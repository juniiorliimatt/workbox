#!/bin/sh
# Decifra um backup gerado pela tela com senha (.dump.enc -> .dump), pra usar no restore-db.sh.
# O arquivo é cifrado com openssl AES-256-CBC + PBKDF2 (600000 iterações): este script só roda o
# openssl na ordem inversa e PEDE A SENHA NO TERMINAL (nunca como argumento, que apareceria no
# histórico do shell e no ps).
#
# Uso (a partir da raiz do monorepo):
#   scripts/decrypt-backup.sh backups/workbox_20261004_101500.dump.enc
#   docker compose --profile backup run --rm restore /backups/workbox_20261004_101500.dump
#
# Senha errada = "bad decrypt" e nenhum arquivo é deixado. Não há como recuperar o backup sem a senha.
set -eu

if [ -z "${1:-}" ]; then
  echo "Uso: decrypt-backup.sh <arquivo.dump.enc>" >&2
  exit 1
fi

in="$1"
case "$in" in
  *.dump.enc) ;;
  *) echo "Esperava um arquivo .dump.enc, recebi: $in" >&2; exit 1 ;;
esac
if [ ! -f "$in" ]; then
  echo "Arquivo não encontrado: $in" >&2
  exit 1
fi

out="${in%.enc}"
if [ -e "$out" ]; then
  echo "Já existe $out - apague ou mova antes de decifrar." >&2
  exit 1
fi

if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$in" -out "$out"; then
  rm -f "$out"
  echo "Falha ao decifrar (senha errada ou arquivo corrompido)." >&2
  exit 1
fi

# O dump em claro contém hashes de senha e segredos de MFA: só você deve ler.
chmod 600 "$out"
echo "Decifrado: $out"
