# moto-service — desenho

Data: 2026-10-06 · Status: aprovado pelo desenvolvedor (seções 1–3); seções 4–5 abaixo seguem o
padrão do monorepo e entram em revisão junto com este arquivo.

## Objetivo

Controlar e acompanhar a(s) moto(s) do usuário: abastecimentos e consumo (km/l), km rodados,
trocas de óleo com previsão da próxima, gasto mensal/anual e métricas de rodagem/consumo.

## Decisões

| Tema | Decisão |
|---|---|
| Autoria | Claude Code implementa tudo (backend, front, migration no `workbox-api`). Exceção **por serviço**, a registrar no `CLAUDE.md` da raiz. |
| Serviço | `moto-service` · pacote `br.com.moto` · porta host **7059** (container 8085) · resource server com introspecção (igual `budget-service`). |
| Banco | **PostgreSQL**, schema `moto`, role `moto_service` (dados tabulares/agregáveis; `GROUP BY` + window functions; reaproveita o padrão de role/schema/Liquibase). MongoDB descartado: nada document-shaped. |
| Acesso | Módulo **`MOTO`** (migration no `workbox-api`: módulo + role vinculada; trava `MODULE_MOTO` no serviço; card no Dashboard). |
| Fora do escopo (v1) | Importar Timeline/Google Maps (API inexistente; dado só no aparelho e impreciso como km). Eventual import de JSON fica como feature futura, só estimativa de km/dia. |

## Modelo de dados

Todas as entidades: `owner_username` vindo do token (nunca do payload), auditoria
`@CreatedBy/...` + Envers (`*_aud`), valores monetários em `BigDecimal`.

- `Motorcycle`: apelido, marca/modelo, ano, placa (opcional), `initialOdometerKm`, capacidade do
  tanque (opcional), ativa.
- `Refueling`: moto, data, **hodômetro total (km)**, litros, valor total, posto (opcional),
  combustível (gasolina comum/aditivada/etanol), `fullTank` (opcional, default `false`).
- `OilChange`: moto, data, hodômetro, tipo (mineral/semi/sintético), marca/viscosidade
  (opcional), custo (opcional), `intervalKm`, `intervalMonths` (pré-preenchidos por tipo,
  editáveis).
- `OdometerReading`: moto, data, hodômetro (km avulso, sem abastecer).

Invariantes: hodômetro **monotônico por moto** (entre abastecimentos, trocas e leituras);
litros e valor > 0; moto sempre conferida contra o dono (IDOR, OWASP API1).

## Cálculo de consumo (abastecimento parcial é o caso comum)

- **Por trecho** (abastecimento N-1 → N): `km/l = (odo[N] − odo[N-1]) / litros[N]`. Selo
  **exato** se N e N-1 têm `fullTank=true`; senão **estimado**.
- **Média de janela** (mês, ano, vida): `Σ km / Σ litros`, ponderada — nunca média de médias.
  Janela com poucos abastecimentos recebe flag `lowConfidence`.
- Trecho que cruza a virada do mês pertence ao mês do abastecimento N (data de fim).
- `fullTank` só refina precisão; nada é bloqueado sem ele.
- Hodômetro atual = maior valor entre abastecimentos, trocas e leituras da moto.

### Próxima troca de óleo

`próxima = min(odo_troca + intervalKm, data_troca + intervalMonths)`. Saída: km restantes, dias
restantes e status `OK | PERTO | VENCIDA` (limiar de "perto" configurável no serviço, default
10% do intervalo ou 500 km / 30 dias — o que for maior). Padrões por tipo (editáveis): mineral
~1.000–1.500 km, semi ~3.000–4.000 km, sintético ~5.000–6.000 km; 6–12 meses.

## API (`/api/v1`, módulo `MOTO`, tudo filtrado por dono)

| Recurso | Rotas |
|---|---|
| Motos | CRUD `/motorcycles`, `/{id}/history` (Envers) |
| Abastecimentos | CRUD `/motorcycles/{id}/refuelings` (paginado; `from`/`to`) |
| Trocas de óleo | CRUD `/motorcycles/{id}/oil-changes`; `GET /oil-intervals` |
| Km avulso | `POST /motorcycles/{id}/odometer-readings` |
| Métricas | `GET /motorcycles/{id}/stats?from&to`, `/stats/monthly?year`, `/stats/yearly`, `/oil-status` |

