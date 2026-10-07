# Workbox — instruções do projeto

> Carregado automaticamente pelo Claude Code em toda sessão dentro do monorepo, inclusive
> nos submódulos (o Claude Code lê os `CLAUDE.md` dos diretórios pai). Complementa as
> regras globais do usuário em `~/.claude/CLAUDE.md`.

## Divisão de responsabilidade

Este monorepo é desenvolvido por **um único agente de IA: o Claude Code, full-stack** —
backend, frontend, persistência, infra e a integração entre as camadas. Desde 2026-10-03
o Antigravity (`GEMINI.md`) **deixou de ser usado**: o frontend (`workbox-app/`) passou a
ser desenvolvido pelo Claude Code, e a antiga regra "Claude só mexe no backend" foi
revogada. O que continua valendo é a **autoria de código por repositório de backend**,
descrita abaixo.

## Backend — um repo/submódulo por microserviço
- Cada microserviço é um repositório GitLab próprio, adicionado como submódulo — **não**
  pacotes dentro de um monólito. Cada um com seu próprio deploy, versionamento e
  `openapi/openapi.yaml`. Ver [`workbox-api/README.md`](workbox-api/README.md) e
  [`budget-service/README.md`](budget-service/README.md) como referência de estrutura
  pro próximo serviço.
- Escopo backend: API REST, domínio, persistência (JPA/Liquibase), segurança
  (Spring Security/JWT), infra (Gradle, CI, Docker/deploy).

### `workbox-api/` — implementação exclusiva do Claude Code
- Responsabilidade de código é **só do Claude Code** — o desenvolvedor não escreve linha
  de código neste repositório, apenas solicita mudanças/features.
- Regras específicas do serviço em [`workbox-api/CLAUDE.md`](workbox-api/CLAUDE.md).

### `budget-service/` e demais serviços backend futuros — padrão: implementação do desenvolvedor
- **Padrão**: o desenvolvedor implementa sozinho. Claude Code atua **só como consultor**:
  análises, recomendações, code review e exemplos de código a seguir — não escreve nem
  edita código de produção diretamente nesses repositórios. As regras globais de
  qualidade (`~/.claude/CLAUDE.md`) e as do `CLAUDE.md` de cada serviço continuam sendo o
  padrão a apontar nas revisões — só a autoria de código muda de mãos.
- **Exceção vigente — permissão total temporária**: `budget-service`, `notes-service`,
  `forza-telemetry-service` e `moto-service` estão com autorização explícita do desenvolvedor
  pro Claude Code implementar tudo (budget: antes de 2026-09-15; notes: 2026-09-16; forza:
  2026-10-03; moto: 2026-10-06). A exceção é **por serviço**, nunca herdada: um serviço novo
  volta ao padrão "consultor" até o desenvolvedor dizer o contrário. Em dúvida se ainda vale
  (longo intervalo sem tocar no serviço, mudança de tom), pergunte.

### Mapa de `CLAUDE.md` por repositório

Cada serviço tem o seu `CLAUDE.md` com o que é específico dele (stack, estrutura, portas,
contratos, convenções de teste, armadilhas). **Leia o do serviço antes de mexer nele**;
este arquivo cobre só o que vale pro monorepo inteiro.

