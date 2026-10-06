-- Para um Postgres JÁ existente (initdb/ só roda em volume vazio). Rodar como superusuário:
--   docker exec -i workbox-postgres psql -U postgres -d workbox < initdb/04-create-moto-role.sql
-- Idempotente. Senha local de estudo — em produção, troque (ALTER ROLE moto_service PASSWORD '...').
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'moto_service') THEN
    CREATE ROLE moto_service WITH LOGIN PASSWORD 'moto_service';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE workbox TO moto_service;
CREATE SCHEMA IF NOT EXISTS moto AUTHORIZATION moto_service;
