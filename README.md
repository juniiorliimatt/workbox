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
pra não colidir com algum outro Postgres já rodando na máquina). **Banco único**
(`workbox`), **um schema por microserviço** — não banco-por-serviço. `initdb/`
provisiona, na primeira subida (só roda em volume vazio):

- Extensões (`pgcrypto`, `uuid-ossp`) — instaladas uma vez pelo superusuário, os
  changesets de Liquibase que tentam recriá-las viram no-op.
- Um role Postgres por microserviço (`workbox_service`, `budget_service`), **dono só do seu
  próprio schema** — sem `CREATE` no banco, sem acesso a schema de outro serviço
  (confirmado: `SELECT` cross-schema dá `permission denied`). Cada app se conecta com o
  role do seu próprio serviço, nunca com o superusuário `postgres`.
- Os schemas (`workbox para o workbox-api; `budget` para o budget-service).

Se já tiver `.pgdata/` de antes, rode os scripts de `initdb/` manualmente com `psql`
(nessa ordem: `00`, `01`, `02`).

**Próximo microserviço**: crie um role + schema seguindo o mesmo padrão em
`initdb/`, aponte `DATABASE_URL` pro mesmo banco (`workbox`) e use
`POSTGRES_USER`/`POSTGRES_PASSWORD` do role novo — nunca reuse o role de outro serviço
nem o superusuário.

```bash
docker compose up -d

# workbox-api (8080) — identidade
cd workbox-api
DATABASE_URL=jdbc:postgresql://localhost:5433/workbox ./gradlew bootRun

# budget-service (8081) — resource server, precisa de um JWT do workbox-api
cd budget-service
DATABASE_URL=jdbc:postgresql://localhost:5433/workbox ./gradlew bootRun

# frontend
cd workbox-app
npm install
npm run dev
```

## Rodando tudo em containers

Cada submódulo tem seu próprio `Dockerfile` (multi-stage, usuário non-root) — `docker
compose up --build -d` na raiz sobe Postgres + `workbox-api` + `budget-service` +
`workbox-app`, um comando só, sem precisar entrar em cada submódulo.

`workbox-app` é standalone — nginx serve os assets buildados (`npm run build`, saída
padrão em `dist/`) e faz proxy de `/api/*` pro `workbox-api` dentro da rede do compose,
então o browser nunca precisa de CORS (mesmo origin do ponto de vista dele). Decisão
tomada em 2026-08-29: existia um modo alternativo embutido (`vite build` gerando os
estáticos direto em `workbox-api/src/main/resources/static`, servido pelo próprio
Spring Boot) — descontinuado a favor do container isolado; `workbox-api` não serve
mais SPA nenhum.

Ordem de subida garantida por `depends_on: condition: service_healthy` — Postgres
(`pg_isready`) antes dos backends, backends (`/actuator/health`, liberado sem
autenticação nos dois) antes do front.

**Java fixado em 26** nas 3 imagens (`ARG JAVA_VERSION` no topo de cada `Dockerfile`,
mesma versão do `toolchain` em cada `build.gradle`) — mude nos três lugares juntos se
atualizar, não deixe a versão flutuar entre serviços.

Variáveis de ambiente (todas com default sensato — só precisa de `.env` pra
sobrescrever; copie `.env.example` → `.env`, que é gitignored):

| Variável | Default | Efeito |
|---|---|---|
| `POSTGRES_PORT` | `5433` | Porta do Postgres exposta no **host**. Dentro da rede docker os backends sempre falam com `postgres:5432` — isso nunca muda. |
| `DB_HOST` | `postgres` | Host usado pelos backends pra montar `DATABASE_URL`. Só sobrescreva se apontar pra um Postgres fora do compose. |
| `SPRING_PROFILE` | `dev` | `PROFILE_ACTIVE` passado pro `workbox-api` e pro `budget-service` (`dev`\|`prod`\|`test`). |
| `JWT_SECRET` | fallback de `application.properties` (só estudo local) | Segredo HS256 — **tem que ser idêntico** nos dois backends (`workbox-api` emite, `budget-service` valida). |
| `FRONT_PORT` | `5173` | Porta do `workbox-app` exposta no host. |

```bash
cp .env.example .env   # ajuste se precisar, senão os defaults acima já funcionam
docker compose up --build -d
docker compose ps      # confirma os 4 serviços "healthy"
```
