-- Role do backup-service: só LEITURA do banco inteiro (pg_read_all_data), sem schema próprio e sem
-- CREATE. É o que o pg_dump precisa pra exportar todos os schemas sem usar o superusuário postgres.
-- Senha local de estudo — em produção troque (ALTER ROLE backup_service PASSWORD '...') e a mesma
-- senha em PGPASSWORD do serviço. Num banco que já existe, o initdb/ não roda: execute este arquivo
-- à mão (psql -U postgres -d workbox -f initdb/03-create-backup-role.sql) — é idempotente.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'backup_service') THEN
    CREATE ROLE backup_service WITH LOGIN PASSWORD 'backup_service';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE workbox TO backup_service;
GRANT pg_read_all_data TO backup_service;
