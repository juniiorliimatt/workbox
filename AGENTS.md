# Divisão de responsabilidade entre agentes de IA

Este monorepo é desenvolvido com dois agentes de IA em paralelo, cada um responsável
por um submódulo. Esta divisão é uma decisão de projeto — respeite os limites abaixo
independentemente de qual agente estiver lendo este arquivo.

## Backend — um repo/submódulo por microserviço
- Agente: **Claude Code** (regras globais em `~/.claude/CLAUDE.md` do desenvolvedor,
  copiadas em `CLAUDE.md` de cada submódulo backend para o projeto carregar as mesmas
  instruções em qualquer máquina).
- Escopo: API REST, domínio, persistência (JPA/Liquibase), segurança (Spring Security/JWT),
  infra (Gradle, CI, Docker/deploy).
- Não desenvolve UI/frontend.
- Cada microserviço é um repositório GitLab próprio, adicionado como submódulo — **não**
  pacotes dentro de um monólito. Cada um com seu próprio deploy, versionamento e
  `openapi/openapi.yaml`. Ver [`workbox-api/README.md`](workbox-api/README.md) e
  [`budget-service/README.md`](budget-service/README.md) como referência de estrutura
  pro próximo serviço.

| Serviço | Papel |
|---|---|
| [`workbox-api/`](workbox-api/) | Identidade/autenticação — emite os JWTs (`POST /api/auth/login`) |
| [`budget-service/`](budget-service/) | Domínio de finanças pessoais — *resource server*, valida os JWTs do workbox-api (segredo HS256 compartilhado, sem login próprio) |

## Frontend — `workbox-app/`
- Agente: **Antigravity** (regras globais em `~/GEMINI.md` do desenvolvedor, copiadas em
  [`workbox-app/GEMINI.md`](workbox-app/GEMINI.md) pelo mesmo motivo).
- Escopo: componentes, styling, state management de tela, testes visuais.
- Não desenvolve API/domínio/persistência.

## Contrato entre os lados

Cada microserviço backend versiona seu próprio `<serviço>/openapi/openapi.yaml` — a
**fonte da verdade** do que aquela API expõe. Regras (valem pra todos os serviços):

- Nenhum client (frontend, outro microserviço, agente de IA) deve assumir comportamento
  de endpoint que não esteja descrito no `openapi.yaml` daquele serviço.
- Qualquer mudança de contrato (novo endpoint, novo campo, mudança de schema) exige
  regenerar o arquivo (`./gradlew generateOpenApiDocs` dentro do submódulo) e commitar
  junto com a mudança de código. O CI (`contract-drift-check` em cada
  `.gitlab-ci.yml`) falha o pipeline se o arquivo commitado divergir do gerado a partir
  do código.
- Mudanças que exigem um endpoint novo ou diferente do que já está no contrato de outro
  serviço devem ser solicitadas ao dono daquele serviço, não assumidas/mockadas
  silenciosamente.
- Autenticação entre microserviços: `workbox-api` é o único que emite JWT (login). Os
  demais são *resource servers* — validam o token com o mesmo segredo HS256
  (`JWT_SECRET`), sem reimplementar login.
