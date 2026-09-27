#!/usr/bin/env bash
# Sobe todos os containers do stack workbox (postgres, redis, mongo,
# workbox-api, budget-service, notes-service, workbox-app). Serviços dos
# profiles "backup"/"restore" ficam de fora, como sempre (não sobem com
# "docker compose up" normal). Complementa scripts/down-all.sh: down para,
# up sobe de volta os mesmos containers, sem rebuild.
#
# Uso (de qualquer diretório):
#   scripts/up-all.sh           # só sobe (recria containers parados via down-all.sh)
#   scripts/up-all.sh --build   # rebuilda as imagens antes de subir
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "${1:-}" == "--build" ]]; then
  echo "Rebuildando imagens..."
  docker compose build
fi

echo "Subindo containers..."
docker compose up -d

echo
docker compose ps