Métricas: rodagem (km totais, km/mês, km/dia, maior trecho); consumo (litros, gasto, km/l
ponderado, melhor/pior trecho, preço médio/L); custo (R$/km, mensal, anual, variação vs. mês
anterior); óleo (última, próxima, restantes, status). Erros em RFC 9457. Paginação explícita.
`openapi/openapi.yaml` versionado e commitado junto (contrato é consumido pelo front na mesma
tarefa; CI `contract-drift-check`).

## Front (`workbox-app`, padrão de Finanças/Forza)

- Rota `/moto` (hub, `MotoPage`) com abas: **Resumo** (cards de km/l médio, km do mês, gasto do
  mês/ano, status do óleo + gráficos `recharts`: km/l por mês, gasto mensal, km por mês),
  **Abastecimentos** (tabela paginada, filtro mensal/anual, form `react-hook-form`+`yup`),
  **Óleo** (histórico + card da próxima troca com barra de progresso), **Motos** (cadastro,
  seletor de moto ativa persistido). Selos "estimado"/"baixa confiança" com tooltip.
- `services/motoApi.ts` (padrão de `budgetApi.ts`/`forzaApi.ts`), tipos `I*` em
  `interfaces/moto/`, hook de carga por aba (`useLazyTabData`).
- Roteamento nos dois lugares: `vite.config.ts` (`motorcycles|oil-intervals` →
  `VITE_MOTO_API_URL` ou `:7059`) e `nginx.conf.template` (`MOTO_SERVICE_UPSTREAM`);
  upstream/`depends_on` no `docker-compose.yml`. Card "Moto" no Dashboard ligado ao módulo.
- Tokens do tema existentes, mobile-first (uso principal no celular, na LAN), HTML semântico,
  foco visível, contraste AA; listas paginadas (sem virtualização necessária).

## Testes (test-first)

- Backend: JUnit 5 + AssertJ; `@WebMvcTest` (serviços via `@MockitoBean`); Testcontainers
  Postgres para repositórios e agregações; `ModuleAccessSecurityTest` (403 sem `MOTO`); testes
  de unidade do cálculo (trecho exato/estimado, janela ponderada, virada de mês, parcial sem
  cheio, hodômetro regressivo, próxima troca por km vs. por tempo, IDOR entre donos).
- Front: Vitest + Testing Library (forms, cálculo exibido, estados de erro/loading), axe onde
  viável; E2E existente (`run-e2e.sh`) ganha o fluxo cadastrar moto → abastecer → ver métricas.

## Infra e entrega

- Repo GitLab próprio + submódulo em `.gitmodules` (**main primeiro, depois develop**; push
  só com confirmação). `Dockerfile` multi-stage non-root, Java 25, `.gitlab-ci.yml`
  (`test` dind → `contract-drift-check` → `build`), README e `CLAUDE.md` do serviço.
- `initdb/` (role + schema; em volume existente, rodar à mão), `docker-compose.yml`,
  `docker-compose.prod.yml`, `.env.example`, `.env.prod.example`, `scripts/up-all.sh`;
  seed de `api_clients` no `workbox-api` (client credentials do serviço).
- CORS com allowlist (`localhost:7053`), sem `*`; logs sem PII.

### Ordem de entrega

1. `workbox-api`: módulo `MOTO` + role + seed `api_clients` (+ testes).
2. `moto-service`: esqueleto, segurança, `Motorcycle`; depois `Refueling` + cálculo de consumo;
   `OilChange` + próxima troca; endpoints de métricas; `openapi.yaml`.
3. Infra (initdb, compose, scripts, `.env*`).
4. `workbox-app`: proxy/rota, serviço de API e tipos, abas (Motos → Abastecimentos → Óleo →
   Resumo/gráficos), card no Dashboard.
5. Docs: `CLAUDE.md` raiz (exceção de autoria, mapa, portas, módulo) + README do serviço.