| Repositório | Porta (host) | Papel | Instruções específicas |
|---|---|---|---|
| [`workbox-api/`](workbox-api/) | 7051 | Identidade/autenticação — emite os JWTs (`POST /api/v1/auth/login`) e expõe a introspecção. Postgres (schema `workbox`) + Redis (refresh tokens) | [`workbox-api/CLAUDE.md`](workbox-api/CLAUDE.md) |
| [`budget-service/`](budget-service/) | 7052 | Domínio de finanças pessoais — *resource server*, valida os JWTs do workbox-api via introspecção remota. Postgres (schema `budget`) | [`budget-service/CLAUDE.md`](budget-service/CLAUDE.md) |
| [`notes-service/`](notes-service/) | 7055 | Notas/documentos pessoais (conteúdo livre, sem schema fixo) — *resource server*, mesmo padrão de introspecção. **MongoDB**, não Postgres — primeiro serviço do monorepo a usar um banco não-relacional | [`notes-service/CLAUDE.md`](notes-service/CLAUDE.md) |
| [`forza-telemetry-service/`](forza-telemetry-service/) | 7057 + UDP 5310 | Telemetria do Forza (Data Out UDP → sessões, voltas e resumo de tuning) — *resource server*, mesmo padrão de introspecção. Postgres, schema `forza`. Ainda não registrado em `.gitmodules` (sem repo no GitLab, repo git local sem commits) | [`forza-telemetry-service/CLAUDE.md`](forza-telemetry-service/CLAUDE.md) |
| [`backup-service/`](backup-service/) | 7058 | Backup do Postgres pela tela (só ADMIN): `pg_dump` de todos os schemas numa pasta (`./backups`), listar/baixar/apagar, cifra opcional por senha. *Resource server*, **sem banco próprio** (arquivos + metadados em disco), role Postgres só-leitura `backup_service`. **Sem restore na API/tela, de propósito** — só `scripts/restore-db.sh`. Submódulo registrado em `.gitmodules` (repo próprio no GitLab, `main` padrão + `develop`) | [`backup-service/CLAUDE.md`](backup-service/CLAUDE.md) |
| [`moto-service/`](moto-service/) | 7059 | Moto pessoal: abastecimentos, consumo (km/l), km rodados, troca de óleo (próxima por km e tempo) e métricas mensais/anuais — *resource server*, mesmo padrão de introspecção, módulo `MOTO`. Postgres, schema `moto`. Submódulo registrado em `.gitmodules` (repo **privado** no GitLab, grupo `sonar-group-oojuniiin`, espelhado no GitHub `juniiorliimatt/moto-service` pelo hook `pre-push`; `main` padrão + `develop`; nenhum dos dois tem CI de GitHub — só o `.gitlab-ci.yml`) | [`moto-service/CLAUDE.md`](moto-service/CLAUDE.md) |
| [`workbox-app/`](workbox-app/) | 7053 | Frontend SPA (React/TS/Vite/MUI). Consome `workbox-api`, `budget-service`, `forza-telemetry-service`, `backup-service` e `moto-service` | [`workbox-app/CLAUDE.md`](workbox-app/CLAUDE.md) |

O frontend consome `workbox-api`, `budget-service`, `forza-telemetry-service` (módulo
`/forza`) e `moto-service` (módulo `/moto`). Ele ainda **não** consome o `notes-service` (o proxy do Vite/nginx não roteia
`/api/v1/documents`) — ligar exige rota nova em `workbox-app/vite.config.ts`,
`workbox-app/nginx.conf.template` e o upstream no `docker-compose.yml`.

**Nomenclatura**: só o `workbox-api` leva sufixo `-api` — é o único ponto de entrada/
emissor de identidade do sistema. Todo microserviço novo (domínio downstream, resource
server) leva sufixo `-service` (repo, role Postgres, schema), seguindo o padrão de
`budget-service`/`budget_service`. Decisão de nomenclatura fixada — não renomear
`workbox-api` nem introduzir `-api` em serviços novos.

