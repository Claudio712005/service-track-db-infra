#!/usr/bin/env bash

set -euo pipefail

AMBIENTE="${1:-}"
if [ -z "$AMBIENTE" ]; then
  echo "uso: $0 <hml|prd>" >&2
  exit 1
fi

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIXO="/servicetrack/${AMBIENTE}/db"

ler() { aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text; }

HOST="$(ler "$PREFIXO/endpoint")"
PORTA="$(ler "$PREFIXO/port")"
BANCO="$(ler "$PREFIXO/name")"
MASTER="$(ler "$PREFIXO/username")"
export PGPASSWORD="$(ler "$PREFIXO/password")"

FLYWAY_DB_USER="$(ler "$PREFIXO/roles/flyway/usuario")"
FLYWAY_DB_PASSWORD="$(ler "$PREFIXO/roles/flyway/senha")"
APP_DB_USER="$(ler "$PREFIXO/roles/app/usuario")"
APP_DB_PASSWORD="$(ler "$PREFIXO/roles/app/senha")"
READONLY_DB_USER="$(ler "$PREFIXO/roles/readonly/usuario")"
READONLY_DB_PASSWORD="$(ler "$PREFIXO/roles/readonly/senha")"

TETO="$(ler "$PREFIXO/max-connections")"

psql_master() {
  psql -v ON_ERROR_STOP=1 \
    --host "$HOST" --port "$PORTA" --username "$MASTER" --dbname "$BANCO" "$@"
}

echo ">> extensoes em ${AMBIENTE} (${HOST})"
psql_master -f "$RAIZ/scripts/init-extensoes.sql"

echo ">> roles em ${AMBIENTE}"
psql_master \
  -v flyway_user="$FLYWAY_DB_USER"     -v flyway_pass="$FLYWAY_DB_PASSWORD" \
  -v app_user="$APP_DB_USER"           -v app_pass="$APP_DB_PASSWORD" \
  -v readonly_user="$READONLY_DB_USER" -v readonly_pass="$READONLY_DB_PASSWORD" \
  -f "$RAIZ/scripts/init-roles.sql"

echo ">> verificando o estado esperado"
psql_master \
  -v flyway_user="$FLYWAY_DB_USER" \
  -v app_user="$APP_DB_USER" \
  -v readonly_user="$READONLY_DB_USER" \
  -v teto_esperado="$TETO" \
  -f "$RAIZ/scripts/verificar-banco.sql"
