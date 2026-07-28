\echo '== conexoes por usuario =='
SELECT coalesce(usename, '(sistema)') AS usuario,
       count(*)                                                   AS total,
       count(*) FILTER (WHERE state = 'active')                   AS ativas,
       count(*) FILTER (WHERE state = 'idle')                     AS ociosas,
       count(*) FILTER (WHERE state = 'idle in transaction')      AS ociosas_em_transacao
  FROM pg_stat_activity
 GROUP BY usename
 ORDER BY total DESC;

\echo '== teto e uso =='
SELECT current_setting('max_connections') AS teto,
       (SELECT count(*) FROM pg_stat_activity) AS em_uso;

\echo '== consultas mais lentas =='
SELECT round(mean_exec_time::numeric, 1) AS media_ms,
       calls                             AS chamadas,
       round(total_exec_time::numeric, 1) AS total_ms,
       left(query, 90)                   AS consulta
  FROM pg_stat_statements
 ORDER BY mean_exec_time DESC
 LIMIT 10;

\echo '== maiores tabelas =='
SELECT relname AS tabela,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamanho,
       n_live_tup AS linhas
  FROM pg_stat_user_tables
 ORDER BY pg_total_relation_size(relid) DESC
 LIMIT 10;

\echo '== bloqueios em espera =='
SELECT bloqueada.pid        AS pid_bloqueado,
       bloqueada.usename    AS usuario_bloqueado,
       left(bloqueada.query, 60) AS consulta_bloqueada,
       bloqueadora.pid      AS pid_bloqueador
  FROM pg_stat_activity bloqueada
  JOIN pg_stat_activity bloqueadora
    ON bloqueadora.pid = ANY(pg_blocking_pids(bloqueada.pid))
 WHERE cardinality(pg_blocking_pids(bloqueada.pid)) > 0;
