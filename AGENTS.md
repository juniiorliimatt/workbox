# Divisão de responsabilidade entre agentes de IA

Este monorepo é desenvolvido com dois agentes de IA em paralelo, cada um responsável
por um submódulo. Esta divisão é uma decisão de projeto — respeite os limites abaixo
independentemente de qual agente estiver lendo este arquivo.

## Backend — `workbox-api/`
- Agente: **Claude Code** (regras globais em `~/.claude/CLAUDE.md` do desenvolvedor,
  copiadas em [`workbox-api/CLAUDE.md`](workbox-api/CLAUDE.md) para o projeto carregar
  as mesmas instruções em qualquer máquina).
- Escopo: API REST, domínio, persistência (JPA/Liquibase), segurança (Spring Security/JWT),
  infra (Gradle, CI, Docker/deploy).
- Não desenvolve UI/frontend.

## Frontend — `workbox-app/`
- Agente: **Antigravity** (regras globais em `~/GEMINI.md` do desenvolvedor, copiadas em
  [`workbox-app/GEMINI.md`](workbox-app/GEMINI.md) pelo mesmo motivo).
- Escopo: componentes, styling, state management de tela, testes visuais.
- Não desenvolve API/domínio/persistência.

## Contrato entre os dois lados

`workbox-api/openapi/openapi.yaml` é o contrato REST versionado — **fonte da verdade**
para o que a API expõe. Regras:

- O frontend não deve assumir comportamento de endpoint que não esteja descrito nesse
  arquivo.
- Qualquer mudança de contrato no backend (novo endpoint, novo campo, mudança de schema)
  exige regenerar o arquivo (`cd workbox-api && ./gradlew generateOpenApiDocs`) e
  commitar junto com a mudança de código. O CI (`contract-drift-check` em
  `workbox-api/.gitlab-ci.yml`) falha o pipeline se o arquivo commitado divergir do
  gerado a partir do código — ou seja, o contrato nunca fica desatualizado sem que o
  pipeline acuse.
- Mudanças no frontend que exigem um endpoint novo ou diferente do que já está no
  contrato devem ser solicitadas ao lado backend, não assumidas/mockadas
  silenciosamente.
