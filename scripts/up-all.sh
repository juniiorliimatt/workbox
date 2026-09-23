#!/usr/bin/env bash
# Rebuilda (quando necessário) e sobe todos os containers do stack workbox
# (postgres, redis, mongo, workbox-api, budget-service, notes-service,
# workbox-app). Serviços dos profiles "backup"/"restore" ficam de fora, como
# sempre (não sobem com "docker compose up" normal).
#
# Uso (de qualquer diretório):
#   scripts/up-all.sh              # rebuilda as imagens antes de subir
#   scripts/up-all.sh --no-build   # só sobe, sem rebuildar
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "Rebuildando imagens..."
  docker compose build
fi

echo "Subindo containers..."
docker compose up -d

echo
docker compose ps
