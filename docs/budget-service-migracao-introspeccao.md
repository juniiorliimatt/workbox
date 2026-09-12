# Migração do budget-service pra introspecção de token via workbox-api

Passo a passo pra trocar a validação local de JWT (decodificação com `jwt.secret`
compartilhado) por consulta remota ao `workbox-api` via `POST /api/v1/auth/introspect`.
Motivo da mudança: centralizar a validação de token e o controle de permissão no
`workbox-api` (único emissor de identidade) — o `budget-service` deixa de precisar
conhecer o segredo HS256 e passa a confiar no que o `workbox-api` responder, inclusive
revogação (logout/troca de senha) que uma decodificação local nunca enxergaria.

**Nada muda do ponto de vista do client** (frontend, Postman, outro serviço): a chamada
continua sendo `Authorization: Bearer <access_token>` emitido por
`POST /api/v1/auth/login` no `workbox-api`, exatamente como hoje. Só a validação
*interna* do `budget-service` muda de local (decodificar o JWT) pra remota (perguntar
pro `workbox-api`).

## Pré-requisitos já prontos (lado workbox-api)

- Endpoint `POST /api/v1/auth/introspect` implementado — recebe `token` (form
  `application/x-www-form-urlencoded`), autenticado via HTTP Basic (client credentials),
  responde `{"active": bool, "sub": string, "roles": string[], "exp": number}`. Nunca
  401 pra token inválido/expirado, sempre 200 com `active=false`.
