#!/usr/bin/env bash
# Compara o uso real de conexoes com o orcamento declarado no terraform.
# Somente leitura. Requer psql e AWS CLI autenticada.

set -euo pipefail

AMBIENTE="${1:-}"
if [ -z "$AMBIENTE" ]; then
  echo "uso: $0 <hml|prd>" >&2
  exit 1
fi

PREFIXO="/servicetrack/${AMBIENTE}/db"
ler() { aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text; }

HOST="$(ler "$PREFIXO/endpoint")"
PORTA="$(ler "$PREFIXO/port")"
BANCO="$(ler "$PREFIXO/name")"
MASTER="$(ler "$PREFIXO/username")"
TETO="$(ler "$PREFIXO/max-connections")"
POOL_API="$(ler "$PREFIXO/pool/api-max-size")"
POOL_MIG="$(ler "$PREFIXO/pool/api-migration-max-size")"
POOL_LMB="$(ler "$PREFIXO/pool/lambda-max-size")"
export PGPASSWORD="$(ler "$PREFIXO/password")"

echo "ambiente ${AMBIENTE} - teto de conexoes: ${TETO}"
echo "orcamento por consumidor: api=${POOL_API} migracao=${POOL_MIG} lambda=${POOL_LMB}"
echo

psql -qAt --host "$HOST" --port "$PORTA" --username "$MASTER" --dbname "$BANCO" <<'SQL'
SELECT 'em uso agora: ' || count(*) || ' de ' || current_setting('max_connections') FROM pg_stat_activity;
SELECT '  ' || coalesce(usename,'(sistema)') || ': ' || count(*) || ' (' || count(*) FILTER (WHERE state = 'idle in transaction') || ' ociosas em transacao)'
  FROM pg_stat_activity GROUP BY usename ORDER BY count(*) DESC;
SQL
