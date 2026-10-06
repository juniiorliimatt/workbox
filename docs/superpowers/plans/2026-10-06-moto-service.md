# moto-service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Novo microserviço `moto-service` (+ módulo `MOTO` no `workbox-api` e telas no `workbox-app`) para controlar abastecimentos, consumo (km/l), km rodados, trocas de óleo (próxima troca por km e tempo) e métricas mensais/anuais de uma ou mais motos.

**Architecture:** Resource server Spring Boot (opaque token/introspecção, igual `budget-service`), Postgres schema `moto`. Toda a regra de cálculo (consumo por trecho, janelas ponderadas, próxima troca, monotonicidade do hodômetro) vive em classes **puras** em `br.com.moto.domain` — testadas sem Spring. Services carregam os dados do dono (volume pequeno: centenas de linhas/ano), chamam o domínio e devolvem DTOs `record`. Front: página `/moto` com abas, no padrão de Finanças/Forza.

**Tech Stack:** Java 25, Spring Boot 3.5.16, Gradle 9.7.1, JPA + Liquibase + Envers, springdoc, Testcontainers (Postgres 18) · React 18/TS/Vite/MUI v5/recharts/react-hook-form+yup, Vitest.

**Spec:** `docs/superpowers/specs/2026-10-06-moto-service-design.md`

## Global Constraints

- Pacote raiz `br.com.moto`; repo/submódulo `moto-service`; schema `moto`; role Postgres `moto_service` (senha de dev `moto_service`); porta host **7059**, container **8085**; módulo `MOTO` (authority `MODULE_MOTO`).
- **`final` obrigatório** em todo parâmetro e variável local (`src/main` e `src/test`), exceto reatribuição real. Lombok permitido; Javadoc e nomes de métodos de negócio em **português**; sem `SELECT *`.
- `owner_username` vem **sempre** do token (`Authentication.getName()`), nunca do payload; toda query filtra por ele; recurso de outro dono responde **404** (nunca 403).
- Valores monetários e litros em `BigDecimal`; datas `LocalDate`; hodômetro `int` (km).
- Erros em RFC 9457 (`ProblemDetail`), sem stack trace; mensagens em `messages.properties` (pt-BR).
- Liquibase: arquivos `yymmdd_nnnn_<acao>_<alvo>.sql` em `db/changelog/v0.0.1/create`; nunca editar changeset aplicado; schema escrito no SQL (`moto.`).
- Commits em **pt-BR**, Conventional Commits (`tipo(escopo): descrição`), um por tarefa, **sem `git push`**. Cada commit termina com a linha `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. `git add` só dos arquivos da tarefa (há edições alheias no working tree da raiz).
- Test-first: teste → ver falhar pelo motivo certo → implementar → verde. Alterar arquivos só com `Edit`/`Write` (diff visível).
- Contrato OpenAPI do `moto-service` é gerado **nesta entrega** (pedido explícito do desenvolvedor, é serviço novo): `./gradlew generateOpenApiDocs`.
- Java 25 / Node 22 já fixados no monorepo — não mudar versões.
- Front: tokens do tema MUI, mobile-first, HTML semântico, foco visível, contraste AA; mensagens de erro via `getErrorMessage` (`@/utils/errors`); sem scripts de scratch.

## Mapa de arquivos

**`workbox-api/`** (submódulo existente)
- Create `src/main/resources/db/changelog/v0.0.2/create/261006_0000_seed_module_moto.sql` — módulo + role `MOTO`.
- Create `src/main/resources/db/changelog/v0.0.2/create/261006_0001_seed_api_clients_moto_service.sql` — client de introspecção.

**Raiz**
- Modify `initdb/01-create-app-roles.sql`, `initdb/02-create-schemas.sql`; Create `initdb/04-create-moto-role.sql` (para volume já existente).
- Modify `docker-compose.yml`, `docker-compose.prod.yml`, `.env.example`, `.env.prod.example`, `.gitmodules`, `CLAUDE.md`, `README.md`.

**`moto-service/`** (repo novo; árvore `br/com/moto`)
```
build.gradle  settings.gradle  Dockerfile  .gitignore  .dockerignore  .gitlab-ci.yml  README.md  CLAUDE.md
src/main/java/br/com/moto/
  MotoServiceApplication.java
  config/        SecurityConfig  WorkboxTokenIntrospector  AuditorAwareImpl  OpenApiConfig  MessageConfig  audit/{CustomRevisionEntity,RevisionListenerImpl}
  exceptions/    ResourceNotFoundException  InvalidOdometerException  handler/RestExceptionHandler
  domain/        OdometerPoint  OdometerRules  FuelEntry  Segment  ConsumptionWindow  ConsumptionCalculator  OdometerTimeline  OilStatus  OilStatusCalculator  OilLimit  OilStatusLevel
  models/enums/  FuelType  OilType
  models/entities/ Motorcycle  Refueling  OilChange  OdometerReading
  models/dto/    (records — ver tarefas)
  repositories/  MotorcycleRepository  RefuelingRepository  OilChangeRepository  OdometerReadingRepository
  services/      MotorcycleService  OdometerService  RefuelingService  OilChangeService  StatsService  AuditService
  controllers/   MotorcycleController  RefuelingController  OilChangeController  OdometerReadingController  StatsController
src/main/resources/ application*.properties  messages.properties  db/changelog/changelog.yaml  db/changelog/v0.0.1/create/*.sql
src/test/java/br/com/moto/ ... (espelha main)  src/test/resources/testcontainers-init.sql
```

**`workbox-app/`**
- Create `src/interfaces/moto/index.ts`, `src/services/motoApi.ts`, `src/pages/Moto.tsx`, `src/pages/moto/{useMotos.ts,format.ts,MotosTab.tsx,AbastecimentosTab.tsx,OleoTab.tsx,ResumoTab.tsx}`, `src/test/moto/*.test.tsx`.
- Modify `vite.config.ts`, `nginx.conf.template`, `src/routes/routes.tsx`, `src/pages/Dashboard.tsx`, `CLAUDE.md`, `README.md`.

---

### Task 1: `workbox-api` — módulo `MOTO`, role e client de introspecção

**Files:**
- Create: `workbox-api/src/main/resources/db/changelog/v0.0.2/create/261006_0000_seed_module_moto.sql`
- Create: `workbox-api/src/main/resources/db/changelog/v0.0.2/create/261006_0001_seed_api_clients_moto_service.sql`
- Test: `workbox-api/src/test/java/br/com/workbox/MotoModuleSeedIT.java` (confirmar o pacote real lendo o `RealPostgresSchemaIT` do `workbox-api` e copiando o setup de container dele)

**Interfaces:**
- Produces: módulo `MOTO` em `workbox.modules`; role `MOTO` (`roles.module_id` → módulo); client `moto-service` em `workbox.api_clients` (secret de dev `MyS3cur3Cli3ntS3cr3t!M0t0!`).

- [ ] **Step 1: Gerar o hash bcrypt do secret** (cost 12, prefixo `$2b$` como o do seed do forza)

```bash
cd /home/jr/work/projetos/workbox && python3 -c "import bcrypt;print(bcrypt.hashpw(b'MyS3cur3Cli3ntS3cr3t!M0t0!',bcrypt.gensalt(12)).decode())" 2>/dev/null \
  || htpasswd -bnBC 12 "" 'MyS3cur3Cli3ntS3cr3t!M0t0!' | tr -d ':\n' | sed 's/^\$2y/$2b/'
```
Guarde a saída (`$2b$12$...`) — é o `<HASH>` do Step 4. (Gerar hash é saída de comando, não edição de arquivo; o arquivo SQL é escrito com `Write`.)

- [ ] **Step 2: Escrever o teste que falha** — `MotoModuleSeedIT` sobe o Postgres descartável (mesmo setup do `RealPostgresSchemaIT` do `workbox-api`) e assevera:

```java
@Test
void seedCriaModuloMotoRoleEClient() {
    final var modulos = jdbc.queryForList("SELECT code FROM workbox.modules WHERE code = 'MOTO'", String.class);
    assertThat(modulos).containsExactly("MOTO");

    final var roleModulo = jdbc.queryForObject(
        "SELECT m.code FROM workbox.roles r JOIN workbox.modules m ON m.id = r.module_id "
            + "WHERE r.authority = 'MOTO' AND r.deleted_at IS NULL", String.class);
    assertThat(roleModulo).isEqualTo("MOTO");

    final var ativo = jdbc.queryForObject(
        "SELECT active FROM workbox.api_clients WHERE client_id = 'moto-service'", Boolean.class);
    assertThat(ativo).isTrue();
}
```
(`jdbc` = `JdbcTemplate` autowired; conferir se o IT existente já expõe um.)

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd workbox-api && ./gradlew test --tests '*MotoModuleSeedIT'`
Expected: FAIL (`modulos` vazio — o módulo ainda não existe).

- [ ] **Step 4: Implementar os dois changesets**

`261006_0000_seed_module_moto.sql`:
```sql
-- liquibase formatted sql

-- changeset oojuniin:modules-v1-seed-moto context:data labels:api,modules
-- comment: Módulo Moto (moto-service). Catálogo fechado: módulo novo entra por changeset junto com a role que libera o acesso.
-- preconditions onFail:MARK_RAN onError:HALT
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM workbox.modules WHERE code = 'MOTO'
INSERT INTO workbox.modules (code, name)
VALUES ('MOTO', 'Moto');
-- rollback DELETE FROM workbox.modules WHERE code = 'MOTO';

-- changeset oojuniin:roles-v3-seed-moto context:data labels:api,roles,modules
-- comment: Role que libera o módulo Moto. Não é atribuída a ninguém aqui: só um ADMIN concede (ADMIN já recebe todos os módulos).
-- preconditions onFail:MARK_RAN onError:HALT
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM workbox.roles WHERE authority = 'MOTO' AND deleted_at IS NULL
INSERT INTO workbox.roles (authority, module_id, created_at, created_by, updated_at, updated_by)
SELECT m.code, m.id, current_timestamp, 'API', current_timestamp, 'API'
FROM workbox.modules m
WHERE m.code = 'MOTO';
-- rollback DELETE FROM workbox.roles WHERE authority = 'MOTO';
```

`261006_0001_seed_api_clients_moto_service.sql` (UUID novo: `uuidgen` e cole):
```sql
-- liquibase formatted sql

-- changeset oojuniin:api_clients-v5-seed-moto-service context:data labels:api,api_clients
-- comment: Cliente inicial do moto-service, secret de estudo local (ver .env.example na raiz). Em produção, gere um secret forte e insira o cliente real via changeset novo — nunca edite este arquivo já aplicado.
-- preconditions onFail:MARK_RAN onError:HALT
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM workbox.api_clients WHERE client_id = 'moto-service'
INSERT INTO workbox.api_clients (id, name, client_id, client_secret_hash, allowed_grant_types, active, created_at, created_by)
VALUES ('<UUID-GERADO>', 'moto-service', 'moto-service',
        '<HASH>', '["CLIENT_SECRET"]', true,
        current_timestamp, 'API');
-- rollback DELETE FROM workbox.api_clients WHERE client_id = 'moto-service';
```
(Substitua `<UUID-GERADO>` e `<HASH>` pelos valores reais **antes** de salvar — nada de placeholder no commit.)

- [ ] **Step 5: Rodar e ver passar** — `cd workbox-api && ./gradlew check` → PASS (inclui `contract-drift`? não: não mudou API).

- [ ] **Step 6: Commit (no submódulo `workbox-api`, branch `develop`)**

```bash
cd workbox-api && git add src/main/resources/db/changelog/v0.0.2/create/261006_0000_seed_module_moto.sql src/main/resources/db/changelog/v0.0.2/create/261006_0001_seed_api_clients_moto_service.sql src/test/java/br/com/workbox/MotoModuleSeedIT.java
git commit -m "feat(modulos): adiciona módulo MOTO, role e client de introspecção do moto-service

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
O ponteiro do submódulo na raiz é atualizado na Task 17.

---

### Task 2: initdb — role e schema do `moto-service`

**Files:**
- Modify: `initdb/01-create-app-roles.sql`, `initdb/02-create-schemas.sql`
- Create: `initdb/04-create-moto-role.sql` (para banco **já existente**; rodado à mão)

**Interfaces:** Produces role `moto_service` dono do schema `moto`.

(Config sem lógica — dispensa teste prévio; validação por execução.)

- [ ] **Step 1:** Em `01-create-app-roles.sql`, após a linha do `forza_service`, adicionar `CREATE ROLE moto_service WITH LOGIN PASSWORD 'moto_service';` e incluir `moto_service` na lista do `GRANT CONNECT ON DATABASE workbox TO ...`.
- [ ] **Step 2:** Em `02-create-schemas.sql`, adicionar `CREATE SCHEMA IF NOT EXISTS moto AUTHORIZATION moto_service;`.
- [ ] **Step 3:** Criar `initdb/04-create-moto-role.sql`:
```sql
-- Para um Postgres JÁ existente (initdb/ só roda em volume vazio). Rodar como superusuário:
--   docker exec -i workbox-postgres psql -U postgres -d workbox < initdb/04-create-moto-role.sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'moto_service') THEN
    CREATE ROLE moto_service WITH LOGIN PASSWORD 'moto_service';
  END IF;
END
$$;
GRANT CONNECT ON DATABASE workbox TO moto_service;
CREATE SCHEMA IF NOT EXISTS moto AUTHORIZATION moto_service;
```
- [ ] **Step 4: Aplicar no Postgres de dev (não derruba nada)** — `docker exec -i workbox-postgres psql -U postgres -d workbox < initdb/04-create-moto-role.sql` → `CREATE ROLE`/`CREATE SCHEMA`. Verificar: `docker exec workbox-postgres psql -U postgres -d workbox -c "\dn moto"`.
- [ ] **Step 5: Commit (raiz)** — `git add initdb/01-create-app-roles.sql initdb/02-create-schemas.sql initdb/04-create-moto-role.sql` · `chore(infra): adiciona role e schema do moto-service`.

---

### Task 3: `moto-service` — esqueleto, segurança por módulo e tratamento de erros

**Files:**
- Create (repo novo em `/home/jr/work/projetos/workbox/moto-service`): `settings.gradle`, `build.gradle`, `gradlew*` + `gradle/wrapper/*` (copiados do `budget-service`), `.gitignore`, `.dockerignore`, `Dockerfile`
- Create: `config/*`, `exceptions/*`, `MotoServiceApplication.java`, `application*.properties`, `messages.properties`, `db/changelog/changelog.yaml`, `db/changelog/v0.0.1/create/261006_0000_create_envers_rev_info.sql`
- Test: `src/test/java/br/com/moto/config/ModuleAccessSecurityTest.java` (escrito na Task 4, junto do primeiro controller — nesta tarefa o teste é o boot do contexto)
- Test: `src/test/java/br/com/moto/PostgresIT.java` (base), `RealPostgresSchemaIT.java`; `src/test/resources/testcontainers-init.sql`

**Interfaces:**
- Produces: `SecurityConfig.MODULE_AUTHORITY == "MODULE_MOTO"`; `ResourceNotFoundException(String)`; `InvalidOdometerException(String)` (→ 400); `abstract class PostgresIT` (container + `@DynamicPropertySource`) estendida pelos ITs seguintes; bean `MessageSourceAccessor`.

- [ ] **Step 1: Criar o repo e copiar a base**

```bash
cd /home/jr/work/projetos/workbox && mkdir moto-service && cd moto-service && git init -q -b main
cp -r ../budget-service/gradle ../budget-service/gradlew ../budget-service/gradlew.bat ../budget-service/.dockerignore ../budget-service/.gitignore .
```
(Cópia de binários/wrapper — não há diff de texto a esconder; os arquivos de texto abaixo são escritos com `Write`.)

- [ ] **Step 2: `settings.gradle` e `build.gradle`** — `settings.gradle`: `rootProject.name = 'moto-service'` (com o `pluginManagement` do budget). `build.gradle` = o do `budget-service` com: `group = 'br.com.moto'`; **sem** o plugin `org.sonarqube`, bloco `sonar {}`, `tasks.named('sonar')`, `spring-boot-starter-cache`, `caffeine`, `cucumber-*`, `junit-platform-suite` e o `mavenBom cucumber`; manter `mavenBom "org.junit:junit-bom:5.14.2"`; `apiDocsUrl.set("http://localhost:7059/v3/api-docs.yaml")`.

- [ ] **Step 3: Escrever o teste que falha** — `RealPostgresSchemaIT` (mesma estrutura do budget, `br.com.moto`, role `moto_service`) estendendo a base:

```java
package br.com.moto;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("dev")
abstract class PostgresIT {
    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(DockerImageName.parse("postgres:18"))
            .withDatabaseName("workbox").withUsername("postgres").withPassword("postgres")
            .withInitScript("testcontainers-init.sql");

    @DynamicPropertySource
    static void datasourceProperties(final DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> "jdbc:postgresql://%s:%d/workbox"
                .formatted(POSTGRES.getHost(), POSTGRES.getMappedPort(5432)));
        registry.add("spring.datasource.username", () -> "moto_service");
        registry.add("spring.datasource.password", () -> "moto_service");
    }
}
```
```java
class RealPostgresSchemaIT extends PostgresIT {
    @Test
    void contextoSobeContraPostgresReal() { /* o boot (Liquibase + ddl-auto=validate) é o teste */ }
}
```
`testcontainers-init.sql`: extensões `pgcrypto`/`uuid-ossp`; `CREATE ROLE moto_service WITH LOGIN PASSWORD 'moto_service'; GRANT CONNECT ON DATABASE workbox TO moto_service; CREATE SCHEMA IF NOT EXISTS moto AUTHORIZATION moto_service;`.

- [ ] **Step 4: Rodar e ver falhar** — `./gradlew test --tests '*RealPostgresSchemaIT'` → FAIL (classe `MotoServiceApplication` inexistente / contexto não sobe).

- [ ] **Step 5: Implementar a base**
  - `MotoServiceApplication` (`@SpringBootApplication @EnableJpaAuditing`).
  - `application.properties`: igual ao do budget com `spring.application.name=moto-service`, `server.port=${PORT:7059}`, **sem** as linhas de cache, `introspection.client-id=${INTROSPECTION_CLIENT_ID:moto-service}`, `introspection.client-secret=${INTROSPECTION_CLIENT_SECRET:MyS3cur3Cli3ntS3cr3t!M0t0!}`. `application-dev.properties`: igual ao do budget com `POSTGRES_USER:moto_service`, `POSTGRES_PASSWORD:moto_service`, `SCHEMA:moto`. `application-prod.properties`: copiar o do budget (sem defaults de segredo; conferir o conteúdo ao copiar). `application-test.properties`: igual ao do budget.
  - `config/WorkboxTokenIntrospector`, `AuditorAwareImpl`, `MessageConfig`: cópia literal do budget com `package br.com.moto.config`.
  - `config/audit/CustomRevisionEntity` e `RevisionListenerImpl`: cópia com `package br.com.moto.config.audit` e `@Table(name = "rev_info", schema = "moto")`.
  - `config/OpenApiConfig`: cópia com título `"Moto Service API"` e descrição `"Contrato REST do moto-service ..."`.
  - `config/SecurityConfig`: cópia do budget com `MODULE_AUTHORITY = WorkboxTokenIntrospector.MODULE_AUTHORITY_PREFIX + "MOTO"` e `allowedMethods` `GET, POST, PUT, DELETE, OPTIONS`.
  - `exceptions/ResourceNotFoundException`, `exceptions/InvalidOdometerException` (ambas `RuntimeException(String)`).
  - `exceptions/handler/RestExceptionHandler`: cópia do budget, removendo os handlers de `DuplicateResourceException`/`ResourceInUseException` e **adicionando**:
```java
@ExceptionHandler(InvalidOdometerException.class)
public ProblemDetail handleInvalidOdometer(final InvalidOdometerException exception) {
    return problem(HttpStatus.BAD_REQUEST, exception.getMessage());
}
```
  - `messages.properties`: as chaves `erro.*` do budget (`erro.validacaoFalhou`, `erro.registroEmUso`, `erro.jsonMalFormado`, `erro.inesperado`, `erro.parametroObrigatorio`, `erro.parametroInvalido` — copiar os valores exatos do arquivo do budget).
  - `changelog.yaml`: `includeAll` de `db/changelog/v0.0.1/create` (`relativeToChangelogFile: false`).
  - `261006_0000_create_envers_rev_info.sql`: o trecho `rev_info` do `260913_0011` do budget com `moto.` no lugar de `budget.` (sequence `moto.rev_info_seq START 1 INCREMENT 50`; tabela `moto.rev_info(id, timestamp, username NOT NULL)`; changeset id `moto-service:envers-v1-rev-info`).
  - `Dockerfile`: o do budget com `EXPOSE 8085`.

- [ ] **Step 6: Rodar e ver passar** — `./gradlew test --tests '*RealPostgresSchemaIT'` → PASS. (`ddl-auto=validate` com `CustomRevisionEntity` mapeada exige `rev_info` — o changeset acima a cria.)

- [ ] **Step 7: Commit (repo `moto-service`, branch `main` — a `develop` é criada na Task 11)**

```bash
git add . && git commit -m "chore: esqueleto do moto-service com segurança por módulo e tratamento de erros

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
(Repo novo: primeiro commit na `main`; `git branch develop` e demais ficam para a Task 11. Sem remote ainda — nada de push.)

