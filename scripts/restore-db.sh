#!/bin/sh
# Restaura um backup gerado por backup-db.sh (--format=custom, pg_restore).
#
# Uso manual (a partir da raiz do monorepo) - caminho é dentro do container, onde
# ./backups do host está montado em /backups:
#   docker compose --profile backup run --rm restore /backups/workbox_20260913_120000.dump
#
# ATENÇÃO: --clean --if-exists dropa e recria os objetos existentes que colidirem com
# o backup - sobrescreve o banco atual, não faz merge. Rodar contra o Postgres errado
# (ex.: produção sem querer) destrói dados atuais.
set -eu

: "${PGHOST:=postgres}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=postgres}"
: "${PGDATABASE:=workbox}"

export PGPASSWORD

if [ -z "${1:-}" ]; then
  echo "Uso: restore-db.sh <caminho-do-arquivo.dump>" >&2
  exit 1
fi

file="$1"
if [ ! -f "$file" ]; then
  echo "Arquivo não encontrado: $file" >&2
  exit 1
fi

echo "Restaurando '${PGDATABASE}' (${PGHOST}:${PGPORT}) a partir de ${file}..."
echo "Isso sobrescreve objetos existentes com o mesmo nome (--clean --if-exists)."
# Sem --no-owner: cada schema é dono do seu próprio role (workbox_service/
# budget_service, ver initdb/02-create-schemas.sql) - restaurando como superusuário
# postgres, --no-owner reatribuiria os objetos recriados pra "postgres" em vez do
# owner original, e os roles de cada serviço perderiam acesso ("permission denied for
# schema") até alguém rodar GRANT/ALTER OWNER manualmente. Descoberto testando o
# restore de ponta a ponta antes de documentar isso como pronto pra uso.
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  --clean --if-exists "$file"

echo "Restore concluído."
