# workbox

Monorepo pessoal de estudos — espaço único para implementar os backends/microserviços
que eu for precisar ao longo do tempo, cada um em seu próprio submódulo Git. Não segue
necessariamente as melhores práticas de organização de repositório de produção; a
prioridade é ter um lugar central pra prototipar e aprender.

## Estrutura

| Submódulo | Papel | Stack | Docs |
|---|---|---|---|
| [`workbox-api`](workbox-api/) | Backend — identidade/autenticação (emite JWT) | Java 25 LTS, Spring Boot 3.5.16, Gradle 9.7.1, PostgreSQL/Liquibase, JWT | [README](workbox-api/README.md) |
| [`budget-service`](budget-service/) | Backend — finanças pessoais (*resource server*, valida JWT do workbox-api) | Java 25 LTS, Spring Boot 3.5.16, Gradle 9.7.1, PostgreSQL/Liquibase | [README](budget-service/README.md) |
| [`notes-service`](notes-service/) | Backend — notas/documentos pessoais (*resource server*, valida JWT do workbox-api) | Java 25 LTS, Spring Boot 3.5.16, Gradle 9.7.1, MongoDB | [README](notes-service/README.md) |
| [`forza-telemetry-service`](forza-telemetry-service/) | Backend — telemetria do Forza (Data Out UDP → sessões/voltas/resumo de tuning; *resource server*) | Java 25 LTS, Spring Boot 3.5.16, Gradle 9.7.1, PostgreSQL/Liquibase, UDP | [README](forza-telemetry-service/README.md) |
| [`moto-service`](moto-service/) | Backend — moto pessoal: abastecimentos, consumo (km/l), km rodados, troca de óleo e métricas (*resource server*, módulo `MOTO`) | Java 25 LTS, Spring Boot 3.5.16, Gradle 9.7.1, PostgreSQL/Liquibase | [README](moto-service/README.md) |
| [`workbox-app`](workbox-app/) | Frontend | React 18, TypeScript, Vite, MUI | [README](workbox-app/README.md) |

Cada microserviço backend é um repositório GitLab próprio — não pacotes dentro de um
monólito — pra praticar fronteira de deploy/versionamento real entre serviços. São Git
submodules (ver `.gitmodules`).

```bash
git clone --recurse-submodules git@gitlab.com:sonar-group-oojuniiin/workbox.git
# ou, se já clonou sem --recurse-submodules:
git submodule update --init --recursive
```

## Espelho no GitHub / git hooks

Cada repositório (este e os submódulos) tem um espelho no GitHub
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
- **`commit-msg`**: no-op — historicamente prefixava a mensagem com `[<branch>] - <versão> -`,
  descontinuado (2026-08-29) já que o desenvolvimento agora vive numa branch fixa
  (`develop`) e versão passou a ser identificada por tags Git, não por commit.

## Agente de IA

Este repositório é desenvolvido pelo Claude Code, full-stack (backend e frontend) — o
Antigravity deixou de ser usado em 2026-10-03. A divisão de autoria de código por
repositório de backend e as regras de contrato OpenAPI estão formalizadas em
**[CLAUDE.md](CLAUDE.md)**.

## Convenção de commits

Vale pro Claude Code e pro desenvolvedor, em todos os repositórios deste monorepo
(este e os submódulos) — sempre em português (pt-BR), Conventional Commits com o
prefixo de tipo em inglês:

```
<tipo>(<escopo opcional>): <descrição curta e objetiva em português>
```

