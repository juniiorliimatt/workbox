#!/bin/sh
# Backup completo do banco (todos os schemas) via pg_dump --format=custom.
# Feito pra rodar dentro do container do serviço "backup" do docker-compose.yml
# (imagem postgres:18, mesma versão do servidor real — pg_dump/pg_restore de versões
# diferentes entre si dão warning e podem falhar em restore).
#
# Uso manual (a partir da raiz do monorepo):
#   docker compose --profile backup run --rm backup
#
# Gera um arquivo em /backups (montado em ./backups no host) no formato
# "<PGDATABASE>_<timestamp>.dump" - formato --custom permite restore seletivo
# (só uma tabela/schema) e já vem comprimido, ao contrário de um dump --plain (.sql).
set -eu

: "${PGHOST:=postgres}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=postgres}"
: "${PGDATABASE:=workbox}"
: "${BACKUP_DIR:=/backups}"

export PGPASSWORD

mkdir -p "$BACKUP_DIR"
# Diretório nasce dono de root (bind mount criado pelo Docker na primeira execução) -
# sem isso, mesmo um arquivo world-writable não pode ser apagado pelo usuário comum:
# unlink exige permissão de escrita no diretório pai, não só no arquivo.
chmod 777 "$BACKUP_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)
filepath="${BACKUP_DIR}/${PGDATABASE}_${timestamp}.dump"

echo "Fazendo backup de '${PGDATABASE}' (${PGHOST}:${PGPORT}), todos os schemas..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  --format=custom --compress=9 --file="$filepath"

# O container roda como root (entrypoint sobrescrito, não usa o gosu da imagem oficial),
# então o arquivo nasceria dono de root em ./backups no host - chmod pra qualquer
# usuário conseguir mexer nele sem sudo depois.
chmod 666 "$filepath"

size=$(du -h "$filepath" | cut -f1)
echo "Backup concluído: ${filepath} (${size})"
echo "Pra restaurar: docker compose --profile backup run --rm restore ${filepath}"
