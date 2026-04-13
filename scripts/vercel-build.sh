#!/usr/bin/env bash
# Build na Vercel: gera .env (asset do pubspec) + Flutter stable + flutter build web
# Defina na Vercel (Settings → Environment Variables): APP_LOGIN, APP_PASSWORD,
# ID_CLIENTE_GOOGLE ou GOOGLE_OAUTH_CLIENT_ID, etc. — os mesmos nomes do .env local.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# O repositório não inclui .env (gitignore); o Flutter exige o ficheiro para empacotar assets.
{
  printf 'APP_LOGIN=%s\n' "${APP_LOGIN:-}"
  printf 'APP_PASSWORD=%s\n' "${APP_PASSWORD:-}"
  printf 'GOOGLE_OAUTH_CLIENT_ID=%s\n' "${GOOGLE_OAUTH_CLIENT_ID:-}"
  printf 'ID_CLIENTE_GOOGLE=%s\n' "${ID_CLIENTE_GOOGLE:-}"
  printf 'CHAVE_SECRETA_GOOGLE=%s\n' "${CHAVE_SECRETA_GOOGLE:-}"
} > .env

echo ">>> .env criado na raiz do projeto (valores vindos das Environment Variables da Vercel)."

# SDK Flutter (Linux — igual ao tutorial DEV)
if [ -d flutter ]; then
  (cd flutter && git pull) || true
else
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="$ROOT/flutter/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release --no-tree-shake-icons

echo ">>> build/web pronto."
