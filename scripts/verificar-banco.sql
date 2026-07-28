\set ON_ERROR_STOP on

SELECT 'roles' AS verificacao,
       CASE WHEN count(*) = 3 THEN 'ok' ELSE 'FALHOU: esperadas 3, encontradas ' || count(*) END AS resultado
  FROM pg_roles
 WHERE rolname IN (:'flyway_user', :'app_user', :'readonly_user');

SELECT 'create revogado de PUBLIC' AS verificacao,
       CASE WHEN has_schema_privilege('public', 'public', 'CREATE')
            THEN 'FALHOU: PUBLIC ainda pode criar objetos'
            ELSE 'ok' END AS resultado;

SELECT 'app_user nao altera estrutura' AS verificacao,
       CASE WHEN has_schema_privilege(:'app_user', 'public', 'CREATE')
            THEN 'FALHOU: app_user pode criar objetos'
            ELSE 'ok' END AS resultado;

SELECT 'flyway_user altera estrutura' AS verificacao,
       CASE WHEN has_schema_privilege(:'flyway_user', 'public', 'CREATE')
            THEN 'ok'
            ELSE 'FALHOU: flyway_user nao pode criar objetos' END AS resultado;

SELECT 'readonly somente leitura' AS verificacao,
       CASE WHEN (SELECT rolconfig::text FROM pg_roles WHERE rolname = :'readonly_user')
                 LIKE '%default_transaction_read_only=on%'
            THEN 'ok'
            ELSE 'FALHOU: readonly_user pode escrever' END AS resultado;

SELECT 'pg_stat_statements' AS verificacao,
       CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
            THEN 'ok'
            ELSE 'FALHOU: extensao ausente' END AS resultado;

SELECT 'teto de conexoes' AS verificacao,
       CASE WHEN current_setting('max_connections')::int >= :teto_esperado
            THEN 'ok (' || current_setting('max_connections') || ')'
            ELSE 'FALHOU: ' || current_setting('max_connections') || ' abaixo de ' || :teto_esperado
       END AS resultado;
