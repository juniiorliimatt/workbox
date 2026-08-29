# Divisão de responsabilidade entre agentes de IA

Este monorepo é desenvolvido com dois agentes de IA em paralelo, cada um responsável
por um submódulo. Esta divisão é uma decisão de projeto — respeite os limites abaixo
independentemente de qual agente estiver lendo este arquivo.

## Backend — um repo/submódulo por microserviço
- Cada microserviço é um repositório GitLab próprio, adicionado como submódulo — **não**
  pacotes dentro de um monólito. Cada um com seu próprio deploy, versionamento e
  `openapi/openapi.yaml`. Ver [`workbox-api/README.md`](workbox-api/README.md) e
  [`budget-service/README.md`](budget-service/README.md) como referência de estrutura
  pro próximo serviço.
- Escopo geral (ambos): API REST, domínio, persistência (JPA/Liquibase), segurança
  (Spring Security/JWT), infra (Gradle, CI, Docker/deploy). Nenhum dos dois desenvolve
  UI/frontend.

### `workbox-api/` — implementação exclusiva do Claude Code
- Responsabilidade de código é **só do Claude Code** — o desenvolvedor não escreve linha
  de código neste repositório, apenas solicita mudanças/features.
- Regras globais em `~/.claude/CLAUDE.md`, copiadas em [`workbox-api/CLAUDE.md`](workbox-api/CLAUDE.md).

### `budget-service/` e demais serviços backend futuros — implementação do desenvolvedor
- O desenvolvedor implementa sozinho. Claude Code atua **só como consultor**: análises,
  recomendações, code review e exemplos de código a seguir — não escreve nem edita
  código de produção diretamente nesses repositórios.
- Regras globais em `~/.claude/CLAUDE.md`, copiadas em
  [`budget-service/CLAUDE.md`](budget-service/CLAUDE.md), continuam valendo como padrão
  de qualidade/convenções a apontar nas revisões — só a autoria de código muda de mãos.

| Serviço | Papel |
|---|---|
| [`workbox-api/`](workbox-api/) | Identidade/autenticação — emite os JWTs (`POST /api/auth/login`) |
| [`budget-service/`](budget-service/) | Domínio de finanças pessoais — *resource server*, valida os JWTs do workbox-api (segredo HS256 compartilhado, sem login próprio) |

**Nomenclatura**: só o `workbox-api` leva sufixo `-api` — é o único ponto de entrada/
emissor de identidade do sistema. Todo microserviço novo (domínio downstream, resource
server) leva sufixo `-service` (repo, role Postgres, schema), seguindo o padrão de
`budget-service`/`budget_service`. Decisão de nomenclatura fixada — não renomear
`workbox-api` nem introduzir `-api` em serviços novos.

**Banco**: um Postgres único (`workbox`), **um schema por microserviço** — não
banco-por-serviço (ver [README raiz](README.md#rodando-localmente)). Cada serviço tem
seu próprio role Postgres, dono só do seu schema, sem `CREATE` no banco e sem acesso ao
schema de outro serviço. Um microserviço novo precisa: role + schema em `initdb/` na
raiz, `DATABASE_URL` apontando pro mesmo banco `workbox`, credenciais do role próprio —
nunca reusar role de outro serviço nem o superusuário `postgres`.

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
