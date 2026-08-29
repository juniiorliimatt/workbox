# workbox

Monorepo pessoal de estudos — espaço único para implementar os backends/microserviços
que eu for precisar ao longo do tempo, cada um em seu próprio submódulo Git. Não segue
necessariamente as melhores práticas de organização de repositório de produção; a
prioridade é ter um lugar central pra prototipar e aprender.

## Estrutura

| Submódulo | Papel | Stack | Docs |
|---|---|---|---|
| [`workbox-api`](workbox-api/) | Backend — identidade/autenticação (emite JWT) | Java 26, Spring Boot 3.5, Gradle 9, PostgreSQL/Liquibase, JWT | [README](workbox-api/README.md) |
| [`budget-service`](budget-service/) | Backend — finanças pessoais (*resource server*, valida JWT do workbox-api) | Java 26, Spring Boot 3.5, Gradle 9, PostgreSQL/Liquibase | [README](budget-service/README.md) |
| [`workbox-app`](workbox-app/) | Frontend | React 18, TypeScript, Vite, MUI | [README](workbox-app/README.md) |

Cada microserviço backend é um repositório GitLab próprio — não pacotes dentro de um
monólito — pra praticar fronteira de deploy/versionamento real entre serviços. São Git
submodules (ver `.gitmodules`).

```bash
git clone --recurse-submodules git@gitlab.com:oojuniin/workbox.git
# ou, se já clonou sem --recurse-submodules:
git submodule update --init --recursive
```

## Espelho no GitHub / git hooks

Cada repositório (este e os 3 submódulos) tem um espelho no GitHub
(`juniiorliimatt/<repo>`), mantido em sincronia por um hook local — não é
subtree/subtree-split, é o mesmo histórico enviado pros dois remotes. Depois de clonar,
em cada repositório (raiz e cada submódulo):

```bash
git remote add github git@github.com:juniiorliimatt/<repo>.git
git config core.hooksPath .githooks
```

Hooks em `.githooks/` (versionados, um conjunto idêntico em cada repositório):

- **`pre-push`**: todo `git push` pro remote `origin` (GitLab) é automaticamente
  espelhado pro remote `github`, ref por ref. Se o remote `github` não estiver
  configurado, não faz nada (não quebra o push normal).
- **`commit-msg`**: prefixa toda mensagem de commit com `[<branch>] - <versão> -`, onde
  `<versão>` vem de `build.gradle` (Gradle) ou `package.json` (npm), ou `unversioned` se
  nenhum existir. Não duplica em amend/merge.

## Divisão entre agentes de IA

Este repositório é desenvolvido com dois agentes de IA em paralelo, cada um dono de um
submódulo — Claude Code no backend, Antigravity no frontend. A divisão de escopo e a
regra de como os dois lados se alinham (via o contrato OpenAPI do backend) estão
formalizadas em **[AGENTS.md](AGENTS.md)**.

## Contrato de API

`workbox-api/openapi/openapi.yaml` é o contrato REST versionado — fonte da verdade do
que a API expõe, consumido pelo frontend e por agentes de IA. Detalhes de como
regenerá-lo estão no [README do workbox-api](workbox-api/README.md#contrato-de-api-openapi).

## Rodando localmente

Pré-requisitos: JDK 26 (toolchain do Gradle resolve automaticamente se estiver
instalado), Node.js e PostgreSQL local (ou só o profile `test` de cada serviço, que usa
H2 em memória e não depende de Postgres).

Postgres via `docker-compose.yml` na raiz — Postgres 18, porta **5433** (não 5432,
pra não colidir com algum outro Postgres já rodando na máquina). `initdb/` provisiona
os databases `workbox`/`budget` e os schemas (`api`, `api_liquibase`, `budget`) na
primeira subida (só roda em volume vazio — se já tiver `.pgdata/`, rode os scripts de
`initdb/` manualmente com `psql`).

```bash
docker compose up -d

# workbox-api (8080) — identidade
cd workbox-api
DATABASE_URL=jdbc:postgresql://localhost:5433/workbox ./gradlew bootRun

# budget-service (8081) — resource server, precisa de um JWT do workbox-api
cd budget-service
DATABASE_URL=jdbc:postgresql://localhost:5433/budget ./gradlew bootRun

# frontend
cd workbox-app
npm install
npm run dev
```
