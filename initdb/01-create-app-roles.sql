-- Um role por microserviço, restrito ao seu próprio schema (nunca o superusuário
-- postgres/postgres do container). Senha local de estudo — não use isso em produção.
CREATE ROLE workbox_service WITH LOGIN PASSWORD 'workbox_service';
CREATE ROLE budget_service WITH LOGIN PASSWORD 'budget_service';

GRANT CONNECT ON DATABASE workbox TO workbox_service, budget_service;
