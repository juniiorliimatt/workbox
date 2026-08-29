-- Um schema por microserviço, banco único (workbox). AUTHORIZATION torna o role dono
-- do schema — full acesso dentro dele, nenhum acesso fora (Postgres não concede nada
-- entre schemas por padrão, não precisa de REVOKE explícito).
CREATE SCHEMA IF NOT EXISTS api AUTHORIZATION workbox_api;
CREATE SCHEMA IF NOT EXISTS api_liquibase AUTHORIZATION workbox_api;
CREATE SCHEMA IF NOT EXISTS budget AUTHORIZATION budget_service;