---

### Task 4: Motos — entidade, CRUD, histórico (Envers) e trava de módulo

**Files:**
- Create: `models/entities/Motorcycle.java`, `models/dto/{MotorcycleDTO,MotorcycleRequestDTO,MotorcycleRevisionDTO}.java`, `repositories/MotorcycleRepository.java`, `services/{MotorcycleService,AuditService}.java`, `controllers/MotorcycleController.java`
- Create: `db/changelog/v0.0.1/create/261006_0001_create_table_motorcycles.sql`
- Test: `controllers/MotorcycleControllerTest.java`, `config/ModuleAccessSecurityTest.java`, `services/MotorcycleServiceIT.java`

**Interfaces:**
- Produces:
  - `MotorcycleRequestDTO(String nickname, String brand, String model, Integer year, String plate, Integer initialOdometerKm, BigDecimal tankCapacityLiters, Boolean active)`
  - `MotorcycleDTO(UUID id, String nickname, String brand, String model, Integer year, String plate, int initialOdometerKm, BigDecimal tankCapacityLiters, boolean active)`
  - `MotorcycleService`: `List<MotorcycleDTO> listar(String owner)`, `MotorcycleDTO buscar(UUID id, String owner)`, `MotorcycleDTO criar(MotorcycleRequestDTO, String owner)`, `MotorcycleDTO atualizar(UUID, MotorcycleRequestDTO, String owner)`, `void excluir(UUID, String owner)`, **`Motorcycle exigirDoDono(UUID id, String owner)`** (entidade; 404 se não existir/for de outro dono)
  - `MotorcycleRepository.findByIdAndOwnerUsername(UUID, String): Optional<Motorcycle>`, `findByOwnerUsernameOrderByNicknameAsc(String)`
  - Rotas: `GET/POST /api/v1/motorcycles`, `GET/PUT/DELETE /api/v1/motorcycles/{id}`, `GET /api/v1/motorcycles/{id}/history`

- [ ] **Step 1: Escrever os testes que falham**

`ModuleAccessSecurityTest` — idêntico ao do budget, apontando `@WebMvcTest(MotorcycleController.class)`, `URL = "/api/v1/motorcycles"`, `@MockitoBean MotorcycleService` + `AuditService`, e authority `MODULE_MOTO` (casos: sem token 401; só `ROLE_USER` 403; `MODULE_FORZA` 403; `MODULE_MOTO` 200 — o `service.listar(any())` mockado devolve `List.of()`).

`MotorcycleControllerTest` (`@WebMvcTest(MotorcycleController.class)`, `@ActiveProfiles("test")`, `@MockitoBean(types = JpaMetamodelMappingContext.class)`, `@Import(MessageConfig.class)`, mocks de `MotorcycleService` e `AuditService`). Casos:
```java
@Test void criar_comPayloadValido_retorna201ComDono() throws Exception {
    when(service.criar(any(), eq("jr"))).thenReturn(DTO);
    mockMvc.perform(post(URL).with(csrf()).with(opaqueToken().attributes(a -> a.put("sub", "jr")))
            .contentType(APPLICATION_JSON)
            .content("""
                {"nickname":"Fazer","model":"Fazer 250","initialOdometerKm":1200}"""))
        .andExpect(status().isCreated()).andExpect(jsonPath("$.nickname").value("Fazer"));
}
@Test void criar_semApelido_retorna400ComErros() { ... jsonPath("$.errors[0].field").value("nickname") ... }
@Test void criar_hodometroNegativo_retorna400() { ... "initialOdometerKm": -1 ... }
@Test void buscar_deOutroDono_retorna404() { when(service.buscar(ID, "jr")).thenThrow(new ResourceNotFoundException("Moto não encontrada")); ... status().isNotFound() ... jsonPath("$.detail") }
@Test void excluir_retorna204() { ... }
```
(`DTO = new MotorcycleDTO(ID, "Fazer", null, "Fazer 250", null, null, 1200, null, true)`.)

`MotorcycleServiceIT extends PostgresIT`: (a) criar e listar só devolve as motos do dono (`"jr"` vs `"outro"`); (b) `buscar(id, "outro")` lança `ResourceNotFoundException`; (c) atualizar muda o apelido e `/history` via `AuditService.historicoMoto(id, "jr")` devolve 2 revisões (`ADD`, `MOD`); (d) excluir remove.

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*Motorcycle*' --tests '*ModuleAccess*'` → FAIL (classes inexistentes).

- [ ] **Step 3: Migration** `261006_0001_create_table_motorcycles.sql`:
```sql
-- liquibase formatted sql

-- changeset moto-service:motorcycles-v1-create context:structure labels:motorcycles
-- comment: Motos do usuário (owner_username vem do token). initial_odometer_km é o piso do hodômetro (nenhum registro pode ficar abaixo).
-- preconditions onFail:MARK_RAN onError:HALT
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'moto' AND table_name = 'motorcycles'
CREATE TABLE moto.motorcycles
(
    id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    nickname             VARCHAR(60)   NOT NULL,
    brand                VARCHAR(60),
    model                VARCHAR(60)   NOT NULL,
    year                 INTEGER,
    plate                VARCHAR(10),
    initial_odometer_km  INTEGER       NOT NULL CHECK (initial_odometer_km >= 0),
    tank_capacity_liters NUMERIC(5, 2),
    active               BOOLEAN       NOT NULL DEFAULT TRUE,
    owner_username       VARCHAR(255)  NOT NULL,
    created_at           TIMESTAMP(6),
    updated_at           TIMESTAMP(6),
    created_by           VARCHAR(50),
    updated_by           VARCHAR(50)
);
CREATE INDEX idx_motorcycles_owner ON moto.motorcycles (owner_username);

-- changeset moto-service:motorcycles-v1-aud context:structure labels:motorcycles,audit
-- comment: Histórico Envers de motorcycles — espelha as colunas da tabela principal.
-- preconditions onFail:MARK_RAN onError:HALT
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'moto' AND table_name = 'motorcycles_aud'
CREATE TABLE moto.motorcycles_aud
(
    id                   UUID    NOT NULL,
    rev                  INTEGER NOT NULL REFERENCES moto.rev_info (id),
    revtype              SMALLINT,
    nickname             VARCHAR(60),
    brand                VARCHAR(60),
    model                VARCHAR(60),
    year                 INTEGER,
    plate                VARCHAR(10),
    initial_odometer_km  INTEGER,
    tank_capacity_liters NUMERIC(5, 2),
    active               BOOLEAN,
    owner_username       VARCHAR(255),
    created_at           TIMESTAMP(6),
    updated_at           TIMESTAMP(6),
    created_by           VARCHAR(50),
    updated_by           VARCHAR(50),
    PRIMARY KEY (id, rev)
);
```

