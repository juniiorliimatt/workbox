-- Um role por microserviço, restrito ao seu próprio schema (nunca o superusuário
-- postgres/postgres do container). Senha local de estudo — não use isso em produção.
CREATE ROLE workbox_api WITH LOGIN PASSWORD 'workbox_api';
CREATE ROLE budget_service WITH LOGIN PASSWORD 'budget_service';

GRANT CONNECT ON DATABASE workbox TO workbox_api, budget_service;