- Clientes autorizados vivem na tabela `workbox.api_clients` (ver
  [`workbox-api/README.md`](../workbox-api/README.md#clientes-de-introspecção-resource-servers)).
  O `budget-service` já tem uma linha seed (`client_id=budget-service`) pra uso local/dev.
- `docker-compose.yml`/`docker-compose.prod.yml`/`.env.example` na raiz já têm as env
  vars `INTROSPECTION_URI`, `INTROSPECTION_CLIENT_ID`, `INTROSPECTION_CLIENT_SECRET`
  wireadas no serviço `budget-service` — nada a mudar em infra.

Nenhuma dependência nova é necessária no `build.gradle` — o starter
`spring-boot-starter-oauth2-resource-server` (já presente) cobre `opaqueToken(...)`, e
`spring-boot-starter-web` (já presente, transitivamente) cobre `RestClient`/`RestTemplate`
pra chamar o endpoint.

## Passo 1 — `application.properties`

Adicionar (removendo `jwt.secret` só no Passo 5, depois de validar que a migração
funciona):

```properties
introspection.uri=${INTROSPECTION_URI:http://localhost:8080/api/v1/auth/introspect}
introspection.client-id=${INTROSPECTION_CLIENT_ID:budget-service}
introspection.client-secret=${INTROSPECTION_CLIENT_SECRET:introspect-dev-secret-change-me}
```

## Passo 2 — implementar o `OpaqueTokenIntrospector`

O suporte nativo do Spring Security pra opaque token (`spring.security.oauth2.resourceserver.opaquetoken.introspection-uri`
via properties, sem código) **não serve aqui de forma direta**: ele mapeia a claim
`scope` (string espaço-separada) em authorities `SCOPE_*` — mas o `workbox-api` devolve
`roles` (lista já prefixada `ROLE_*`). Por isso precisa de um introspector customizado,
pra mapear `roles` → `GrantedAuthority` do jeito que o restante do código já espera
(`hasRole(...)` funcionando igual ao fluxo atual).

Criar `br.com.budget.config.WorkboxTokenIntrospector`:

```java
package br.com.budget.config;

import java.time.Instant;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.core.OAuth2AuthenticatedPrincipal;
import org.springframework.security.oauth2.server.resource.introspection.BadOpaqueTokenException;
import org.springframework.security.oauth2.server.resource.introspection.OpaqueTokenIntrospector;
import org.springframework.security.oauth2.server.resource.introspection.OAuth2IntrospectionAuthenticatedPrincipal;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

public class WorkboxTokenIntrospector implements OpaqueTokenIntrospector {

    private final RestClient restClient;
    private final String introspectionUri;
    private final String clientId;
    private final String clientSecret;

    public WorkboxTokenIntrospector(RestClient restClient, String introspectionUri,
                                     String clientId, String clientSecret) {
        this.restClient = restClient;
        this.introspectionUri = introspectionUri;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    @Override
    public OAuth2AuthenticatedPrincipal introspect(String token) {
        MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("token", token);

        Map<String, Object> result;
        try {
            // ParameterizedTypeReference em vez de Map.class: Map.class é um Class raw, sem
            // informação genérica — o retorno viraria Map bruto, gerando unchecked assignment
            // ao atribuir em Map<String, Object>. ParameterizedTypeReference preserva o tipo
            // genérico de verdade pro Jackson desserializar.
            result = restClient.post()
                    .uri(introspectionUri)
                    .headers(headers -> headers.setBasicAuth(clientId, clientSecret))
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(body)
                    .retrieve()
                    .body(new ParameterizedTypeReference<Map<String, Object>>() { });
        } catch (RestClientException e) {
            throw new BadOpaqueTokenException("Falha ao consultar introspecção no workbox-api", e);
        }

        if (result == null || !Boolean.TRUE.equals(result.get("active"))) {
            throw new BadOpaqueTokenException("Token inativo");
        }

        // OpaqueTokenAuthenticationProvider (Spring Security) lê a claim "exp" do mapa de
        // atributos com um cast direto pra Instant — (Instant) attributes.get("exp") — sem
        // converter a partir de epoch-seconds. O workbox-api devolve "exp" como número JSON
        // puro, que o Jackson desserializa como Integer/Long dentro do Map<String,Object> —
        // sem essa conversão, todo token VÁLIDO (o único caminho que chega até aqui) derruba
        // um ClassCastException dentro do próprio Spring, disfarçado de 401 genérico.
        Map<String, Object> attributes = new HashMap<>(result);
        Object exp = attributes.get("exp");
        if (exp instanceof Number number) {
            attributes.put("exp", Instant.ofEpochSecond(number.longValue()));
        }

        @SuppressWarnings("unchecked")
        List<String> roles = (List<String>) result.getOrDefault("roles", List.of());
        // .<GrantedAuthority>map(...) força o tipo do Stream — sem isso, toList() infere
        // List<SimpleGrantedAuthority>, que não é atribuível a Collection<GrantedAuthority>
        // (generics em Java são invariantes, mesmo SimpleGrantedAuthority implementando
        // GrantedAuthority).
        Collection<GrantedAuthority> authorities = roles.stream()
                .<GrantedAuthority>map(SimpleGrantedAuthority::new)
                .toList();

        return new OAuth2IntrospectionAuthenticatedPrincipal((String) result.get("sub"), attributes, authorities);
    }
}
```

`BadOpaqueTokenException` faz o Spring Security responder 401 (mesmo contrato de hoje
pra token inválido/expirado) — não precisa mexer no `RestExceptionHandler`.

## Passo 3 — registrar o bean e trocar o `SecurityConfig`

Em `br.com.budget.config.SecurityConfig`, trocar o bloco de JWT local:

```java
// REMOVER:
// @Value("${jwt.secret}") private String jwtSecret;
// @Bean public JwtDecoder jwtDecoder() { ... }
// private JwtAuthenticationConverter jwtAuthenticationConverter() { ... }
// httpSecurity.oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(...)))
```

Por:

```java
@Value("${introspection.uri}") private String introspectionUri;
@Value("${introspection.client-id}") private String introspectionClientId;
@Value("${introspection.client-secret}") private String introspectionClientSecret;

@Bean
public OpaqueTokenIntrospector opaqueTokenIntrospector() {
    return new WorkboxTokenIntrospector(RestClient.create(), introspectionUri,
            introspectionClientId, introspectionClientSecret);
}

// dentro de securityFilterChain(HttpSecurity httpSecurity, OpaqueTokenIntrospector introspector):
httpSecurity.oauth2ResourceServer(oauth2 -> oauth2.opaqueToken(opaque -> opaque.introspector(introspector)));
```

Resto do `SecurityConfig` (CORS, `authorizeHttpRequests`, `csrf().disable()`,
`httpBasic().disable()`) fica igual — só o bloco de autenticação Bearer muda de
`jwt(...)` pra `opaqueToken(...)`.

## Passo 4 — ajustar os testes

`RevenueControllerTest` usa
`SecurityMockMvcRequestPostProcessors.jwt()` pra simular autenticação — isso monta um
`Jwt` no contexto, que só faz sentido pro fluxo antigo. Com opaque token, o
equivalente é `SecurityMockMvcRequestPostProcessors.opaqueToken()`:

```java
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.opaqueToken;

mockMvc.perform(get("/api/revenues")
        .with(opaqueToken().authorities(new SimpleGrantedAuthority("ROLE_USER"))))
```

Não precisa mockar o `OpaqueTokenIntrospector` nem subir uma chamada HTTP de verdade
nesses testes — o postprocessor injeta a autenticação direto no contexto de segurança,
sem passar pelo filtro real.

## Passo 5 — remover o `jwt.secret`, validar e limpar

1. Suba os dois serviços juntos (`docker compose up -d --build`) e teste manualmente: um
   login real no `workbox-api`, usar o `access_token` pra chamar `GET /api/revenues` no
   `budget-service` — precisa funcionar igual a antes.
2. Teste também o caso negativo: token expirado/inválido → 401 (mesmo contrato de hoje).
3. Teste revogação: logar, chamar `/api/v1/auth/logout` no workbox-api, tentar usar o
   mesmo access token no budget-service → agora deve dar 401 (**isso não acontecia
   antes** com decodificação local — é o ganho real da migração).
4. Só depois de confirmar os 3 pontos acima: remover `jwt.secret`/`JWT_SECRET` de
   `application.properties` e do bloco `budget-service` em `docker-compose.yml`/
   `docker-compose.prod.yml` (raiz do monorepo) — não é mais necessário.
5. Regerar o contrato (`./gradlew generateOpenApiDocs`) e conferir `git diff` — não deve
   haver mudança no `openapi.yaml` (o mecanismo de auth do lado do client continua
   `Authorization: Bearer`, isso não muda no contrato observável).

## O que NÃO fazer

- **Não** usar o suporte declarativo puro do Spring
  (`spring.security.oauth2.resourceserver.opaquetoken.introspection-uri` via properties,
  sem bean customizado) — ele descarta a claim `roles` e monta authorities `SCOPE_*`,
  quebrando qualquer `hasRole(...)` existente.
- **Não** cachear o resultado da introspecção sem TTL curto e explícito, se decidir
  adicionar cache no futuro por performance — do contrário logout/revogação (o ganho
  principal desta migração) fica mascarado até o cache expirar.
- **Não** apontar `introspection.uri` pra um valor sem fallback de dev — sem
  `INTROSPECTION_URI` setado, o default `http://localhost:8080/...` só funciona rodando
  os dois serviços fora de container; dentro do compose é sempre `http://workbox-api:8080/...`
  (já wireado).
