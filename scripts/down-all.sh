#!/usr/bin/env bash
# Para (sem remover) TODOS os containers do stack workbox, incluindo o
# postgres:18 (workbox-postgres), redis e mongo — diferente do dia a dia
# normal, em que banco nunca é derrubado junto dos serviços de aplicação.
# Uso explícito e pontual (ex.: desligar a máquina, liberar recursos), não
# automático. Containers ficam parados, não removidos — scripts/up-all.sh
# sem flags apenas os reinicia, sem precisar rebuildar. Volumes (dados do
# postgres/mongo) NÃO são removidos.
#
# Uso (de qualquer diretório):
#   scripts/down-all.sh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Parando todos os containers do stack workbox (incluindo postgres:18)..."
docker compose stop

echo
docker compose ps -a
