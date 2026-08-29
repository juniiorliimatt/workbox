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

```bash
# workbox-api (8080) — identidade
cd workbox-api
./gradlew bootRun

# budget-service (8081) — resource server, precisa de um JWT do workbox-api
cd budget-service
./gradlew bootRun

# frontend
cd workbox-app
npm install
npm run dev
```
