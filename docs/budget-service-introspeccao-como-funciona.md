# Como funciona a introspecção de token (recapitulação)

Complementa [`budget-service-migracao-introspeccao.md`](budget-service-migracao-introspeccao.md)
(o passo a passo de implementação) — este documento explica o mecanismo em si, pra tirar
dúvida de "onde entra cada peça" sem precisar reler o código.

## Onboarding de um serviço novo (resumo dos 3 passos)

1. **Liquibase no `workbox-api`**: um changeset novo inserindo uma linha em
   `workbox.api_clients` (`name`, `client_id`, `client_secret_hash` — hash BCrypt
   pré-computado, nunca o segredo em texto plano —, `allowed_grant_types=["CLIENT_SECRET"]`,
   `active=true`).
2. **Properties do serviço novo**: `introspection.uri`, `introspection.client-id`
   (normalmente = nome do serviço, batendo com o `client_id` inserido acima) e
   `introspection.client-secret` (o segredo em texto plano correspondente ao hash do
   passo 1).
3. **Código Java** no serviço novo: implementar o `OpaqueTokenIntrospector` customizado
   e trocar `oauth2ResourceServer().jwt(...)` por `oauth2ResourceServer().opaqueToken(...)`
   no `SecurityConfig` (código completo em `budget-service-migracao-introspeccao.md`).

Depois desses 3 passos, a validação de token passa a funcionar automaticamente pra
**todo** endpoint protegido do serviço — sem precisar chamar nada manualmente em cada
controller.

## Estado atual (atualizado em 2026-09-12): migração concluída

O `budget-service` já foi migrado — `SecurityConfig` usa `oauth2ResourceServer().opaqueToken(...)`
com um `WorkboxTokenIntrospector` próprio, sem `JwtDecoder`/`jwt.secret` em lugar nenhum
do código ou do `application.properties`. Validado ao vivo: token válido → `200`, token
expirado/inválido → `401` com detalhe, e revogação por logout/troca de senha
propagando corretamente (o ganho principal sobre decodificação local).

## O mecanismo, passo a passo (depois de implementado)

O `OpaqueTokenIntrospector` **nunca é chamado manualmente** em nenhum controller. O
ciclo é todo interno ao Spring Security:

1. Uma request chega no serviço com `Authorization: Bearer <token>`.
2. O filtro padrão de resource server do Spring Security
   (`BearerTokenAuthenticationFilter`) intercepta e extrai o token do header.
3. Como o `SecurityConfig` está configurado com
   `.oauth2ResourceServer(oauth2 -> oauth2.opaqueToken(...))`, o Spring invoca
   automaticamente `OpaqueTokenIntrospector.introspect(token)` — é o mesmo ponto do
   ciclo de vida onde antes rodava `JwtDecoder.decode(token)` local.
4. **Só aí**, dentro da implementação do introspector, o `RestClient` faz um `POST`
   HTTP de verdade pro `workbox-api` (`/api/v1/auth/introspect`), autenticado via HTTP
   Basic com `client-id`/`client-secret`, mandando `token=<o mesmo bearer recebido>` no
   corpo.
5. A resposta (`active`/`sub`/`roles`) vira o `OAuth2AuthenticatedPrincipal` que o
   Spring usa pra popular o `SecurityContext` — dali em diante `hasRole(...)`,
   `@PreAuthorize` etc. funcionam igual a hoje, sem mudança de código de negócio.

```
Client → budget-service (Bearer <token>)
              │
              ▼
   BearerTokenAuthenticationFilter (Spring Security)
              │  invoca automaticamente
              ▼
   OpaqueTokenIntrospector.introspect(token)
              │  RestClient.post(...)
              ▼
   workbox-api: POST /api/v1/auth/introspect (HTTP Basic client credentials)
              │  {"active": true, "sub": "...", "roles": [...]}
              ▼
   OAuth2AuthenticatedPrincipal → SecurityContext
```

## Trade-off consciente: chamada de rede síncrona por request

Cada request protegida no serviço consumidor passa a depender de uma chamada HTTP
síncrona pro `workbox-api`:

- **Acoplamento de disponibilidade**: se o `workbox-api` cair, nenhum token valida em
  nenhum serviço consumidor.
- **Latência adicional**: um round-trip de rede a mais por request, antes mesmo de
  chegar no controller.

Cache não foi implementado de propósito no exemplo — cachear o resultado da
introspecção sem um TTL curto e explícito mascararia revogação (logout/troca de senha),
que é justamente o ganho principal desta arquitetura sobre a decodificação local. Se a
latência incomodar na prática depois de validar o fluxo básico, um cache curto (ex.:
Caffeine, TTL de poucos segundos) é a forma correta de mitigar — não trocar por
decodificação local de novo.