- [ ] **Step 4: Entidade** (padrão `Revenue` do budget — Lombok `@Getter @Setter @Builder @NoArgsConstructor @AllArgsConstructor`, `@Entity @Table(name = "motorcycles", schema = "moto") @EntityListeners(AuditingEntityListener.class) @Audited`):

```java
@Id @GeneratedValue(strategy = GenerationType.UUID) private UUID id;
@NotBlank(message = "{moto.apelidoObrigatorio}") @Size(max = 60) @Column(nullable = false, length = 60) private String nickname;
@Size(max = 60) @Column(length = 60) private String brand;
@NotBlank(message = "{moto.modeloObrigatorio}") @Size(max = 60) @Column(nullable = false, length = 60) private String model;
@Column(name = "year") private Integer year;
@Size(max = 10) @Column(length = 10) private String plate;
@Min(0) @Column(name = "initial_odometer_km", nullable = false) private int initialOdometerKm;
@Column(name = "tank_capacity_liters", precision = 5, scale = 2) private BigDecimal tankCapacityLiters;
@Column(nullable = false) private boolean active;
@Column(name = "owner_username", nullable = false, updatable = false, length = 255) private String ownerUsername;
// + @CreatedDate createdAt, @LastModifiedDate updatedAt, @CreatedBy createdBy, @LastModifiedBy updatedBy (idêntico ao Revenue)
```
`year` é palavra reservada em alguns dialetos — se o H2 do profile `test` reclamar, anotar `@Column(name = "\"year\"")` **só** não é necessário no Postgres; preferir renomear coluna e campo para `modelYear` / `model_year` (migration e `_aud` acompanham) — decidir no Step 2 se o teste de contexto falhar.

- [ ] **Step 5: DTOs** (records + Bean Validation; mensagens via chaves de `messages.properties`):
```java
public record MotorcycleRequestDTO(
    @NotBlank(message = "{moto.apelidoObrigatorio}") @Size(max = 60) String nickname,
    @Size(max = 60) String brand,
    @NotBlank(message = "{moto.modeloObrigatorio}") @Size(max = 60) String model,
    @Min(1900) @Max(2100) Integer year,
    @Size(max = 10) String plate,
    @NotNull(message = "{moto.hodometroObrigatorio}") @Min(value = 0, message = "{moto.hodometroNegativo}") Integer initialOdometerKm,
    @DecimalMin(value = "0.0", inclusive = false) @Digits(integer = 3, fraction = 2) BigDecimal tankCapacityLiters,
    Boolean active) {}
public record MotorcycleDTO(UUID id, String nickname, String brand, String model, Integer year, String plate,
    int initialOdometerKm, BigDecimal tankCapacityLiters, boolean active) {}
public record MotorcycleRevisionDTO(int revision, LocalDateTime changedAt, String changedBy, String revisionType,
    UUID id, String nickname, String model, int initialOdometerKm, boolean active) {}
```
`messages.properties` ganha: `moto.naoEncontrada=Moto não encontrada`, `moto.apelidoObrigatorio=Apelido é obrigatório`, `moto.modeloObrigatorio=Modelo é obrigatório`, `moto.hodometroObrigatorio=Hodômetro inicial é obrigatório`, `moto.hodometroNegativo=Hodômetro não pode ser negativo`.

- [ ] **Step 6: Repository / Service / AuditService / Controller**

```java
public interface MotorcycleRepository extends JpaRepository<Motorcycle, UUID> {
    Optional<Motorcycle> findByIdAndOwnerUsername(UUID id, String ownerUsername);
    List<Motorcycle> findByOwnerUsernameOrderByNicknameAsc(String ownerUsername);
}
```
```java
@Service
public class MotorcycleService {
    private final MotorcycleRepository repository;
    private final MessageSourceAccessor messages;
    // construtor com final params

    @Transactional(readOnly = true)
    public List<MotorcycleDTO> listar(final String owner) {
        return repository.findByOwnerUsernameOrderByNicknameAsc(owner).stream().map(MotorcycleService::paraDto).toList();
    }
    @Transactional(readOnly = true)
    public MotorcycleDTO buscar(final UUID id, final String owner) { return paraDto(exigirDoDono(id, owner)); }

    @Transactional
    public MotorcycleDTO criar(final MotorcycleRequestDTO req, final String owner) {
        final var moto = Motorcycle.builder().ownerUsername(owner).build();
        aplicar(moto, req);
        return paraDto(repository.save(moto));
    }
    @Transactional
    public MotorcycleDTO atualizar(final UUID id, final MotorcycleRequestDTO req, final String owner) {
        final var moto = exigirDoDono(id, owner);
        aplicar(moto, req);
        return paraDto(repository.save(moto));
    }
    @Transactional
    public void excluir(final UUID id, final String owner) { repository.delete(exigirDoDono(id, owner)); }

    /** Checagem de dono/existência (404, nunca 403) usada por todo recurso filho da moto. */
    @Transactional(readOnly = true)
    public Motorcycle exigirDoDono(final UUID id, final String owner) {
        return repository.findByIdAndOwnerUsername(id, owner)
            .orElseThrow(() -> new ResourceNotFoundException(messages.getMessage("moto.naoEncontrada")));
    }
    private static void aplicar(final Motorcycle moto, final MotorcycleRequestDTO req) { /* copia campos; active = req.active() == null || req.active() */ }
    static MotorcycleDTO paraDto(final Motorcycle m) { return new MotorcycleDTO(m.getId(), m.getNickname(), m.getBrand(), m.getModel(), m.getYear(), m.getPlate(), m.getInitialOdometerKm(), m.getTankCapacityLiters(), m.isActive()); }
}
```
`excluir` com filhos: as FKs das Tasks 5/7/8 usam `ON DELETE CASCADE`.

`AuditService.historicoMoto(UUID id, String owner)`: mesma lógica de `findRevenueHistory` do budget (`AuditReaderFactory`, `forRevisionsOfEntity(Motorcycle.class, false, true)`, ordem por `revisionNumber`), chamando antes `motorcycleService.exigirDoDono` e mapeando para `MotorcycleRevisionDTO` (helper `toLocalDateTime` copiado do budget).

```java
@RestController
@RequestMapping("/api/v1/motorcycles")
public class MotorcycleController {
    @GetMapping public List<MotorcycleDTO> listar(final Authentication auth) { return service.listar(auth.getName()); }
    @GetMapping("/{id}") public MotorcycleDTO buscar(@PathVariable final UUID id, final Authentication auth) { ... }
    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public MotorcycleDTO criar(@Valid @RequestBody final MotorcycleRequestDTO req, final Authentication auth) { ... }
    @PutMapping("/{id}") public MotorcycleDTO atualizar(@PathVariable final UUID id, @Valid @RequestBody final MotorcycleRequestDTO req, final Authentication auth) { ... }
    @DeleteMapping("/{id}") @ResponseStatus(HttpStatus.NO_CONTENT) public void excluir(@PathVariable final UUID id, final Authentication auth) { ... }
    @GetMapping("/{id}/history") public List<MotorcycleRevisionDTO> historico(@PathVariable final UUID id, final Authentication auth) { return auditService.historicoMoto(id, auth.getName()); }
}
```
Com `@Tag(name = "Motos")` e `@Operation(summary = ...)` em cada método (springdoc), como nos controllers do budget.

- [ ] **Step 7: Rodar e ver passar** — `./gradlew test` → PASS (controller, módulo, IT).

- [ ] **Step 8: Commit** — `feat(motos): adiciona CRUD de motos, histórico e trava do módulo MOTO`.

---

### Task 5: Hodômetro — regras de monotonicidade e leitura avulsa

**Files:**
- Create: `domain/OdometerPoint.java`, `domain/OdometerRules.java`, `models/entities/OdometerReading.java`, `models/dto/{OdometerReadingRequestDTO,OdometerReadingDTO}.java`, `repositories/OdometerReadingRepository.java`, `services/OdometerService.java`, `controllers/OdometerReadingController.java`
- Create: `db/changelog/v0.0.1/create/261006_0002_create_table_odometer_readings.sql`
- Test: `domain/OdometerRulesTest.java`, `controllers/OdometerReadingControllerTest.java`, `services/OdometerServiceIT.java`

**Interfaces:**
- Produces:
  - `record OdometerPoint(UUID id, LocalDate date, int km)`
  - `OdometerRules.validar(List<OdometerPoint> outros, int hodometroInicial, LocalDate data, int km)` — lança `InvalidOdometerException`; `OdometerRules.atual(List<OdometerPoint> pontos, int hodometroInicial): int`
  - `OdometerService`: `List<OdometerPoint> pontos(UUID motoId, String owner)` (união de abastecimentos + trocas + leituras da moto), `void validarNovo(UUID motoId, String owner, LocalDate data, int km, UUID ignorarId)`, `int hodometroAtual(UUID motoId, String owner)`
  - `OdometerReadingRepository.findByMotorcycleIdAndOwnerUsernameOrderByDateAsc(UUID, String)`
  - `POST /api/v1/motorcycles/{id}/odometer-readings` (201), `GET` lista, `DELETE /{readingId}`
  - `OdometerReadingRequestDTO(LocalDate date, Integer odometerKm)`; `OdometerReadingDTO(UUID id, LocalDate date, int odometerKm)`

- [ ] **Step 1: Teste de unidade que falha** — `OdometerRulesTest`:
```java
class OdometerRulesTest {
    private static OdometerPoint p(final String data, final int km) { return new OdometerPoint(UUID.randomUUID(), LocalDate.parse(data), km); }

    @Test void aceitaHodometroEntreVizinhos() {
        final var outros = List.of(p("2026-01-10", 1000), p("2026-03-10", 2000));
        assertThatCode(() -> OdometerRules.validar(outros, 500, LocalDate.parse("2026-02-10"), 1500)).doesNotThrowAnyException();
    }
    @Test void rejeitaAbaixoDoInicial() {
        assertThatThrownBy(() -> OdometerRules.validar(List.of(), 1200, LocalDate.parse("2026-01-01"), 1199))
            .isInstanceOf(InvalidOdometerException.class).hasMessageContaining("1200");
    }
    @Test void rejeitaMenorQueRegistroAnterior() {
        final var outros = List.of(p("2026-01-10", 1000));
        assertThatThrownBy(() -> OdometerRules.validar(outros, 0, LocalDate.parse("2026-02-01"), 999))
            .isInstanceOf(InvalidOdometerException.class);
    }
    @Test void rejeitaMaiorQueRegistroPosterior() {
        final var outros = List.of(p("2026-03-10", 2000));
        assertThatThrownBy(() -> OdometerRules.validar(outros, 0, LocalDate.parse("2026-02-01"), 2001))
            .isInstanceOf(InvalidOdometerException.class);
    }
    @Test void mesmaDataNaoCompara() {
        final var outros = List.of(p("2026-02-01", 1500));
        assertThatCode(() -> OdometerRules.validar(outros, 0, LocalDate.parse("2026-02-01"), 1400)).doesNotThrowAnyException();
    }
    @Test void atualEOMaiorEntrePontosEInicial() {
        assertThat(OdometerRules.atual(List.of(p("2026-01-10", 1000), p("2026-02-10", 1800)), 500)).isEqualTo(1800);
        assertThat(OdometerRules.atual(List.of(), 500)).isEqualTo(500);
    }
}
```
`OdometerReadingControllerTest` (slice): 201 em POST válido; 400 em `odometerKm` ausente/negativo; 400 com `ProblemDetail` quando o service lança `InvalidOdometerException`; 404 de moto alheia. `OdometerServiceIT`: moto com inicial 1000 → leitura 1500 em 10/01 ok; leitura 1400 em 20/01 → `InvalidOdometerException`; leitura de outro dono na mesma moto → `ResourceNotFoundException`.

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*OdometerRulesTest'` → FAIL (classes inexistentes).

- [ ] **Step 3: Implementar o domínio**
```java
public record OdometerPoint(UUID id, LocalDate date, int km) {}

public final class OdometerRules {
    private OdometerRules() {}

    /** Hodômetro é monotônico no tempo: mesma data não é comparada (ordem do dia é desconhecida). */
    public static void validar(final List<OdometerPoint> outros, final int hodometroInicial, final LocalDate data, final int km) {
        if (km < hodometroInicial) {
            throw new InvalidOdometerException("Hodômetro (%d km) abaixo do inicial da moto (%d km)".formatted(km, hodometroInicial));
        }
        for (final var ponto : outros) {
            if (ponto.date().isBefore(data) && ponto.km() > km) {
                throw new InvalidOdometerException("Hodômetro (%d km) menor que o registro de %s (%d km)".formatted(km, ponto.date(), ponto.km()));
            }
            if (ponto.date().isAfter(data) && ponto.km() < km) {
                throw new InvalidOdometerException("Hodômetro (%d km) maior que o registro de %s (%d km)".formatted(km, ponto.date(), ponto.km()));
            }
        }
    }

    public static int atual(final List<OdometerPoint> pontos, final int hodometroInicial) {
        return Math.max(hodometroInicial, pontos.stream().mapToInt(OdometerPoint::km).max().orElse(hodometroInicial));
    }
}
```

