CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT 'extensao ' || extname || ' versao ' || extversion AS instalada
  FROM pg_extension
 WHERE extname = 'pg_stat_statements';
