-- Roles de runtime do ServiceTrack. Fonte canonica.
--
-- flyway_user  dono do schema, aplica as migrations
-- app_user     runtime da aplicacao, sem poder alterar estrutura
--
-- Executado com o usuario master do RDS. Idempotente: pode rodar a cada
-- recriacao de ambiente sem efeito colateral.

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'flyway_user', :'flyway_pass')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'flyway_user')
\gexec
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_pass')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec

GRANT :"flyway_user" TO CURRENT_USER;
GRANT :"app_user"    TO CURRENT_USER;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT USAGE, CREATE ON SCHEMA public TO :"flyway_user";
GRANT USAGE            ON SCHEMA public TO :"app_user";

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO :"app_user";
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO :"app_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"flyway_user" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"flyway_user" IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"app_user";
