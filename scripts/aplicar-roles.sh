#!/usr/bin/env bash
# Aplica as roles de runtime no banco do ambiente informado.
# Le endpoint e credenciais do master a partir do SSM publicado pelo terraform.
# Idempotente. Requer psql e AWS CLI autenticada.

set -euo pipefail

AMBIENTE="${1:-}"
if [ -z "$AMBIENTE" ]; then
  echo "uso: $0 <hml|prd>" >&2
  exit 1
fi

: "${FLYWAY_DB_USER:?defina FLYWAY_DB_USER}"
: "${FLYWAY_DB_PASSWORD:?defina FLYWAY_DB_PASSWORD}"
: "${APP_DB_USER:?defina APP_DB_USER}"
: "${APP_DB_PASSWORD:?defina APP_DB_PASSWORD}"
: "${READONLY_DB_USER:=readonly_user}"
: "${READONLY_DB_PASSWORD:?defina READONLY_DB_PASSWORD}"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIXO="/servicetrack/${AMBIENTE}/db"

ler() { aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text; }

HOST="$(ler "$PREFIXO/endpoint")"
PORTA="$(ler "$PREFIXO/port")"
BANCO="$(ler "$PREFIXO/name")"
MASTER="$(ler "$PREFIXO/username")"
export PGPASSWORD="$(ler "$PREFIXO/password")"

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