- [ ] **Step 4: Migration** `261006_0002_create_table_odometer_readings.sql` — tabela `moto.odometer_readings(id UUID PK DEFAULT gen_random_uuid(), motorcycle_id UUID NOT NULL REFERENCES moto.motorcycles(id) ON DELETE CASCADE, date DATE NOT NULL, odometer_km INTEGER NOT NULL CHECK (odometer_km >= 0), owner_username VARCHAR(255) NOT NULL, created_at/updated_at TIMESTAMP(6), created_by/updated_by VARCHAR(50))`, índice `(motorcycle_id, date)`, e `odometer_readings_aud` (mesmas colunas sem FK/CHECK + `rev`/`revtype`, PK `(id, rev)`), cada um em seu changeset com a precondition do Task 4.

- [ ] **Step 5: Entidade `OdometerReading`** (Lombok + `@Audited` + auditoria, `@ManyToOne(fetch = LAZY) @JoinColumn(name = "motorcycle_id", nullable = false) Motorcycle motorcycle`, `LocalDate date`, `int odometerKm`, `ownerUsername`), repository, DTOs (`@NotNull LocalDate date`, `@NotNull @Min(0) Integer odometerKm`).

- [ ] **Step 6: `OdometerService`** — `pontos` junta `RefuelingRepository`, `OilChangeRepository` e `OdometerReadingRepository` (os dois primeiros só passam a existir nas Tasks 7/8: nesta tarefa `pontos` usa apenas leituras e é **estendido** nas Tasks 7 e 8 — cada uma adiciona sua fonte e seu teste de integração no `OdometerServiceIT`); `validarNovo` chama `motorcycleService.exigirDoDono`, monta a lista sem `ignorarId` e delega a `OdometerRules.validar`. `OdometerReadingController` (`criar`/`listar`/`excluir`) chama `validarNovo` antes de salvar.

- [ ] **Step 7: Rodar e ver passar** — `./gradlew test` → PASS.
- [ ] **Step 8: Commit** — `feat(hodometro): adiciona leituras de hodômetro e regra de monotonicidade`.

---

### Task 6: `ConsumptionCalculator` — consumo por trecho e janelas ponderadas (domínio puro)

**Files:**
- Create: `domain/FuelEntry.java`, `domain/Segment.java`, `domain/ConsumptionWindow.java`, `domain/ConsumptionCalculator.java`, `domain/OdometerTimeline.java`
- Test: `domain/ConsumptionCalculatorTest.java`, `domain/OdometerTimelineTest.java`

**Interfaces:**
- Produces:
```java
public record FuelEntry(LocalDate date, int odometerKm, BigDecimal liters, BigDecimal totalValue, boolean fullTank) {}
public record Segment(LocalDate date, int km, BigDecimal liters, BigDecimal cost, boolean exact) {
    /** km/l do trecho (2 casas, HALF_UP); null quando km == 0. */
    public BigDecimal kmPerLiter() { return km > 0 ? BigDecimal.valueOf(km).divide(liters, 2, RoundingMode.HALF_UP) : null; }
}
public record ConsumptionWindow(
    BigDecimal litersRefueled, BigDecimal totalSpent, BigDecimal pricePerLiter,
    int segmentKm, BigDecimal kmPerLiter, BigDecimal costPerKm,
    int segmentCount, boolean lowConfidence,
    BigDecimal bestKmPerLiter, BigDecimal worstKmPerLiter, Integer longestSegmentKm) {}
```
- `ConsumptionCalculator.MIN_SEGMENTS_CONFIDENT = 3`; `static List<Segment> segmentos(List<FuelEntry> ordenados)`; `static ConsumptionWindow janela(List<FuelEntry> ordenados, List<Segment> segmentos, LocalDate de, LocalDate ate)` (`de`/`ate` nulos = sem limite).
- `OdometerTimeline.kmNaJanela(List<OdometerPoint> pontos, int hodometroInicial, LocalDate de, LocalDate ate): int` e `LocalDate primeiraData(...)` não — só a primeira.
- Entrada **sempre ordenada** por `(date, odometerKm)` ascendente (responsabilidade do service).

- [ ] **Step 1: Teste que falha** — `ConsumptionCalculatorTest` com a massa fixa (preço em R$):
```java
private static FuelEntry e(final String data, final int km, final String litros, final String valor, final boolean cheio) {
    return new FuelEntry(LocalDate.parse(data), km, new BigDecimal(litros), new BigDecimal(valor), cheio);
}
private static final List<FuelEntry> MASSA = List.of(
    e("2026-01-05", 1000, "10.00", "60.00", true),
    e("2026-01-20", 1300, "8.00", "50.00", true),
    e("2026-02-10", 1500, "5.00", "32.00", false),
    e("2026-02-25", 1700, "10.00", "63.00", true));

@Test void primeiroAbastecimentoNaoGeraTrecho() {
    assertThat(ConsumptionCalculator.segmentos(List.of(MASSA.get(0)))).isEmpty();
    assertThat(ConsumptionCalculator.segmentos(List.of())).isEmpty();
}
@Test void trechoEntreDoisCheiosEExato() {
    final var segs = ConsumptionCalculator.segmentos(MASSA);
    assertThat(segs).hasSize(3);
    assertThat(segs.get(0).km()).isEqualTo(300);
    assertThat(segs.get(0).kmPerLiter()).isEqualByComparingTo("37.50");
    assertThat(segs.get(0).exact()).isTrue();
}
@Test void trechoComParcialEEstimado() {
    final var segs = ConsumptionCalculator.segmentos(MASSA);
    assertThat(segs.get(1).kmPerLiter()).isEqualByComparingTo("40.00");
    assertThat(segs.get(1).exact()).isFalse();   // atual parcial
    assertThat(segs.get(2).kmPerLiter()).isEqualByComparingTo("20.00");
    assertThat(segs.get(2).exact()).isFalse();   // anterior parcial
}
@Test void janelaDeJaneiroTemUmTrechoEBaixaConfianca() {
    final var segs = ConsumptionCalculator.segmentos(MASSA);
    final var jan = ConsumptionCalculator.janela(MASSA, segs, LocalDate.parse("2026-01-01"), LocalDate.parse("2026-01-31"));
    assertThat(jan.litersRefueled()).isEqualByComparingTo("18.00");
    assertThat(jan.totalSpent()).isEqualByComparingTo("110.00");
    assertThat(jan.segmentKm()).isEqualTo(300);
    assertThat(jan.kmPerLiter()).isEqualByComparingTo("37.50");
    assertThat(jan.costPerKm()).isEqualByComparingTo("0.17");
    assertThat(jan.segmentCount()).isEqualTo(1);
    assertThat(jan.lowConfidence()).isTrue();
}
@Test void janelaDeFevereiroEPonderadaNaoMediaDeMedias() {
    final var segs = ConsumptionCalculator.segmentos(MASSA);
    final var fev = ConsumptionCalculator.janela(MASSA, segs, LocalDate.parse("2026-02-01"), LocalDate.parse("2026-02-28"));
    assertThat(fev.kmPerLiter()).isEqualByComparingTo("26.67");   // 400/15, não (40+20)/2 = 30
    assertThat(fev.costPerKm()).isEqualByComparingTo("0.24");
    assertThat(fev.pricePerLiter()).isEqualByComparingTo("6.333");
    assertThat(fev.bestKmPerLiter()).isEqualByComparingTo("40.00");
    assertThat(fev.worstKmPerLiter()).isEqualByComparingTo("20.00");
    assertThat(fev.longestSegmentKm()).isEqualTo(200);
}
@Test void janelaSemLimitesCobreTudoEGanhaConfianca() {
    final var segs = ConsumptionCalculator.segmentos(MASSA);
    final var tudo = ConsumptionCalculator.janela(MASSA, segs, null, null);
    assertThat(tudo.kmPerLiter()).isEqualByComparingTo("30.43");   // 700/23
    assertThat(tudo.segmentCount()).isEqualTo(3);
    assertThat(tudo.lowConfidence()).isFalse();
}
@Test void janelaSemDadosDevolveZerosENulos() {
    final var vazia = ConsumptionCalculator.janela(List.of(), List.of(), null, null);
    assertThat(vazia.litersRefueled()).isEqualByComparingTo("0");
    assertThat(vazia.kmPerLiter()).isNull();
    assertThat(vazia.lowConfidence()).isTrue();
}
@Test void trechoSemKmNaoEntraNoMelhorPior() {
    final var entradas = List.of(e("2026-03-01", 2000, "5.00", "30.00", true), e("2026-03-02", 2000, "1.00", "6.00", false));
    final var segs = ConsumptionCalculator.segmentos(entradas);
    assertThat(segs.get(0).kmPerLiter()).isNull();
    final var j = ConsumptionCalculator.janela(entradas, segs, null, null);
    assertThat(j.bestKmPerLiter()).isNull();
    assertThat(j.kmPerLiter()).isNull();   // km total 0
}
```
`OdometerTimelineTest`:
```java
private static OdometerPoint p(final String d, final int km) { return new OdometerPoint(UUID.randomUUID(), LocalDate.parse(d), km); }
@Test void kmDoMesUsaFimDoMesAnteriorComoBase() {
    final var pontos = List.of(p("2026-01-20", 1300), p("2026-02-10", 1500), p("2026-02-25", 1700));
    assertThat(OdometerTimeline.kmNaJanela(pontos, 1000, LocalDate.parse("2026-02-01"), LocalDate.parse("2026-02-28"))).isEqualTo(400);
}
@Test void primeiroMesUsaHodometroInicial() {
    final var pontos = List.of(p("2026-01-20", 1300));
    assertThat(OdometerTimeline.kmNaJanela(pontos, 1000, LocalDate.parse("2026-01-01"), LocalDate.parse("2026-01-31"))).isEqualTo(300);
}
@Test void mesSemRegistrosDaZero() {
    final var pontos = List.of(p("2026-01-20", 1300));
    assertThat(OdometerTimeline.kmNaJanela(pontos, 1000, LocalDate.parse("2026-03-01"), LocalDate.parse("2026-03-31"))).isZero();
}
@Test void semLimitesSomaTudoDesdeOInicial() {
    assertThat(OdometerTimeline.kmNaJanela(List.of(p("2026-02-25", 1700)), 1000, null, null)).isEqualTo(700);
}
```

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*ConsumptionCalculatorTest' --tests '*OdometerTimelineTest'` → FAIL (classes inexistentes).

- [ ] **Step 3: Implementar**
```java
public final class ConsumptionCalculator {
    public static final int MIN_SEGMENTS_CONFIDENT = 3;
    private ConsumptionCalculator() {}

    public static List<Segment> segmentos(final List<FuelEntry> ordenados) {
        final var segmentos = new ArrayList<Segment>();
        for (int i = 1; i < ordenados.size(); i++) {
            final var anterior = ordenados.get(i - 1);
            final var atual = ordenados.get(i);
            final int km = Math.max(0, atual.odometerKm() - anterior.odometerKm());
            segmentos.add(new Segment(atual.date(), km, atual.liters(), atual.totalValue(),
                    anterior.fullTank() && atual.fullTank()));
        }
        return List.copyOf(segmentos);
    }

    public static ConsumptionWindow janela(final List<FuelEntry> ordenados, final List<Segment> segmentos,
                                           final LocalDate de, final LocalDate ate) {
        final var entradas = ordenados.stream().filter(e -> dentro(e.date(), de, ate)).toList();
        final var trechos = segmentos.stream().filter(s -> dentro(s.date(), de, ate)).toList();

        final var litros = entradas.stream().map(FuelEntry::liters).reduce(BigDecimal.ZERO, BigDecimal::add);
        final var gasto = entradas.stream().map(FuelEntry::totalValue).reduce(BigDecimal.ZERO, BigDecimal::add);
        final var preco = litros.signum() > 0 ? gasto.divide(litros, 3, RoundingMode.HALF_UP) : null;

        final int km = trechos.stream().mapToInt(Segment::km).sum();
        final var litrosTrechos = trechos.stream().map(Segment::liters).reduce(BigDecimal.ZERO, BigDecimal::add);
        final var custoTrechos = trechos.stream().map(Segment::cost).reduce(BigDecimal.ZERO, BigDecimal::add);
        final var kmPorLitro = km > 0 && litrosTrechos.signum() > 0
                ? BigDecimal.valueOf(km).divide(litrosTrechos, 2, RoundingMode.HALF_UP) : null;
        final var custoPorKm = km > 0 ? custoTrechos.divide(BigDecimal.valueOf(km), 2, RoundingMode.HALF_UP) : null;

        final var eficiencias = trechos.stream().map(Segment::kmPerLiter).filter(Objects::nonNull).toList();
        return new ConsumptionWindow(litros, gasto, preco, km, kmPorLitro, custoPorKm, trechos.size(),
                trechos.size() < MIN_SEGMENTS_CONFIDENT,
                eficiencias.stream().max(Comparator.naturalOrder()).orElse(null),
                eficiencias.stream().min(Comparator.naturalOrder()).orElse(null),
                trechos.stream().map(Segment::km).max(Comparator.naturalOrder()).orElse(null));
    }

    private static boolean dentro(final LocalDate data, final LocalDate de, final LocalDate ate) {
        return (de == null || !data.isBefore(de)) && (ate == null || !data.isAfter(ate));
    }
}

public final class OdometerTimeline {
    private OdometerTimeline() {}

    /** km entre o hodômetro ao fim do período anterior (ou o inicial) e o último registro até {@code ate}. */
    public static int kmNaJanela(final List<OdometerPoint> pontos, final int hodometroInicial,
                                 final LocalDate de, final LocalDate ate) {
        final int superior = pontos.stream().filter(p -> ate == null || !p.date().isAfter(ate))
                .mapToInt(OdometerPoint::km).max().orElse(hodometroInicial);
        final int inferior = de == null ? hodometroInicial
                : pontos.stream().filter(p -> p.date().isBefore(de)).mapToInt(OdometerPoint::km).max().orElse(hodometroInicial);
        return Math.max(0, Math.max(superior, hodometroInicial) - Math.max(inferior, hodometroInicial));
    }
}
```

