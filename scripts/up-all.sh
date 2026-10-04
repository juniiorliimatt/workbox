#!/usr/bin/env bash
# Sobe todos os containers do stack workbox (postgres, redis, mongo,
# workbox-api, budget-service, notes-service, forza-telemetry-service, backup-service, workbox-app). Serviços dos
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

# IP da máquina na LAN pra tela "Ao vivo" do front (onde apontar o Data Out do Forza):
# respeita FORZA_HOST_IP do ambiente ou do .env; senão usa a origem da rota padrão.
if [[ -z "${FORZA_HOST_IP:-}" ]] && ! grep -qE '^FORZA_HOST_IP=.+' .env 2>/dev/null; then
  DETECTED_IP="$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1 || true)"
  if [[ -n "$DETECTED_IP" ]]; then
    export FORZA_HOST_IP="$DETECTED_IP"
    echo "FORZA_HOST_IP detectado: $FORZA_HOST_IP"
  fi
fi

# Caminho ABSOLUTO de ./backups no host, exibido na tela de backup (o container só enxerga /backups).
if [[ -z "${BACKUP_HOST_DIR:-}" ]] && ! grep -qE '^BACKUP_HOST_DIR=.+' .env 2>/dev/null; then
  export BACKUP_HOST_DIR="$PROJECT_ROOT/backups"
fi

echo "Subindo containers..."

docker compose up -d

echo
docker compose ps
