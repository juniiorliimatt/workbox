-- Extensões são objetos de banco (não de schema) — só o superusuário pode criá-las.
-- Instaladas uma vez aqui pra que os roles restritos de cada serviço (sem CREATE no
-- banco) não precisem de privilégio pra isso; os changesets de Liquibase que fazem
-- CREATE EXTENSION IF NOT EXISTS viram no-op.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