- [ ] **Step 4: Rodar e ver passar** — mesmos testes → PASS. Rodar também `./gradlew test` completo.
- [ ] **Step 5: Commit** — `feat(consumo): adiciona cálculo de consumo por trecho e janelas ponderadas`.

---

### Task 7: Abastecimentos — CRUD com validação de hodômetro

**Files:**
- Create: `models/enums/FuelType.java`, `models/entities/Refueling.java`, `models/dto/{RefuelingRequestDTO,RefuelingDTO}.java`, `repositories/RefuelingRepository.java`, `services/RefuelingService.java`, `controllers/RefuelingController.java`
- Modify: `services/OdometerService.java` (incluir abastecimentos em `pontos`)
- Create: `db/changelog/v0.0.1/create/261006_0003_create_table_refuelings.sql`
- Test: `controllers/RefuelingControllerTest.java`, `services/RefuelingServiceIT.java`

**Interfaces:**
- Consumes: `MotorcycleService.exigirDoDono`, `OdometerService.validarNovo(UUID motoId, String owner, LocalDate data, int km, UUID ignorarId)`.
- Produces:
  - `enum FuelType { GASOLINA_COMUM, GASOLINA_ADITIVADA, ETANOL }`
  - `RefuelingRequestDTO(LocalDate date, Integer odometerKm, BigDecimal liters, BigDecimal totalValue, String station, FuelType fuelType, Boolean fullTank)`
  - `RefuelingDTO(UUID id, LocalDate date, int odometerKm, BigDecimal liters, BigDecimal totalValue, BigDecimal pricePerLiter, String station, FuelType fuelType, boolean fullTank)`
  - `RefuelingService`: `Page<RefuelingDTO> listar(UUID motoId, String owner, LocalDate de, LocalDate ate, Pageable)`, `RefuelingDTO criar(UUID, RefuelingRequestDTO, String)`, `RefuelingDTO atualizar(UUID motoId, UUID id, RefuelingRequestDTO, String)`, `void excluir(UUID motoId, UUID id, String)`, `List<FuelEntry> entradasOrdenadas(UUID motoId, String owner)`
  - `RefuelingRepository.findByMotorcycleIdAndOwnerUsernameAndDateBetween(UUID, String, LocalDate, LocalDate, Pageable): Page<Refueling>`, `findByMotorcycleIdAndOwnerUsernameOrderByDateAscOdometerKmAsc(UUID, String): List<Refueling>`, `findByIdAndMotorcycleIdAndOwnerUsername(UUID, UUID, String)`
  - Rotas: `GET/POST /api/v1/motorcycles/{motoId}/refuelings`, `PUT/DELETE /api/v1/motorcycles/{motoId}/refuelings/{id}`; `GET` aceita `from`, `to` (ISO), `page`, `size` (default 20), sort padrão `date,desc`.

- [ ] **Step 1: Testes que falham**
  - `RefuelingControllerTest` (slice, mocks de `RefuelingService`): 201 válido; 400 para `liters = 0`, `totalValue` ausente, `odometerKm` negativo, `date` ausente (com `errors[].field`); 400 `ProblemDetail` quando o service lança `InvalidOdometerException`; 200 paginado (`$.content`, `$.totalElements`) — usar `PageImpl`; 404 de moto alheia; 204 no delete.
  - `RefuelingServiceIT extends PostgresIT` — cenários: (1) criar 3 abastecimentos e `entradasOrdenadas` volta ordenado por data/odômetro com `fullTank` preservado; (2) criar com hodômetro menor que o anterior → `InvalidOdometerException`; (3) editar um abastecimento sem mudar o hodômetro **não** conflita consigo mesmo (`ignorarId`); (4) `listar` com `de/ate` filtra por data e pagina; (5) abastecimento de moto de outro dono → `ResourceNotFoundException`; (6) `pricePerLiter` = `totalValue/liters` com 3 casas (60.00/10.00 → 6.000).

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*Refueling*'` → FAIL.

- [ ] **Step 3: Migration** `261006_0003_create_table_refuelings.sql` — `moto.refuelings(id UUID PK DEFAULT gen_random_uuid(), motorcycle_id UUID NOT NULL REFERENCES moto.motorcycles(id) ON DELETE CASCADE, date DATE NOT NULL, odometer_km INTEGER NOT NULL CHECK (odometer_km >= 0), liters NUMERIC(6,2) NOT NULL CHECK (liters > 0), total_value NUMERIC(10,2) NOT NULL CHECK (total_value > 0), station VARCHAR(120), fuel_type VARCHAR(30) NOT NULL, full_tank BOOLEAN NOT NULL DEFAULT FALSE, owner_username VARCHAR(255) NOT NULL, + colunas de auditoria)`, índice `(motorcycle_id, date, odometer_km)`; mais `refuelings_aud` (changesets separados, precondition por tabela).

- [ ] **Step 4: Entidade** `Refueling` (Lombok, `@Audited`, auditoria; `@Enumerated(EnumType.STRING) FuelType fuelType`; `BigDecimal liters` `precision 6 scale 2`; `BigDecimal totalValue` `precision 10 scale 2`; `boolean fullTank`; `@ManyToOne(LAZY) Motorcycle motorcycle`).
- [ ] **Step 5: DTOs + validação** — `RefuelingRequestDTO`: `@NotNull LocalDate date`, `@NotNull @Min(0) Integer odometerKm`, `@NotNull @DecimalMin(value="0.0", inclusive=false) @Digits(integer=4, fraction=2) BigDecimal liters`, `@NotNull @DecimalMin(value="0.0", inclusive=false) @Digits(integer=8, fraction=2) BigDecimal totalValue`, `@Size(max=120) String station`, `@NotNull FuelType fuelType`, `Boolean fullTank` (null → false). Mensagens novas em `messages.properties`: `abastecimento.naoEncontrado=Abastecimento não encontrado`, `abastecimento.dataObrigatoria`, `abastecimento.litrosInvalidos=Litros deve ser maior que zero`, `abastecimento.valorInvalido=Valor deve ser maior que zero`, `abastecimento.combustivelObrigatorio`.
- [ ] **Step 6: Repository, Service, Controller** — `criar`: `motorcycleService.exigirDoDono` → `odometerService.validarNovo(motoId, owner, req.date(), req.odometerKm(), null)` → salva. `atualizar`: idem com `ignorarId = id`. `listar`: `de` default `LocalDate.of(1900,1,1)`, `ate` default `LocalDate.of(9999,12,31)`; `@PageableDefault(size = 20, sort = {"date", "odometerKm"}, direction = DESC)`. `entradasOrdenadas` mapeia para `FuelEntry`. Em `OdometerService.pontos`, somar `RefuelingRepository` (e estender `OdometerServiceIT` com o caso "abastecimento conta como ponto").
- [ ] **Step 7: Rodar e ver passar** — `./gradlew test` → PASS.
- [ ] **Step 8: Commit** — `feat(abastecimentos): adiciona CRUD de abastecimentos com validação de hodômetro`.

---

### Task 8: Troca de óleo — CRUD, intervalos padrão e próxima troca

**Files:**
- Create: `models/enums/OilType.java`, `domain/{OilStatusLevel,OilLimit,OilStatus,OilStatusCalculator}.java`, `models/entities/OilChange.java`, `models/dto/{OilChangeRequestDTO,OilChangeDTO,OilIntervalDTO,OilStatusDTO}.java`, `repositories/OilChangeRepository.java`, `services/OilChangeService.java`, `controllers/OilChangeController.java`
- Modify: `services/OdometerService.java` (incluir trocas em `pontos`)
- Create: `db/changelog/v0.0.1/create/261006_0004_create_table_oil_changes.sql`
- Test: `domain/OilStatusCalculatorTest.java`, `controllers/OilChangeControllerTest.java`, `services/OilChangeServiceIT.java`

**Interfaces:**
- Produces:
  - `enum OilType { MINERAL, SEMI_SYNTHETIC, SYNTHETIC }`; `enum OilStatusLevel { OK, PERTO, VENCIDA }`; `enum OilLimit { KM, TIME }`
  - `record OilStatus(LocalDate dueDate, int dueKm, int kmRemaining, long daysRemaining, OilStatusLevel level, OilLimit limitedBy)`
  - `OilStatusCalculator.calcular(OilChange ultima, int hodometroAtual, LocalDate hoje): OilStatus` — `static`, constantes `NEAR_KM_MIN = 500`, `NEAR_DAYS_MIN = 30`
  - `OilIntervalDTO(OilType type, int defaultKm, int minKm, int maxKm, int defaultMonths)`
  - `OilChangeRequestDTO(LocalDate date, Integer odometerKm, OilType oilType, String brand, String viscosity, BigDecimal cost, Integer intervalKm, Integer intervalMonths)`; `OilChangeDTO` = request + `UUID id`
  - `OilStatusDTO(OilChangeDTO lastChange, int currentOdometerKm, LocalDate dueDate, int dueKm, int kmRemaining, long daysRemaining, OilStatusLevel level, OilLimit limitedBy)`; `lastChange == null` quando a moto nunca trocou óleo (resposta 200 com `lastChange: null` e demais campos nulos — usar `Integer`/`Long`/enum nulos)
  - `OilChangeService`: `listar`, `criar`, `atualizar`, `excluir` (mesma forma do `RefuelingService`), `OilStatusDTO status(UUID motoId, String owner, LocalDate hoje)`, `static List<OilIntervalDTO> intervalosPadrao()`
  - Rotas: `GET/POST /api/v1/motorcycles/{motoId}/oil-changes`, `PUT/DELETE .../{id}`, `GET /api/v1/motorcycles/{motoId}/oil-status`, `GET /api/v1/oil-intervals`
  - Padrões: `MINERAL` 1500 km (faixa 1000–1500), 6 meses; `SEMI_SYNTHETIC` 4000 (3000–4000), 6 meses; `SYNTHETIC` 6000 (5000–6000), 12 meses.

- [ ] **Step 1: Teste de unidade que falha** — `OilStatusCalculatorTest` (troca em 2026-06-01, 20.000 km, 4.000 km / 6 meses → vence 2026-12-01 / 24.000 km):
```java
private static OilChange troca() { return OilChange.builder().date(LocalDate.parse("2026-06-01")).odometerKm(20000).intervalKm(4000).intervalMonths(6).build(); }

@Test void emDiaQuandoFaltaMuito() {
    final var s = OilStatusCalculator.calcular(troca(), 23000, LocalDate.parse("2026-08-01"));
    assertThat(s.dueKm()).isEqualTo(24000);
    assertThat(s.dueDate()).isEqualTo(LocalDate.parse("2026-12-01"));
    assertThat(s.kmRemaining()).isEqualTo(1000);
    assertThat(s.daysRemaining()).isEqualTo(122);
    assertThat(s.level()).isEqualTo(OilStatusLevel.OK);
    assertThat(s.limitedBy()).isEqualTo(OilLimit.KM);
}
@Test void pertoPorKm() {
    assertThat(OilStatusCalculator.calcular(troca(), 23600, LocalDate.parse("2026-08-01")).level()).isEqualTo(OilStatusLevel.PERTO);   // faltam 400 <= 500
}
@Test void pertoPorTempo() {
    final var s = OilStatusCalculator.calcular(troca(), 20500, LocalDate.parse("2026-11-10"));   // faltam 21 dias <= 30
    assertThat(s.level()).isEqualTo(OilStatusLevel.PERTO);
    assertThat(s.limitedBy()).isEqualTo(OilLimit.TIME);
}
@Test void vencidaPorKm() {
    final var s = OilStatusCalculator.calcular(troca(), 24100, LocalDate.parse("2026-08-01"));
    assertThat(s.level()).isEqualTo(OilStatusLevel.VENCIDA);
    assertThat(s.kmRemaining()).isEqualTo(-100);
}
@Test void vencidaPorTempo() {
    final var s = OilStatusCalculator.calcular(troca(), 21000, LocalDate.parse("2026-12-02"));
    assertThat(s.level()).isEqualTo(OilStatusLevel.VENCIDA);
    assertThat(s.daysRemaining()).isEqualTo(-1);
    assertThat(s.limitedBy()).isEqualTo(OilLimit.TIME);
}
@Test void limiarProporcionalParaIntervaloLongo() {   // 10% de 10.000 km = 1.000 > 500
    final var longa = OilChange.builder().date(LocalDate.parse("2026-06-01")).odometerKm(0).intervalKm(10000).intervalMonths(12).build();
    assertThat(OilStatusCalculator.calcular(longa, 9200, LocalDate.parse("2026-07-01")).level()).isEqualTo(OilStatusLevel.PERTO);   // faltam 800 <= 1.000
}
```
`OilChangeControllerTest` (slice): 201 válido; 400 para `intervalKm = 0`, `intervalMonths` ausente, `oilType` ausente; `GET /oil-status` 200 com `lastChange: null` quando nunca trocou; `GET /api/v1/oil-intervals` devolve 3 itens (`$[0].type`). `OilChangeServiceIT`: criar troca valida hodômetro (menor que o anterior → 400); `status` usa `hodometroAtual` (maior entre abastecimento/troca/leitura/inicial) — troca em 20.000, abastecimento em 23.600 → `kmRemaining` 400 e `PERTO`; só a **última** troca (por data/hodômetro) conta; moto sem troca → `lastChange` nulo.

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*OilStatusCalculatorTest'` → FAIL.