**Banco**: um Postgres único (`workbox`), **um schema por microserviço relacional** — não
banco-por-serviço (ver [README raiz](README.md#rodando-localmente)). Cada serviço tem
seu próprio role Postgres, dono só do seu schema, sem `CREATE` no banco e sem acesso ao
schema de outro serviço. Um microserviço relacional novo precisa: role + schema em
`initdb/` na raiz, `DATABASE_URL` apontando pro mesmo banco `workbox`, credenciais do
role próprio — nunca reusar role de outro serviço nem o superusuário `postgres`. Serviço
com dado genuinamente document-shaped (sem join, schema variável) usa MongoDB em vez de
forçar relacional — ver `notes-service/`.

## Frontend — `workbox-app/`
- Agente: **Claude Code** (full-stack). Antes era do Antigravity; o
  [`workbox-app/GEMINI.md`](workbox-app/GEMINI.md) ficou obsoleto e é mantido só como
  histórico até o desenvolvedor decidir removê-lo — as regras vivas dele (build antes de
  commit, `getErrorMessage`, sem scripts de scratch, manutenção do README) foram migradas
  pro [`workbox-app/CLAUDE.md`](workbox-app/CLAUDE.md).
- Escopo: componentes, styling, state management de tela, testes visuais e a integração
  com as APIs dos serviços. Regras de frontend e segurança de client nas seções 8 e 12 do
  `~/.claude/CLAUDE.md`; especificidades do app em [`workbox-app/CLAUDE.md`](workbox-app/CLAUDE.md).
- Consome as APIs só a partir do `openapi/openapi.yaml` de cada serviço (seção abaixo).

## Contas de teste (QA)

Pra testar login/fluxos autenticados manualmente (Claude Code contra a API e contra o
front local) sem depender de conta real, existem duas contas fixas — credenciais
e como recriá-las em [`workbox-api/README.md`](workbox-api/README.md#contas-de-teste-qa).
Uso exclusivo do Claude Code durante teste, nunca em demo pro usuário final.

## Contrato de API entre serviços e front

Cada microserviço backend versiona seu próprio `<serviço>/openapi/openapi.yaml` — a
**fonte da verdade** do que aquela API expõe. Regras (valem pra todos os serviços):

- **Contrato obrigatório, antes do front** (decisão do desenvolvedor, 2026-10-07): todo serviço
  backend **sempre** tem o `openapi/openapi.yaml` gerado e commitado, e ele tem que existir
  **antes** de qualquer tela ser construída sobre a API. Não se espera pedido (`@openapi`): criar
  e manter o contrato faz parte da tarefa de qualquer endpoint. Serviço novo nasce com o contrato
  no mesmo commit do primeiro endpoint, e o front só começa depois que ele está versionado.
  **Esta regra tem precedência neste monorepo** sobre o "somente sob demanda" do
  `~/.claude/CLAUDE.md` global (mesma lógica da convenção de commits).
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
  demais são *resource servers* — validam o token via introspecção remota
  (`POST /api/v1/auth/introspect`, client credentials cadastrados na tabela
  `workbox.api_clients`), sem decodificar o JWT localmente, sem conhecer `JWT_SECRET` e
  sem reimplementar login. Ver
  [`docs/budget-service-migracao-introspeccao.md`](docs/budget-service-migracao-introspeccao.md).
- **Acesso por módulo**: a introspecção devolve também `modules` (ADMIN: todos; demais: só os
  módulos das roles que têm — `USER` sozinho não libera nenhum). Cada resource server exige o
  módulo dele (`budget-service` → `FINANCAS`, `forza-telemetry-service` → `FORZA`,
  `moto-service` → `MOTO`; 403 sem ele).
  `notes-service` ainda não é módulo liberado, então segue sem essa trava. O `backup-service` não usa
  módulo: exige o papel `ADMIN` (um backup contém hashes de senha e segredos de MFA). Módulo novo =
  migration no `workbox-api` (módulo + role vinculada) + trava no serviço + card no Dashboard.
- Como o mesmo agente cuida dos dois lados, não há mais handoff manual entre agentes: o
  ajuste correspondente no `workbox-app` entra na mesma tarefa que muda o contrato do
  backend (só o contrato observável por client — rota, payload, status code, auth —
  exige ajuste no front; refactor interno ou schema de banco sem reflexo na API, não).
- Estado atual dos contratos: **todos** os serviços têm `openapi/openapi.yaml` versionado
  (`workbox-api`, `budget-service`, `notes-service`, `forza-telemetry-service`,
  `backup-service` e `moto-service`). Serviço sem contrato é pendência a corrigir antes de
  qualquer trabalho de front, não uma situação aceitável.
- Erros de API em RFC 9457/7807 (`application/problem+json`, `ProblemDetail`), sem stack
  trace — padrão de todos os serviços (`RestExceptionHandler`).

## Convenção de mensagens de commit

Vale pro Claude Code e pro desenvolvedor, em todos os repositórios do monorepo (raiz
`workbox`, `workbox-api`, `budget-service`, `notes-service`, `moto-service`, `workbox-app`):

- **Idioma**: sempre em português (pt-BR) — assunto e corpo. Só o prefixo de tipo
  (Conventional Commits) e nomes técnicos/símbolos ficam em inglês. Diverge de propósito
  do formato de commit do `~/.claude/CLAUDE.md` global — esta convenção tem precedência
  neste monorepo, resumida na seção "Commits" do `CLAUDE.md` de cada repositório
  (serviços e `workbox-app`).
- **Padrão** (Conventional Commits, tipo em inglês + descrição em português):

  ```
  <tipo>(<escopo opcional>): <descrição curta e objetiva em português>

  <corpo opcional — o "porquê" da mudança, em português, quando não for óbvio>
  ```

  Tipos aceitos: `feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `style`, `perf`,
  `ci`, `revert`. Exemplo:

  ```
  feat(auth): adiciona endpoint público de auto-cadastro

  Permite que o usuário crie a própria conta pela tela de login, sempre
  atribuindo a role USER no servidor (nunca confia em role vinda do payload).
  ```

## Infra, portas e operação do stack

Tudo sobe pelo `docker-compose.yml` da raiz (`docker compose up --build -d`) ou pelos
scripts `scripts/up-all.sh [--build]` / `scripts/down-all.sh` (este **para** os
containers, sem remover, incluindo o Postgres — uso pontual, nunca automático).

| Componente | Host | Interno (container) | Observação |
|---|---|---|---|
| Postgres 18 (`workbox-postgres`) | 7050 | 5432 | banco `workbox`, um schema/role por serviço (`initdb/` — só roda em volume vazio) |
| `workbox-api` | 7051 | 8080 | |
| `budget-service` | 7052 | 8081 | |
| `workbox-app` (nginx) | 7053 | 8080 | proxy de `/api/*` evita CORS |
| MongoDB (`workbox-mongo`) | 7054 | 27017 | só `notes-service`; auth obrigatória (`authSource=admin`) |
| `notes-service` | 7055 | 8082 | |
| Redis (`workbox-redis`) | 7056 | 6379 | só `workbox-api` (refresh tokens); sem volume |
| `forza-telemetry-service` | 7057 + UDP 5310 | 8083 + 5310/udp | |
| `moto-service` | 7059 | 8085 | schema `moto`, role `moto_service` (`initdb/01`, `02`; num banco existente, `initdb/04-create-moto-role.sql`); fuso de "hoje" `APP_TIMEZONE` (default `America/Fortaleza`) |
| `backup-service` | 7058 | 8084 | liga `./backups` do host em `/backups`; `BACKUP_HOST_DIR` (preenchido pelo `up-all.sh`) é só o caminho exibido na tela; role `backup_service` vem de `initdb/03-create-backup-role.sql` (num banco existente, rodar à mão) |

- **Ciclo de vida dos containers**: parar/remover containers de app e front nunca deve
  tocar no Postgres — só o `scripts/down-all.sh` derruba tudo, e só por pedido explícito.
- `.env` (gitignored) sobrescreve os defaults; `.env.example` lista todas as variáveis.
  Credenciais de dev nos defaults são só de estudo local — nunca replicar pra `prod`
  (`docker-compose.prod.yml` + `.env.prod.example` — mantenha os dois em dia ao adicionar
  serviço/variável: cobre todos os serviços, sem defaults de segredo; validar com
  `docker compose --env-file <env> -f docker-compose.prod.yml config -q`).
- Backup/restore: `scripts/backup-db.sh` / `scripts/restore-db.sh` via
  `docker compose --profile backup run --rm backup|restore` (restore usa `--clean
  --if-exists` — confirme o alvo antes).
- **Java 25 LTS** em todos os backends, `moto-service` incluído (`ARG JAVA_VERSION` no `Dockerfile` + `java.toolchain`
  no `build.gradle`) e Node 22 no front: ao atualizar, mude todos os lugares juntos.
- Dockerfiles: multi-stage, usuário non-root. Os `docs/` da raiz documentam a migração
  do `budget-service` pra introspecção remota (vale como referência pros demais).

## Git, branches, CI e Sonar

- Branch única de desenvolvimento: **`develop`** em todos os repositórios (sem branch por
  versão — versão = tag Git anotada). `main` é a branch protegida. O hook
  `.githooks/commit-msg` é no-op (não prefixa mensagem); `.githooks/pre-push` espelha
  todo push do `origin` (GitLab) pro remote `github` — o `git push` em si continua
  exigindo confirmação.
- Ao mudar o conteúdo de um submódulo, o commit no submódulo vem primeiro; a atualização
  do ponteiro no repositório raiz é um commit separado (`chore: atualiza ponteiro do
  submódulo <nome>`). Nunca varrer alterações alheias do working tree (há edições em
  andamento no raiz e nos submódulos): `git add` só dos arquivos da mudança.
- CI: `workbox-api`/`budget-service` têm `test` → `contract-drift-check` → `build` e
  `sonarcloud-check` (com `docker:dind` pros ITs com Testcontainers); `notes-service` tem
  `test` → `contract-drift-check` → `build`; `forza-telemetry-service` tem `test` (dind) →
  `contract-drift-check` → `build`;
  `moto-service` tem `test` (dind) → `contract-drift-check` → `build`;
  `workbox-app` tem `lint-test-build` em toda branch e `sonarcloud-check`. O Sonar dispara só
  em MR e em `main` (**não** `develop` — limitação do plano Free, não re-adicionar sem
  conferir). Sonar enrolado: `workbox-api`, `budget-service`, `workbox-app` (a raiz foi
  removida de propósito); `notes-service`, `forza-telemetry-service` e `moto-service` ainda sem Sonar.
- O grupo GitLab (`sonar-group-oojuniiin`) já foi renomeado várias vezes — confirme a URL
  do remote em vez de assumir.

## Bugs fora do escopo

Bug encontrado no meio de outra tarefa **não relacionado** ao que foi pedido: sinalize em
1–2 linhas e siga — não corrija sem pedido do desenvolvedor.