Tipos aceitos: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `style`, `perf`, `ci`,
`revert`. Diverge de propósito do formato de commit do `~/.claude/CLAUDE.md` global —
regra completa e exemplo em [CLAUDE.md](CLAUDE.md#convenção-de-mensagens-de-commit).

## Contrato de API

`workbox-api/openapi/openapi.yaml` é o contrato REST versionado — fonte da verdade do
que a API expõe, consumido pelo frontend e por agentes de IA. Detalhes de como
regenerá-lo estão no [README do workbox-api](workbox-api/README.md#contrato-de-api-openapi).

## Testes BDD (Cucumber)

Convenção pros backends: cenário de negócio (`.feature`, Gherkin) escrito *antes* da
implementação — fluxo outside-in documentado com diagrama em
[`workbox-api/README.md`](workbox-api/README.md#bdd-com-cucumber-fluxo-de-implementação),
que também tem o exemplo real (login). `budget-service` ainda não tem Cucumber
configurado — ao adicionar, seguir o mesmo padrão.

## Rodando localmente

Pré-requisitos: JDK 25 LTS (toolchain do Gradle resolve automaticamente se estiver
instalado), Node.js e PostgreSQL local (ou só o profile `test` de cada serviço, que usa
H2 em memória e não depende de Postgres).

Postgres via `docker-compose.yml` na raiz — Postgres 18, porta **7050** (não 5432,
pra não colidir com algum outro Postgres já rodando na máquina). **Banco único**
(`workbox`), **um schema por microserviço** — não banco-por-serviço. `initdb/`
provisiona, na primeira subida (só roda em volume vazio):

- Extensões (`pgcrypto`, `uuid-ossp`) — instaladas uma vez pelo superusuário, os
  changesets de Liquibase que tentam recriá-las viram no-op.
- Um role Postgres por microserviço (`workbox_service`, `budget_service`, `forza_service`, `moto_service`), **dono só do seu
  próprio schema** — sem `CREATE` no banco, sem acesso a schema de outro serviço
  (confirmado: `SELECT` cross-schema dá `permission denied`). Cada app se conecta com o
  role do seu próprio serviço, nunca com o superusuário `postgres`.
- Os schemas (`workbox` para o workbox-api; `budget` para o budget-service; `forza` para o forza-telemetry-service; `moto` para o moto-service — num banco já existente, `initdb/04-create-moto-role.sql` cria o role e o schema).

Se já tiver `.pgdata/` de antes, rode os scripts de `initdb/` manualmente com `psql`
(nessa ordem: `00`, `01`, `02`).

**Próximo microserviço relacional**: crie um role + schema seguindo o mesmo padrão em
`initdb/`, aponte `DATABASE_URL` pro mesmo banco (`workbox`) e use
`POSTGRES_USER`/`POSTGRES_PASSWORD` do role novo — nunca reuse o role de outro serviço
nem o superusuário.

MongoDB via o mesmo `docker-compose.yml` — porta **7054**, usado pelo `notes-service`
(schema livre por documento, sem migrations — ver README do serviço). Sem Postgres
equivalente de role/schema por serviço: cada microserviço Mongo futuro usa seu próprio
banco lógico dentro da mesma instância (`notes` hoje).

Redis via o mesmo `docker-compose.yml` — porta **7056**, usado só pelo `workbox-api`
(refresh tokens: TTL nativo por chave, sem job de cleanup agendado — ver README do
serviço). Sem volume: dado puramente efêmero, perder num restart só força re-login.

```bash
docker compose up -d

# workbox-api (7051) — identidade
cd workbox-api
DATABASE_URL=jdbc:postgresql://localhost:7050/workbox ./gradlew bootRun

# budget-service (7052) — resource server, precisa de um JWT do workbox-api
cd budget-service
DATABASE_URL=jdbc:postgresql://localhost:7050/workbox ./gradlew bootRun

# notes-service (7055) — resource server, precisa de um JWT do workbox-api
cd notes-service
MONGODB_URI="mongodb://root:MyS3cur3M0ngoPassw0rd2026!@localhost:7054/notes?authSource=admin" ./gradlew bootRun

# forza-telemetry-service (7057 + UDP 5310) — resource server, precisa de um JWT do workbox-api
cd forza-telemetry-service
DATABASE_URL="jdbc:postgresql://localhost:7050/workbox?reWriteBatchedInserts=true" ./gradlew bootRun

# moto-service (7059) — resource server, precisa de um JWT do workbox-api com o módulo MOTO
cd moto-service
./gradlew bootRun

# frontend
cd workbox-app
npm install
npm run dev   # http://localhost:7053
```

## Rodando tudo em containers

Cada submódulo tem seu próprio `Dockerfile` (multi-stage, usuário non-root) — `docker
compose up --build -d` na raiz sobe Postgres + MongoDB + Redis + `workbox-api` +
`budget-service` + `notes-service` + `forza-telemetry-service` + `moto-service` + `workbox-app`, um comando só, sem precisar entrar em
cada submódulo.

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

**Java 25 LTS** nos quatro backends (`ARG JAVA_VERSION` em cada `Dockerfile` +
`java.toolchain` em cada `build.gradle`) — mude nos oito lugares juntos se atualizar,
não deixe a versão flutuar entre serviços. `workbox-app` é Node 22 (`ARG NODE_VERSION`
no `Dockerfile` do front), não imagem Java.

Variáveis de ambiente (todas com default sensato — só precisa de `.env` pra
sobrescrever; copie `.env.example` → `.env`, que é gitignored):

| Variável | Default | Efeito |
|---|---|---|
| `POSTGRES_PORT` | `7050` | Porta do Postgres exposta no **host**. Dentro da rede docker os backends sempre falam com `postgres:5432` — isso nunca muda. |
| `DB_HOST` | `postgres` | Host usado pelos backends pra montar `DATABASE_URL`. Só sobrescreva se apontar pra um Postgres fora do compose. |
| `SPRING_PROFILE` | `dev` | `PROFILE_ACTIVE` passado pro `workbox-api` e pro `budget-service` (`dev`\|`prod`\|`test`). |
| `JWT_SECRET` | fallback de `application.properties` (só estudo local) | Segredo HS256 usado só pelo `workbox-api`, que assina os access tokens na emissão (login). `budget-service` não conhece esse segredo — valida token via introspecção remota (ver [`docs/budget-service-migracao-introspeccao.md`](docs/budget-service-migracao-introspeccao.md)). |
| `INTROSPECTION_CLIENT_ID` / `INTROSPECTION_CLIENT_SECRET` | `budget-service` / `introspect-dev-secret-change-me` | Client credentials que o `budget-service` usa (HTTP Basic) pra chamar `POST /api/v1/auth/introspect` no `workbox-api` — tem que bater com uma linha ativa em `workbox.api_clients` (ver README do `workbox-api`). |
| `FRONT_PORT` | `7053` | Porta do `workbox-app` exposta no host. |
| `WORKBOX_API_PORT` | `7051` | Porta do `workbox-api` exposta no host — pra testar direto (Postman, curl) sem passar pelo proxy do front. |
| `BUDGET_SERVICE_PORT` | `7052` | Idem, pro `budget-service`. |
| `MONGO_PORT` | `7054` | Porta do MongoDB exposta no **host**. Dentro da rede docker os backends sempre falam com `mongo:27017` — isso nunca muda. |
| `MONGO_HOST` | `mongo` | Host usado pelo `notes-service` pra montar `MONGODB_URI`. Só sobrescreva se apontar pra um Mongo fora do compose. |
| `MONGO_USER` / `MONGO_PASSWORD` | `root` / `MyS3cur3M0ngoPassw0rd2026!` | Credenciais do usuário root do Mongo — só têm efeito automático em volume vazio (`MONGO_INITDB_ROOT_USERNAME`/`PASSWORD`); num volume já existente, crie o usuário manualmente antes (ver `notes-service/README.md`). |
| `NOTES_SERVICE_PORT` | `7055` | Idem, pro `notes-service`. |
| `NOTES_INTROSPECTION_CLIENT_ID` / `NOTES_INTROSPECTION_CLIENT_SECRET` | `notes-service` / `MyS3cur3Cli3ntS3cr3t!N0tes!` | Idem, client credentials do `notes-service`. |
| `FORZA_SERVICE_PORT` | `7057` | Porta da API REST do `forza-telemetry-service` exposta no host. |
| `FORZA_UDP_PORT` | `5310` | Porta **UDP** exposta no host pra o Data Out do Forza (Xbox → IP do PC). Evite 5200–5300 (o Forza Horizon usa essa faixa) e libere UDP de entrada no firewall. |
| `FORZA_INTROSPECTION_CLIENT_ID` / `FORZA_INTROSPECTION_CLIENT_SECRET` | `forza-telemetry-service` / `MyS3cur3Cli3ntS3cr3t!F0rza!` | Idem, client credentials do `forza-telemetry-service`. |
| `MOTO_SERVICE_PORT` | `7059` | Porta da API REST do `moto-service` exposta no host. |
| `MOTO_INTROSPECTION_CLIENT_ID` / `MOTO_INTROSPECTION_CLIENT_SECRET` | `moto-service` / `MyS3cur3Cli3ntS3cr3t!M0t0!` | Idem, client credentials do `moto-service`. |
| `REDIS_PORT` | `7056` | Porta do Redis exposta no **host**. Dentro da rede docker o `workbox-api` sempre fala com `redis:6379` — isso nunca muda. |
| `REDIS_HOST` | `redis` | Host usado pelo `workbox-api` pra montar a conexão Redis. Só sobrescreva se apontar pra um Redis fora do compose. |
| `REDIS_PASSWORD` | `MyS3cur3R3disP@ssw0rd2026!` | Senha do Redis (`--requirepass`) — precisa bater entre o serviço `redis` e o `workbox-api`. |

```bash
cp .env.example .env   # ajuste se precisar, senão os defaults acima já funcionam
docker compose up --build -d
docker compose ps      # confirma os 8 serviços "healthy"
```

## Compose de produção

`docker-compose.prod.yml` sobe o mesmo stack do dev (Postgres, Redis, MongoDB, `workbox-api`,
`budget-service`, `notes-service`, `forza-telemetry-service`, `moto-service`, `workbox-app`) mais o Caddy (TLS
automático), com diferenças: **nenhum segredo tem default** (`${VAR:?...}` — o compose recusa
subir sem eles), nenhum serviço expõe porta HTTP no host (só o Caddy; exceção: UDP 5310 do
forza, a restringir no firewall ao IP do console) e Redis/MongoDB exigem senha.

```bash
cp .env.prod.example .env.prod   # preencha tudo (senhas, JWT_SECRET, domínios, client credentials)
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

Cada resource server (`budget-service`, `notes-service`, `forza-telemetry-service`, `moto-service`) precisa de um
cliente ativo em `workbox.api_clients` com o secret real — as linhas seed dos changesets usam
secrets de estudo; insira os reais via changeset novo e desative as seeds (ver
[`workbox-api/README.md`](workbox-api/README.md#clientes-de-introspecção-resource-servers)). O
arquivo foi validado com `docker compose config` (variáveis e interpolação), mas ainda **não foi
subido de verdade** numa VPS.

## Backup e restore do banco

### Pela aplicação (Admin → "Backup do banco", só ADMIN)

O [`backup-service`](backup-service/) gera o `pg_dump` (todos os schemas) por uma tela: botão
"Gerar backup agora", lista com **o caminho do arquivo no host** (`./backups`, a mesma pasta dos
scripts), download e exclusão. Cifra opcional com uma senha que você digita na hora (openssl
AES-256-CBC + PBKDF2, a senha nunca é gravada: **sem ela o backup não abre**). **Restore não existe
na tela** — só por script:

```bash
scripts/decrypt-backup.sh backups/workbox_<ts>.dump.enc      # só se foi cifrado; pede a senha
docker compose --profile backup run --rm restore /backups/workbox_<ts>.dump
```

O serviço usa um role só de leitura (`backup_service`, `pg_read_all_data`, `initdb/03-create-backup-role.sql`).
Num banco que já existia, o `initdb/` não roda: execute o arquivo à mão
(`docker exec -i workbox-postgres psql -U postgres -d workbox < initdb/03-create-backup-role.sql`).
`BACKUP_HOST_DIR` (preenchido pelo `scripts/up-all.sh`) é só o caminho exibido na tela. Backup no mesmo
disco do banco não protege contra perda do disco: baixe uma cópia pela tela e guarde fora do servidor.

### Pelos scripts

`scripts/backup-db.sh`/`scripts/restore-db.sh` — `pg_dump`/`pg_restore --format=custom`
(comprimido, permite restore seletivo), banco `workbox` inteiro, todos os schemas de
uma vez (`workbox` do `workbox-api`, `budget` do `budget-service`). Rodam dentro de
serviços dedicados do compose (`profiles: ["backup"]` — nunca sobem com `docker compose
up` normal, só quando chamados explicitamente):

```bash
# Backup - grava em ./backups/workbox_<timestamp>.dump (gitignored, dado real nunca vai pro repo)
docker compose --profile backup run --rm backup

# Restore - path é dentro do container, onde ./backups do host vira /backups
docker compose --profile backup run --rm restore /backups/workbox_20260913_120000.dump
```

Restore usa `--clean --if-exists`: sobrescreve os objetos existentes que colidirem com
o backup, não faz merge — confirme que está apontando pro Postgres certo antes de
rodar (`PGHOST` default é `${DB_HOST:-postgres}`, o container do compose, não um banco
remoto). Scripts pensados pra rodar sem editar nada na maioria dos casos — só
sobrescrever `PGHOST`/`PGUSER`/`PGPASSWORD`/`PGDATABASE` via `environment:` no
`docker-compose.yml` se precisar apontar pra outro banco (ex.: `docker-compose.prod.yml`
usa o mesmo par usuário/banco `postgres`/`workbox`, só a senha muda).

## Deploy futuro no GCP (planejado, não implementado)

Decisão registrada em 2026-08-31 pra quando o deploy real for feito — não precisa ficar
online o tempo todo, só quando for usar. Documentado aqui pra não redescutir do zero na
hora de executar. Comparado com Azure Container Apps e AWS (App Runner/Fargate/Lambda)
antes de fechar — GCP venceu por ter scale-to-zero nativo por request (Azure também tem,
mas com Postgres mais problemático) e um free tier "always free" de verdade, não só nos
primeiros 12 meses (diferencial vs. AWS).

### Serviço escolhido: Google Cloud Run

Scale-to-zero automático por request desde o desenho do produto (`min-instances=0`,
sem precisar de orquestração própria como seria no AWS Fargate). Cold start menor que os
concorrentes pra JVM (tem CPU boost específico de startup). Descartado: Cloud Run não
resolve workload stateful (Postgres) — ver abaixo.

### Arquitetura alvo

- `workbox-api`, `budget-service`, `workbox-app` → 3 serviços Cloud Run separados,
  `min-instances=0`, cada um com sua imagem.
- **Postgres**: **não** em Cloud Run (sem suporte adequado a disco persistente/POSIX
  pra um banco relacional) e **não** em Cloud SQL (não escala a zero, fica cobrando
  mesmo ocioso). Em vez disso, uma VM `e2-micro` no **Always Free tier** (região
  `us-central1`, `us-west1` ou `us-east1` — só nessas o e2-micro é gratuito pra sempre),
  rodando o Postgres via Docker direto, ligada 24/7 sem custo. Resolve o problema de
  persistência sem precisar que o Postgres escale a zero.
- **Registry de imagens**: Artifact Registry (free tier de 0,5GB, suficiente pras 3
  imagens) ou GHCR, já que os repos são espelhados no GitHub (ver [Espelho no
  GitHub](#espelho-no-github--git-hooks)).

### Passo a passo

```bash
# 1. Projeto + APIs necessárias
gcloud projects create workbox-prod --set-as-default
gcloud services enable run.googleapis.com artifactregistry.googleapis.com compute.googleapis.com

# 2. Repositório no Artifact Registry + build/push das 3 imagens de app
gcloud artifacts repositories create workbox --repository-format=docker --location=us-central1
gcloud auth configure-docker us-central1-docker.pkg.dev

docker build -t us-central1-docker.pkg.dev/workbox-prod/workbox/workbox-api:latest ./workbox-api
docker push us-central1-docker.pkg.dev/workbox-prod/workbox/workbox-api:latest
# ... idem workbox-app e budget-service

# 3. Deploy de cada serviço com scale-to-zero
gcloud run deploy workbox-api \
  --image us-central1-docker.pkg.dev/workbox-prod/workbox/workbox-api:latest \
  --region us-central1 --min-instances=0 --max-instances=1 \
  --set-env-vars DATABASE_URL=jdbc:postgresql://<ip-da-vm>:5432/workbox
# ... idem budget-service e workbox-app (com a URL do workbox-api já publicada)

# 4. VM Always Free pro Postgres (região elegível, tipo exato do free tier)
gcloud compute instances create workbox-postgres \
  --zone=us-central1-a --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=30GB --boot-disk-type=pd-standard

# na VM: instalar Docker e subir o Postgres com o initdb/ atual do repo
# (mesma imagem/scripts já usados no docker-compose.yml local)
```

### O que NÃO fazer

- **Não** rodar o Postgres em Cloud Run — sem garantia de disco persistente adequado
  pra um banco relacional (GCS FUSE não é POSIX-safe pra isso).
- **Não** usar Cloud SQL "pra ser mais gerenciado" — não escala a zero, fica cobrando
  mesmo com uso esporádico; o `e2-micro` Always Free já resolve isso de graça.
- **Não** criar a VM Always Free fora de `us-central1`/`us-west1`/`us-east1` — fora
  dessas regiões o `e2-micro` deixa de ser gratuito e passa a cobrar normal.
- **Não** deixar a VM do Postgres exposta na internet pública sem firewall restritivo —
  liberar a porta 5432 só pro IP/range do Cloud Run (via VPC connector) ou usar Cloud
  SQL Auth Proxy-like tunneling; nunca `0.0.0.0/0` na regra de firewall.
- **Não** assumir que o cold start é instantâneo — primeira request após período
  ocioso leva alguns segundos; não é adequado pra uma API que precise responder sempre
  "a quente".
- **Não** commitar `JWT_SECRET`/credenciais reais em `.env` nem em variável de ambiente
  direto no manifest do Cloud Run — usar Secret Manager na hora do deploy real.

### Custo esperado

Cloud Run: free tier "always free" (2M requests/mês + 180k vCPU-s + 360k GiB-s) cobre
uso esporádico de estudo com folga — tendência de ~$0/mês pros 3 serviços de app. VM
`e2-micro` Always Free: $0/mês fixo (dentro do limite de 1 instância, nas regiões
elegíveis), cobrindo o Postgres rodando 24/7 sem precisar resolver scale-to-zero pra ele.
Trade-off aceito: latência maior pro Brasil (região é americana, não há Always Free em
`southamerica-east1`). Valores públicos do GCP são em USD.