- [ ] **Step 3: Implementar o domínio**
```java
public final class OilStatusCalculator {
    public static final int NEAR_KM_MIN = 500;
    public static final int NEAR_DAYS_MIN = 30;
    private OilStatusCalculator() {}

    public static OilStatus calcular(final OilChange ultima, final int hodometroAtual, final LocalDate hoje) {
        final int vencimentoKm = ultima.getOdometerKm() + ultima.getIntervalKm();
        final LocalDate vencimentoData = ultima.getDate().plusMonths(ultima.getIntervalMonths());
        final int kmRestantes = vencimentoKm - hodometroAtual;
        final long diasRestantes = ChronoUnit.DAYS.between(hoje, vencimentoData);
        final long diasIntervalo = ChronoUnit.DAYS.between(ultima.getDate(), vencimentoData);

        final boolean vencida = kmRestantes <= 0 || diasRestantes <= 0;
        final boolean perto = kmRestantes <= Math.max(NEAR_KM_MIN, ultima.getIntervalKm() / 10)
                || diasRestantes <= Math.max(NEAR_DAYS_MIN, diasIntervalo / 10);
        final var nivel = vencida ? OilStatusLevel.VENCIDA : perto ? OilStatusLevel.PERTO : OilStatusLevel.OK;

        final double fracaoKm = (double) kmRestantes / ultima.getIntervalKm();
        final double fracaoTempo = diasIntervalo == 0 ? 0 : (double) diasRestantes / diasIntervalo;
        final var limite = fracaoKm <= fracaoTempo ? OilLimit.KM : OilLimit.TIME;
        return new OilStatus(vencimentoData, vencimentoKm, kmRestantes, diasRestantes, nivel, limite);
    }
}
```
(Conferir `pertoPorTempo`: 2026-11-10 → 2026-12-01 = 21 dias; fração km = (24000−20500)/4000 = 0,875 > fração tempo 21/183 → `TIME`. Conferir `vencidaPorTempo`: km 21000 → fração 0,75; tempo −1/183 → `TIME`.)

- [ ] **Step 4: Migration** `261006_0004_create_table_oil_changes.sql` — `moto.oil_changes(id UUID PK, motorcycle_id UUID NOT NULL REFERENCES ... ON DELETE CASCADE, date DATE NOT NULL, odometer_km INTEGER NOT NULL CHECK (>= 0), oil_type VARCHAR(30) NOT NULL, brand VARCHAR(60), viscosity VARCHAR(20), cost NUMERIC(10,2) CHECK (cost IS NULL OR cost >= 0), interval_km INTEGER NOT NULL CHECK (> 0), interval_months INTEGER NOT NULL CHECK (> 0), owner_username, auditoria)`, índice `(motorcycle_id, date)`; `oil_changes_aud`.
- [ ] **Step 5: Entidade, DTOs, repository, service, controller** — mesmo molde da Task 7 (validar hodômetro com `validarNovo`; `@Min(1)` em `intervalKm`/`intervalMonths`; `@Max(100000)`/`@Max(60)` como sanidade). `status`: busca `findFirstByMotorcycleIdAndOwnerUsernameOrderByDateDescOdometerKmDesc`, `odometerService.hodometroAtual`, `OilStatusCalculator.calcular(ultima, atual, hoje)`; `hoje` injetado por `Clock` bean (adicionar `@Bean Clock clock() { return Clock.systemDefaultZone(); }` em `config/ClockConfig` e usar `LocalDate.now(clock)` no controller) para o IT fixar a data com `Clock.fixed`. `OilIntervalController` (`GET /api/v1/oil-intervals`) devolve `OilChangeService.intervalosPadrao()`. Estender `OdometerService.pontos` com as trocas (+ caso no `OdometerServiceIT`).
- [ ] **Step 6: Rodar e ver passar** — `./gradlew test` → PASS.
- [ ] **Step 7: Commit** — `feat(oleo): adiciona trocas de óleo, intervalos padrão e cálculo da próxima troca`.

---

### Task 9: Métricas — resumo, série mensal e série anual

**Files:**
- Create: `models/dto/{StatsDTO,MonthlyStatsDTO,YearlyStatsDTO}.java`, `services/StatsService.java`, `controllers/StatsController.java`
- Test: `services/StatsServiceIT.java`, `controllers/StatsControllerTest.java`

**Interfaces:**
- Consumes: `RefuelingService.entradasOrdenadas`, `OdometerService.pontos`, `MotorcycleService.exigirDoDono`, `ConsumptionCalculator`, `OdometerTimeline`, `Clock`.
- Produces:
```java
public record StatsDTO(LocalDate from, LocalDate to, int km, BigDecimal kmPerDay,
    BigDecimal litersRefueled, BigDecimal totalSpent, BigDecimal pricePerLiter,
    BigDecimal kmPerLiter, BigDecimal costPerKm, int segmentCount, boolean lowConfidence,
    BigDecimal bestKmPerLiter, BigDecimal worstKmPerLiter, Integer longestSegmentKm) {}
public record MonthlyStatsDTO(int year, int month, StatsDTO stats, BigDecimal spentChangePct) {}   // spentChangePct vs mês anterior; null se anterior = 0 ou inexistente
public record YearlyStatsDTO(int year, StatsDTO stats) {}
```
  - `StatsService`: `StatsDTO resumo(UUID motoId, String owner, LocalDate de, LocalDate ate)`, `List<MonthlyStatsDTO> mensal(UUID motoId, String owner, int ano)` (sempre 12 itens), `List<YearlyStatsDTO> anual(UUID motoId, String owner)` (um por ano com algum registro, ordem crescente)
  - Rotas: `GET /api/v1/motorcycles/{id}/stats?from&to`, `/stats/monthly?year`, `/stats/yearly`
  - Regras: `from` default = data do primeiro registro (se não houver registro → `to`); `to` default = hoje; `from > to` → 400 (`InvalidOdometerException` **não**; criar `ResponseStatusException`? — usar `IllegalArgumentException` mapeada no handler para 400 com a mensagem `estatisticas.periodoInvalido`). `kmPerDay = km / dias`, onde `dias = ChronoUnit.DAYS.between(from, min(to, hoje)) + 1` (mín. 1), 2 casas HALF_UP. Série mensal: o mês corrente usa dias decorridos (`min(fimDoMês, hoje)`); meses futuros: tudo zero/nulo.

- [ ] **Step 1: Testes que falham**
  - `StatsServiceIT extends PostgresIT` com `Clock.fixed(2026-03-15)` e a massa da Task 6 gravada pelo `RefuelingService` (moto inicial 1.000 km): `mensal(2026)` → janeiro `km=300`, `kmPerLiter=37.50`, `totalSpent=110.00`, `lowConfidence=true`; fevereiro `km=400`, `kmPerLiter=26.67`, `spentChangePct = (95−110)/110·100 = −13.64`; março `km=0`, `totalSpent=0`, `kmPerLiter=null`; abril…dezembro zerados; 12 itens. `resumo(null, null)`: `from=2026-01-05`, `to=2026-03-15`, `km=700`, `kmPerLiter=30.43`, `segmentCount=3`, `lowConfidence=false`, `kmPerDay = 700/70 = 10.00` (de 05/01 a 15/03 = 70 dias, inclusivo). `anual()` → um item (`2026`). Leitura avulsa de hodômetro (p.ex. 1.850 km em 10/03) aumenta `km` de março para 150 sem alterar o consumo. Moto de outro dono → `ResourceNotFoundException`. `from > to` → exceção.
  - `StatsControllerTest` (slice, mocks): `GET .../stats?from=2026-01-01&to=2026-01-31` → 200 com `$.kmPerLiter`; `from` malformado → 400; `GET .../stats/monthly` sem `year` → 400 (`MissingServletRequestParameterException`); `GET .../stats/yearly` → 200 lista.

- [ ] **Step 2: Rodar e ver falhar** — `./gradlew test --tests '*Stats*'` → FAIL.

- [ ] **Step 3: Implementar** `StatsService.resumo`:
```java
@Transactional(readOnly = true)
public StatsDTO resumo(final UUID motoId, final String owner, final LocalDate de, final LocalDate ate) {
    final var moto = motorcycleService.exigirDoDono(motoId, owner);
    final var entradas = refuelingService.entradasOrdenadas(motoId, owner);
    final var pontos = odometerService.pontos(motoId, owner);
    final var hoje = LocalDate.now(clock);
    final var fim = ate != null ? ate : hoje;
    final var inicio = de != null ? de : primeiraData(entradas, pontos).orElse(fim);
    if (inicio.isAfter(fim)) {
        throw new IllegalArgumentException(messages.getMessage("estatisticas.periodoInvalido"));
    }
    return montar(moto.getInitialOdometerKm(), entradas, pontos, inicio, fim, hoje);
}

private static StatsDTO montar(final int inicial, final List<FuelEntry> entradas, final List<OdometerPoint> pontos,
                               final LocalDate de, final LocalDate ate, final LocalDate hoje) {
    final var segmentos = ConsumptionCalculator.segmentos(entradas);
    final var janela = ConsumptionCalculator.janela(entradas, segmentos, de, ate);
    final int km = OdometerTimeline.kmNaJanela(pontos, inicial, de, ate);
    final long dias = Math.max(1, ChronoUnit.DAYS.between(de, ate.isAfter(hoje) ? hoje : ate) + 1);
    final var kmPorDia = BigDecimal.valueOf(km).divide(BigDecimal.valueOf(dias), 2, RoundingMode.HALF_UP);
    return new StatsDTO(de, ate, km, kmPorDia, janela.litersRefueled(), janela.totalSpent(), janela.pricePerLiter(),
            janela.kmPerLiter(), janela.costPerKm(), janela.segmentCount(), janela.lowConfidence(),
            janela.bestKmPerLiter(), janela.worstKmPerLiter(), janela.longestSegmentKm());
}
```
`mensal(ano)`: para cada mês `m` em 1..12, `de = LocalDate.of(ano, m, 1)`, `ate = de.with(lastDayOfMonth())`, chama `montar` (para meses após `hoje` o `ate.isAfter(hoje)` e `de.isAfter(hoje)` → `dias` mínimo 1, km 0); `spentChangePct = (gasto − gastoAnterior) / gastoAnterior · 100` (2 casas HALF_UP) quando o mês anterior do **mesmo ano** tem gasto > 0 (janeiro: `null`). `anual`: anos distintos de `entradas` ∪ `pontos`, cada um com `montar(1/1, 31/12)`. Registrar no `RestExceptionHandler`:
```java
@ExceptionHandler(IllegalArgumentException.class)
public ProblemDetail handleIllegalArgument(final IllegalArgumentException exception) {
    return problem(HttpStatus.BAD_REQUEST, exception.getMessage());
}
```
(ressalva: só lançar `IllegalArgumentException` com mensagem própria nesta base de código — nunca propagar a de bibliotecas; se preferir mais estrito, criar `InvalidPeriodException` e mapear só ela.) `messages.properties`: `estatisticas.periodoInvalido=A data inicial deve ser anterior ou igual à final`.

- [ ] **Step 3b: Controller** — `StatsController` (`@RequestMapping("/api/v1/motorcycles/{id}/stats")`): `@GetMapping` com `@RequestParam(required = false) @DateTimeFormat(iso = ISO.DATE) LocalDate from/to`; `@GetMapping("/monthly")` com `@RequestParam final int year`; `@GetMapping("/yearly")`.
- [ ] **Step 4: Rodar e ver passar** — `./gradlew test` → PASS.
- [ ] **Step 5: Commit** — `feat(metricas): adiciona resumo, série mensal e série anual`.

---

### Task 10: Contrato OpenAPI, CI, README e `CLAUDE.md` do serviço

**Files:**
- Create: `moto-service/openapi/openapi.yaml` (gerado), `.gitlab-ci.yml`, `README.md`, `CLAUDE.md`
- Test: gate = `./gradlew check` + `contract-drift` local

- [ ] **Step 1: `.gitlab-ci.yml`** — o do `budget-service` **sem** o job `sonarcloud-check` e o bloco de variáveis exclusivo do Sonar (manter `DOCKER_HOST`, `DOCKER_TLS_CERTDIR`, `TESTCONTAINERS_RYUK_DISABLED`); `artifacts.paths: build/libs/moto-service-0.0.1-SNAPSHOT.jar`.
- [ ] **Step 2: Gerar o contrato** — `./gradlew generateOpenApiDocs` (profile `test`, H2) → cria `openapi/openapi.yaml`. Conferir que contém `/api/v1/motorcycles`, `.../refuelings`, `.../oil-changes`, `.../oil-status`, `/api/v1/oil-intervals`, `.../odometer-readings`, `.../stats`, `.../stats/monthly`, `.../stats/yearly` (`grep -c "^  /api/v1" openapi/openapi.yaml`). Rodar duas vezes e `git diff --stat` não pode mudar (determinismo — `springdoc.writer-with-order-by-keys=true`).
- [ ] **Step 3: `README.md`** — estrutura do `budget-service/README.md`: papel, stack, porta, variáveis (`INTROSPECTION_*`, `DATABASE_URL`, `POSTGRES_USER/PASSWORD`, `CORS_ALLOWED_ORIGINS` se existir), rotas, regras de cálculo (trecho exato/estimado, janela ponderada, próxima troca), como rodar.
- [ ] **Step 4: `CLAUDE.md` do serviço** — mesmas seções do `budget-service/CLAUDE.md`, com: papel/autoria (permissão total concedida em 2026-10-06, por serviço), stack, estrutura `br.com.moto`, regras de domínio e armadilhas (escopo por dono/IDOR → 404; hodômetro monotônico e mesma data não comparada; trecho pertence ao mês do abastecimento N; janela ponderada nunca média de médias; `lowConfidence` < 3 trechos; limiar PERTO = max(500 km, 10%) ou max(30 d, 10%); `Clock` injetado), convenção Java (`final`), testes (domínio puro + slice + `PostgresIT`), Liquibase (`yymmdd_nnnn`, `v0.0.1/create`), commits em pt-BR.
- [ ] **Step 5: Verificar** — `./gradlew check` → PASS (inclui JaCoCo).
- [ ] **Step 6: Commit** — `docs: adiciona contrato OpenAPI, CI e documentação do moto-service`.

---

### Task 11: Infra da raiz — compose, env, branches e submódulo

**Files:**
- Modify: `docker-compose.yml`, `docker-compose.prod.yml`, `.env.example`, `.env.prod.example`, `.gitmodules`; confirmar em `scripts/up-all.sh` se serviços são listados (`grep -n "budget-service" scripts/up-all.sh`) e acrescentar `moto-service` onde houver lista.

- [ ] **Step 1: `docker-compose.yml`** — serviço (após `backup-service`, antes do `workbox-app`):
```yaml
  moto-service:
    build: ./moto-service
    container_name: moto-service
    restart: unless-stopped
    environment:
      - PROFILE_ACTIVE=${SPRING_PROFILE:-dev}
      - PORT=8085
      - DATABASE_URL=jdbc:postgresql://${DB_HOST:-postgres}:5432/workbox
      - POSTGRES_USER=moto_service
      - POSTGRES_PASSWORD=moto_service
      - INTROSPECTION_URI=http://workbox-api:8080/api/v1/auth/introspect
      - INTROSPECTION_CLIENT_ID=${MOTO_INTROSPECTION_CLIENT_ID:-moto-service}
      - INTROSPECTION_CLIENT_SECRET=${MOTO_INTROSPECTION_CLIENT_SECRET:-MyS3cur3Cli3ntS3cr3t!M0t0!}
    ports:
      - "${MOTO_SERVICE_PORT:-7059}:8085"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8085/actuator/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s
    deploy:
      resources:
        limits: { cpus: "1", memory: 512M }
```
No `workbox-app`: `environment` ganha `- MOTO_SERVICE_UPSTREAM=http://moto-service:8085` (e **não** entra em `depends_on` duro, como o backup — o nginx resolve por variável).
- [ ] **Step 2: `docker-compose.prod.yml`** — mesmo serviço, sem defaults de segredo: `INTROSPECTION_CLIENT_ID=${MOTO_INTROSPECTION_CLIENT_ID:?defina MOTO_INTROSPECTION_CLIENT_ID em .env.prod}` e `..._SECRET=${MOTO_INTROSPECTION_CLIENT_SECRET:?defina ... - gere com openssl rand -base64 32}`; sem `ports` publicados (seguir o padrão do `backup-service` do arquivo); `MOTO_SERVICE_UPSTREAM` no `workbox-app`.
- [ ] **Step 3: `.env.example` / `.env.prod.example`** — `MOTO_INTROSPECTION_CLIENT_ID=moto-service` + secret (dev: `MyS3cur3Cli3ntS3cr3t!M0t0!`; prod: vazio), com comentário apontando para `workbox-api/.../261006_0001_seed_api_clients_moto_service.sql`.
- [ ] **Step 4: Validar** — `docker compose config -q` e `docker compose --env-file .env.prod.example -f docker-compose.prod.yml config -q` (este pode exigir preencher segredos temporariamente num arquivo no scratchpad, nunca no repo).
- [ ] **Step 5: Branches do repo novo (regra "main primeiro")** — em `moto-service/`: `git branch develop main && git checkout develop` (a `main` já tem o histórico). **Não** criar remote nem fazer push: criar o projeto no GitLab e enviar `main` + `develop` é passo do desenvolvedor/confirmação explícita. Registrar o submódulo **somente depois** que existir remote: até lá, `.gitmodules` **não** é alterado (mesmo estado do `forza-telemetry-service` antes do repo) — anotar no `CLAUDE.md` da raiz (Task 17).
- [ ] **Step 6: Subir o serviço** — `scripts/up-all.sh --build` (nunca `docker compose up` direto — perde `FORZA_HOST_IP`); `curl -s localhost:7059/actuator/health` → `{"status":"UP"}`.
- [ ] **Step 7: Commit (raiz)** — `git add docker-compose.yml docker-compose.prod.yml .env.example .env.prod.example scripts/up-all.sh` (só se alterado) · `chore(infra): adiciona moto-service ao compose e às variáveis de ambiente`.

---

### Task 12: Front — encanamento (proxy, tipos, cliente de API, rota, card)

**Files:**
- Modify: `workbox-app/vite.config.ts`, `workbox-app/nginx.conf.template`, `workbox-app/src/routes/routes.tsx`, `workbox-app/src/pages/Dashboard.tsx`
- Create: `workbox-app/src/interfaces/moto/index.ts`, `workbox-app/src/services/motoApi.ts`, `workbox-app/src/pages/Moto.tsx` (casca: navbar + abas vazias), `workbox-app/src/pages/moto/useMotos.ts`, `workbox-app/src/pages/moto/format.ts`
- Test: `workbox-app/src/test/moto/motoApi.test.ts`, `workbox-app/src/test/moto/format.test.ts`, `workbox-app/src/test/moto/Moto.test.tsx`; ajustar `workbox-app/src/test/Dashboard.test.tsx`

**Interfaces:**
- Produces (`@/interfaces/moto`): `IMotorcycle`, `IMotorcycleRequest`, `IRefueling`, `IRefuelingRequest`, `IRefuelingPage`, `IOilChange`, `IOilChangeRequest`, `IOilInterval`, `IOilStatus`, `IStats`, `IMonthlyStats`, `IYearlyStats`, tipos `FuelType = 'GASOLINA_COMUM' | 'GASOLINA_ADITIVADA' | 'ETANOL'`, `OilType = 'MINERAL' | 'SEMI_SYNTHETIC' | 'SYNTHETIC'`, `OilLevel = 'OK' | 'PERTO' | 'VENCIDA'` — campos idênticos aos DTOs do `openapi.yaml` (BigDecimal → `number`).
- Produces (`motoApi.ts`, funções puras sobre `AxiosInstance`, como `forzaApi.ts`): `listMotorcycles`, `createMotorcycle`, `updateMotorcycle`, `deleteMotorcycle`, `listRefuelings(api, motoId, {from,to,page,size}, signal)`, `createRefueling`, `updateRefueling`, `deleteRefueling`, `listOilChanges`, `createOilChange`, `updateOilChange`, `deleteOilChange`, `getOilStatus`, `listOilIntervals`, `getStats(api, motoId, {from,to}, signal)`, `getMonthlyStats(api, motoId, year, signal)`, `getYearlyStats`.
- Produces (`format.ts`): `formatKm(n)` → `"1.234 km"`; `formatKmPerLiter(n | null)` → `"37,50 km/l"` ou `"—"`; `formatPerLiter(n | null)` → `"R$ 6,33/L"`; `formatDays(n)`; `OIL_TYPE_LABEL`, `FUEL_TYPE_LABEL`.
- Produces (`useMotos.ts`): `useMotos()` → `{ motos, selectedId, select(id), reload(), loading }`; seleção persistida em `localStorage` (`workbox.moto.selecionada`) com `try/catch`; se o id salvo não existir mais, cai na primeira moto ativa.

- [ ] **Step 1: Testes que falham**
  - `format.test.ts`: `formatKm(1234)` → `'1.234 km'`; `formatKmPerLiter(37.5)` → `'37,50 km/l'`; `formatKmPerLiter(null)` → `'—'`; `formatPerLiter(6.333)` → `'R$ 6,33/L'`.
  - `motoApi.test.ts` (axios mockado com `vi.fn()`): `listRefuelings` chama `GET /api/v1/motorcycles/{id}/refuelings` com `params {from,to,page,size}`; `getOilStatus` → `/oil-status`; `getMonthlyStats` → `/stats/monthly` com `{year}`; `createRefueling` faz `POST` com o corpo.
  - `Moto.test.tsx`: renderiza com `AuthContext.Provider value={createAuthValue()}` (`../forza/helpers`) + `BrowserRouter`, `vi.mock('@/services/motoApi')` devolvendo uma moto; mostra título "Workbox Moto", as 4 abas (Resumo, Abastecimentos, Óleo, Motos) e o seletor de moto; sem motos → texto "Cadastre sua primeira moto" e a aba **Motos** ativa.
  - `Dashboard.test.tsx`: card "Moto" habilitado para quem tem `modules: ['MOTO']`; desabilitado sem o módulo (seguir o teste existente do card Forza).

- [ ] **Step 2: Rodar e ver falhar** — `cd workbox-app && npm test -- src/test/moto src/test/Dashboard.test.tsx` → FAIL.

- [ ] **Step 3: Roteamento (dois lugares — têm que andar juntos)**
  - `vite.config.ts`, antes do `'/api'`:
```ts
      '^/api/v1/(motorcycles|oil-intervals)': {
        target: process.env.VITE_MOTO_API_URL || 'http://localhost:7059',
        changeOrigin: true,
      },
```
  - `nginx.conf.template`: `set $moto_upstream ${MOTO_SERVICE_UPSTREAM};` ao lado dos demais e
```nginx
    location /api/v1/motorcycles {
        proxy_pass $moto_upstream;
    }

    location /api/v1/oil-intervals {
        proxy_pass $moto_upstream;
    }
```
  - **Conferir** se o `Dockerfile`/`entrypoint` do front lista as variáveis do `envsubst` (`grep -rn "BUDGET_SERVICE_UPSTREAM" workbox-app --include=Dockerfile --include=*.sh --include=*.template`) e incluir `MOTO_SERVICE_UPSTREAM` onde as outras aparecem.
- [ ] **Step 4: Implementar** `interfaces/moto/index.ts`, `motoApi.ts`, `format.ts`, `useMotos.ts`, `pages/Moto.tsx` (casca: `AppNavbar title="Workbox Moto" icon={<MotorcycleIcon/>}` com `TwoWheeler` de `@mui/icons-material`, `showBackButton backPath="/dashboard"`, seletor `TextField select` de moto, `Tabs` MUI com `aria-label`, painéis `role="tabpanel"`; aba ativa em `?aba=resumo|abastecimentos|oleo|motos` via `useSearchParams`; sem motos → força `motos` + `Alert` "Cadastre sua primeira moto"). Rota em `routes.tsx` (padrão do `/forza`, `ProtectedRoute` já envolve): `{ path: '/moto', lazy: async () => ({ Component: (await import('@/pages/Moto')).default }) }`. Card no `Dashboard.tsx` após o do Forza: `{ id: 'moto', title: 'Moto', description: 'Abastecimentos, consumo, km rodados e troca de óleo da sua moto.', icon: <MotoIcon sx={{ fontSize: 40 }} color="primary" />, path: '/moto', enabled: true, moduleCode: 'MOTO' }` (`TwoWheeler as MotoIcon`).
- [ ] **Step 5: Rodar e ver passar** — `npm test`, `npm run lint`, `npm run build` → PASS (typecheck incluso no build).
- [ ] **Step 6: Commit (submódulo `workbox-app`)** — `feat(moto): adiciona rota, cliente de API e casca do módulo Moto`.

---

### Task 13: Front — aba **Motos** (cadastro e seleção)

**Files:**
- Create: `workbox-app/src/pages/moto/MotosTab.tsx`
- Modify: `workbox-app/src/pages/Moto.tsx` (renderizar a aba)
- Test: `workbox-app/src/test/moto/MotosTab.test.tsx`

**Interfaces:** Consumes `useMotos`, `createMotorcycle`, `updateMotorcycle`, `deleteMotorcycle`, `useSnackbar`, `ConfirmDialog`. Produces `MotosTab` (props: `{ motos: IMotorcycle[]; onChanged: () => void }`).

- [ ] **Step 1: Testes que falham** — (a) lista as motos (apelido, modelo, hodômetro inicial) e vazio → "Nenhuma moto cadastrada."; (b) "Nova moto" abre diálogo; envio vazio mostra "Apelido é obrigatório" e "Modelo é obrigatório" (yup) e **não** chama `createMotorcycle`; (c) preenchendo apelido, modelo e hodômetro inicial chama `createMotorcycle` com `{ nickname, model, initialOdometerKm: 1200, ... }`, mostra snackbar "Moto cadastrada com sucesso!" e chama `onChanged`; (d) hodômetro negativo bloqueia o envio; (e) editar preenche o formulário; (f) excluir pede confirmação ("Excluir moto — apaga também abastecimentos e trocas") e só então chama `deleteMotorcycle`; (g) erro 400 da API aparece no snackbar via `getErrorMessage`.
- [ ] **Step 2: Rodar e ver falhar** — `npm test -- src/test/moto/MotosTab.test.tsx` → FAIL.
- [ ] **Step 3: Implementar** — tabela MUI (responsiva: em `xs` vira lista de cartões), `Dialog` com `react-hook-form` + `yupResolver` (campos: apelido*, marca, modelo*, ano, placa, hodômetro inicial*, capacidade do tanque, ativa); labels associados, `aria-describedby` nos erros; botões "Nova moto"/"Editar"/"Excluir" com `aria-label` contendo o apelido.
- [ ] **Step 4: Rodar e ver passar** — `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 5: Commit** — `feat(moto): adiciona cadastro de motos`.

---

### Task 14: Front — aba **Abastecimentos**

**Files:**
- Create: `workbox-app/src/pages/moto/AbastecimentosTab.tsx`
- Modify: `workbox-app/src/pages/Moto.tsx`
- Test: `workbox-app/src/test/moto/AbastecimentosTab.test.tsx`

**Interfaces:** Consumes `listRefuelings`, `createRefueling`, `updateRefueling`, `deleteRefueling`, `useLazyTabData`, `formatKm`, `formatCurrency`. Produces `AbastecimentosTab` (props: `{ motorcycle: IMotorcycle; active: boolean; onChanged: () => void }` — `onChanged` avisa o Resumo/Óleo para recarregar).

- [ ] **Step 1: Testes que falham** — (a) carrega só quando a aba está ativa (`useLazyTabData`) e mostra data (DD/MM/AAAA), hodômetro, litros, valor, R$/L e selo "tanque cheio" quando `fullTank`; (b) filtro mensal/anual muda os parâmetros `from`/`to` da chamada (`2026-02-01`..`2026-02-28`); (c) paginação: botão "Próxima página" chama com `page: 1`; (d) formulário: litros 0 → "Litros deve ser maior que zero"; valor vazio → "Valor é obrigatório"; hodômetro vazio → erro; (e) envio válido chama `createRefueling` com `{ date: '2026-02-10', odometerKm: 1500, liters: 5, totalValue: 32, fuelType: 'GASOLINA_COMUM', fullTank: false }` e snackbar "Abastecimento registrado!"; (f) erro 400 de hodômetro da API (`detail`) vai pro snackbar; (g) checkbox "Completei o tanque" com texto de ajuda "Marcar melhora a precisão do km/l; é opcional."; (h) excluir com confirmação.
- [ ] **Step 2: Rodar e ver falhar** — FAIL.
- [ ] **Step 3: Implementar** — `DatePicker` (`@mui/x-date-pickers`, dayjs, como `LancamentosPage`), valor derivado exibido "R$/L" ao lado (`valor/litros`), tabela com cabeçalho semântico + `Pagination`; estados de loading (`Skeleton`), vazio e erro (`Alert` com "Tentar novamente"). Mobile-first (cartões em `xs`). Depois de salvar/excluir: recarregar a lista e chamar `onChanged`.
- [ ] **Step 4: Rodar e ver passar** — `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 5: Commit** — `feat(moto): adiciona aba de abastecimentos`.

---

### Task 15: Front — aba **Óleo**

**Files:**
- Create: `workbox-app/src/pages/moto/OleoTab.tsx`
- Modify: `workbox-app/src/pages/Moto.tsx`
- Test: `workbox-app/src/test/moto/OleoTab.test.tsx`

**Interfaces:** Consumes `getOilStatus`, `listOilChanges`, `createOilChange`, `updateOilChange`, `deleteOilChange`, `listOilIntervals`. Produces `OleoTab` (props: `{ motorcycle: IMotorcycle; active: boolean; refreshKey: number; onChanged: () => void }`).

- [ ] **Step 1: Testes que falham** — (a) card "Próxima troca" com km restantes, data limite, dias restantes e `LinearProgress` (`aria-valuenow` coerente com o consumido do intervalo) para `OK`; (b) `PERTO` mostra `Alert severity="warning"` "Troca próxima"; `VENCIDA` mostra `Alert severity="error"` "Troca vencida" e valores negativos formatados como "vencida há 100 km" / "há 1 dia"; (c) `lastChange: null` → "Nenhuma troca registrada" e botão "Registrar primeira troca"; (d) ao escolher o tipo no formulário, `intervalKm`/`intervalMonths` são **pré-preenchidos** com os padrões de `listOilIntervals` (SYNTHETIC → 6000/12) e continuam editáveis; (e) validações: intervalo 0 → erro; (f) envio válido chama `createOilChange` com `{ date, odometerKm, oilType: 'SEMI_SYNTHETIC', intervalKm: 4000, intervalMonths: 6, ... }`; (g) histórico em tabela, mais recente primeiro; (h) mostra "limitado por: km" / "tempo" (`limitedBy`).
- [ ] **Step 2: Rodar e ver falhar** — FAIL.
- [ ] **Step 3: Implementar** — cores só por tokens do tema (`success`/`warning`/`error`) **sempre acompanhadas de texto/ícone** (não depender só de cor), diálogo de troca com `react-hook-form`+`yup`, recarrega quando `refreshKey` muda (abastecimento novo altera o hodômetro atual).
- [ ] **Step 4: Rodar e ver passar** — `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 5: Commit** — `feat(moto): adiciona aba de troca de óleo`.

---

### Task 16: Front — aba **Resumo** (cards e gráficos)

**Files:**
- Create: `workbox-app/src/pages/moto/ResumoTab.tsx`
- Modify: `workbox-app/src/pages/Moto.tsx` (aba padrão)
- Test: `workbox-app/src/test/moto/ResumoTab.test.tsx`

**Interfaces:** Consumes `getStats`, `getMonthlyStats`, `getYearlyStats`, `getOilStatus`, `recharts`. Produces `ResumoTab` (props: `{ motorcycle: IMotorcycle; active: boolean; refreshKey: number }`).

- [ ] **Step 1: Testes que falham** — (a) cards: "Consumo médio" (`37,50 km/l`), "Km rodados no mês", "Gasto no mês", "Gasto no ano", "Custo por km", "Preço médio/L", "Óleo" (status + km restantes); (b) selo "baixa confiança" com tooltip/`aria-label` "Poucos abastecimentos no período: a média pode variar" quando `lowConfidence`; (c) seletor de ano troca a chamada de `getMonthlyStats(…, 2025)`; (d) valores nulos mostram "—" (nunca "NaN"/"null"); (e) variação do gasto vs. mês anterior com seta e texto ("−13,64% vs. mês anterior"); (f) com a série toda zerada → estado vazio "Sem abastecimentos neste ano"; (g) cada gráfico tem título e uma **tabela alternativa** visualmente oculta (`<table>` com `sr-only`) para leitores de tela; (h) `recharts` é mockado em jsdom (`ResponsiveContainer` sem tamanho) — seguir como o teste de `forza` faz (`grep -rn "ResponsiveContainer" workbox-app/src/test`).
- [ ] **Step 2: Rodar e ver falhar** — FAIL.
- [ ] **Step 3: Implementar** — 3 gráficos de barras/linha em `recharts` com cores do tema MUI (`theme.palette.*`, nunca hex fixo): km/l por mês (linha, pontos vazios para `null`), gasto mensal (barras), km por mês (barras); visão anual (barras por ano) abaixo, só se houver > 1 ano; eixos com `tickFormatter` pt-BR; `<Skeleton>` enquanto carrega; `Alert` + "Tentar novamente" em erro. Carregamento por `useLazyTabData(active, key = \`${motorcycle.id}:${year}:${refreshKey}\`, ...)`.
- [ ] **Step 4: Rodar e ver passar** — `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 5: Commit** — `feat(moto): adiciona aba de resumo com métricas e gráficos`.

---

### Task 17: Validação ponta a ponta, E2E, documentação raiz e ponteiros

**Files:**
- Modify: `CLAUDE.md` (raiz), `README.md` (raiz), `workbox-app/CLAUDE.md`, `workbox-app/README.md`
- Test: fluxo E2E em `workbox-app/src/test/browser-e2e.mjs` (seguir o padrão dos cenários existentes) + validação visual manual
- Modify (ponteiros): `workbox-api`, `workbox-app` na raiz

- [ ] **Step 1: Subir o stack** — `scripts/up-all.sh --build`; conferir `docker ps` (moto-service `healthy`) e que o Postgres **não** foi tocado.
- [ ] **Step 2: Conceder o módulo** — na tela Admin (ou, pelo usuário de QA admin da raiz `README`/`workbox-api/README.md#contas-de-teste-qa`) garantir que a conta de teste enxerga o card Moto (ADMIN recebe todos os módulos).
- [ ] **Step 3: E2E** — cenário: login QA → card **Moto** → cadastrar moto (hodômetro inicial 1.000) → registrar 3 abastecimentos (incluindo um parcial) → registrar troca de óleo → aba Resumo mostra km/l, gasto e status do óleo; hodômetro regressivo mostra o erro da API. `npm run test:e2e` (usa o compose efêmero, não o Postgres de dev) — se o `docker-compose.e2e.yml` listar serviços, incluir o `moto-service` e a seed.
- [ ] **Step 4: Validação visual (browser)** — abrir `http://localhost:7053`, percorrer as 4 abas em viewport desktop **e** mobile (390 px), conferir console sem erros, foco por teclado nas abas/diálogos, contraste dos selos e do status do óleo, tema escuro (se o app tiver). Relatar em 1 linha o que foi validado.
- [ ] **Step 5: Documentação** — `CLAUDE.md` raiz: (i) em "Exceção vigente" acrescentar `moto-service` (autorização de 2026-10-06, por serviço); (ii) linha na tabela "Mapa de CLAUDE.md" (`moto-service/` · 7059 · "Controle de moto: abastecimentos, consumo, km, óleo — resource server, Postgres schema `moto`" · estado do repo: "ainda sem remote no GitLab/`.gitmodules`" até o desenvolvedor criar o projeto); (iii) linha `moto-service` na tabela de portas (7059 → 8085) e na lista de módulos (`moto-service` → `MOTO`); (iv) estado dos contratos: `moto-service` tem `openapi.yaml`; (v) CI: `moto-service` tem `test` → `contract-drift-check` → `build`, sem Sonar. `README.md` raiz: serviço, porta e `initdb/04`. `workbox-app/CLAUDE.md`/`README.md`: módulo Moto (rotas, abas, proxy `motorcycles|oil-intervals`, `MOTO_SERVICE_UPSTREAM`/`VITE_MOTO_API_URL`, hub passa a ter 4 cards ativos).
- [ ] **Step 6: Commits em ordem (submódulo primeiro, depois ponteiro)** — (1) `workbox-app`: `docs(moto): documenta o módulo Moto` (+ E2E se alterado); (2) raiz: `docs: registra o moto-service no CLAUDE.md e no README`; (3) raiz: `chore: atualiza ponteiros dos submódulos (módulo MOTO e telas de moto)` com `git add workbox-api workbox-app` **somente** — **não** adicionar `backup-service` nem `.idea/vcs.xml` (edições alheias). `moto-service` entra como submódulo depois que o desenvolvedor criar o repo no GitLab e o `git push` de `main` + `develop` for confirmado.
- [ ] **Step 7: Relatório final** — `git diff --stat` por repositório, resultado real de `./gradlew check`, `npm test`/`lint`/`build` e do E2E; pendências para o desenvolvedor: criar o projeto GitLab `moto-service` (main + develop), `git submodule add`, **`git push` (exige confirmação)**, rodar `initdb/04-create-moto-role.sql` em bancos de produção, gerar o client secret de produção e atribuir a role `MOTO` aos usuários não-admin.

---

## Self-review

- **Cobertura da spec:** modelo (T3–T8) · consumo parcial/ponderado/estimado/baixa confiança (T6) · próxima troca por km e tempo (T8) · API de motos/abastecimentos/óleo/km avulso/métricas (T4–T9) · IDOR por dono → 404 (T4, ITs de T5/T7/T8/T9) · módulo `MOTO` e trava (T1, T3, T4) · RFC 9457 (T3) · OpenAPI versionado + CI de drift (T10) · front com 4 abas, gráficos, selos, proxy nos dois lugares, card no Dashboard (T12–T16) · infra, initdb, compose, env, submódulo (T2, T11, T17) · docs/CLAUDE.md (T10, T17) · "Timeline fora do escopo" (nenhuma tarefa — correto).
- **Placeholders:** os únicos valores a preencher em tempo de execução são o UUID/hash do seed (T1 Step 4, com instrução explícita de gerar antes de salvar) e a decisão `year`→`modelYear` condicionada ao teste (T4 Step 4). Cópias "literais do budget" (T3) apontam arquivo exato lido na exploração.
- **Consistência de tipos:** `MotorcycleService.exigirDoDono`, `OdometerService.validarNovo(UUID, String, LocalDate, int, UUID)`, `RefuelingService.entradasOrdenadas`, `FuelEntry`/`Segment`/`ConsumptionWindow`, `OilStatusCalculator.calcular(OilChange, int, LocalDate)` e `StatsDTO` usados com a mesma assinatura em todas as tarefas; nomes de rotas idênticos entre backend (T4–T9), proxy (T12) e `motoApi.ts` (T12).
- **Ponto de atenção conhecido:** `OdometerService.pontos` nasce só com leituras (T5) e ganha abastecimentos (T7) e trocas (T8) — cada extensão traz o seu caso no `OdometerServiceIT`.
