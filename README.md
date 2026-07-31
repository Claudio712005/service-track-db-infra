# service-track-db-infra

Infraestrutura do banco de dados gerenciado do ServiceTrack: PostgreSQL no Amazon RDS,
provisionado com Terraform, com uma configuração por ambiente.

É um dos quatro repositórios do sistema. Os outros são
[service-track-api](https://github.com/Claudio712005/ServiceTrack-API) (aplicação),
[service-track-aws-iac](https://github.com/Claudio712005/service-track-aws-iac) (rede, Kubernetes
e borda) e [service-track-lambda](https://github.com/Claudio712005/service-track-lambda)
(autenticação serverless).

---

## Do que este repositório é dono

- Instância RDS PostgreSQL, subnet group, security group e parameter group.
- **Orçamento de conexões** do banco e o tamanho de pool de cada consumidor.
- Roles de runtime (`flyway_user`, `app_user`, `readonly_user`) e seus privilégios.
- Publicação de endpoint, credenciais e orçamento no SSM Parameter Store.

## Do que **não** é dono

- **Schema e migrations.** Pertencem à aplicação, em `db/migration`, aplicadas pelo Flyway na
  subida. Ver `DB-ADR-002`.
- VPC, subnets e cluster — pertencem ao repositório de infraestrutura.
- Manifestos Kubernetes, incluindo o Job que provisiona as roles dentro do cluster.

---

## Arquitetura

```
service-track-aws-iac                service-track-db-infra
  iac/network/<env>                    iac/environments/<env>
    VPC, subnets  ──── remote state ────►  RDS + SG + parameter group
                                              │
                                              │ publica
                                              ▼
                                       SSM /servicetrack/<env>/db/*
                                              │
  iac/environments/<env>  ◄──── lê ────────────┘
    EKS, Lambda, gateway
    + regras de ingress no SG do banco
```

O security group do banco **nasce sem regras de entrada**. Quem tem os security groups dos
consumidores (nodes do EKS, Lambda) é o repositório de infraestrutura, e é lá que as regras
são criadas apontando para o SG daqui. Sem essa inversão os dois states dependeriam um do
outro e nenhum dos dois poderia ser aplicado primeiro (`DB-ADR-003`).

---

## Ordem de aplicação

Os ambientes são efêmeros: destruídos ao fim de cada teste ou apresentação e recriados do
zero. A ordem abaixo vale para **toda** recriação.

| # | Onde | O quê |
|---|---|---|
| 1 | `service-track-aws-iac` → esteira **Network** | VPC e subnets do ambiente |
| 2 | **este repositório** → esteira **Terraform** | RDS, parameter group, SSM |
| 3 | `service-track-aws-iac` → esteira **Terraform** | EKS, Lambda, gateway, ingress no SG do banco |
| 4 | este repositório → `scripts/aplicar-roles.sh` | extensões, roles e verificação do estado esperado |

Pular a fase 1 faz o plan daqui falhar com erro explícito apontando o que aplicar antes.

Destruir é a ordem inversa: stack → banco → rede.

---

## Configuração por ambiente

| | hml | prd |
|---|---|---|
| Classe | `db.t3.micro` | `db.t3.medium` |
| Storage | 20 GB (autoscaling até 50) | 50 GB (autoscaling até 200) |
| **Multi-AZ** | não | **sim** |
| Retenção de backup | 0 dias | 7 dias |
| `max_connections` | 100 | 300 |

Multi-AZ praticamente dobra o custo da instância. HML é o ambiente enxuto por decisão de
orçamento e o mais recriado, então roda em AZ única; PRD tem standby síncrono.

---

## Orçamento de conexões

Este é o ponto mais importante do repositório.

O PostgreSQL tem um teto de conexões simultâneas. Cada pod da aplicação abre **dois** pools
(o principal e o de migração do Flyway) e cada container da Lambda abre mais um. Sob scale-out
do HPA, pools mal dimensionados esgotam o banco justamente no pico que o autoscaling existe
para atender — e o sintoma é a aplicação inteira parando, não uma degradação suave.

O orçamento é declarado num lugar só, `iac/environments/<env>/main.tf`, e publicado no SSM
para que os consumidores o apliquem:

| Ambiente | Teto | Aplicação (10 réplicas) | Lambda | Folga | Total |
|---|---|---|---|---|---|
| hml | 100 | 10 × (4 + 2) = 60 | 5 × 2 = 10 | 10 | **80** |
| prd | 300 | 10 × (15 + 2) = 170 | 20 × 2 = 40 | 10 | **220** |

O módulo tem uma `precondition`: **se a soma passar do teto, o `plan` falha**. O estouro não
chega em produção.

> A Lambda atende uma requisição por container de cada vez. Pool acima de 2 ali é desperdício
> e aumenta a chance de esgotar o banco sob concorrência.

Conferir o uso real contra o orçamento:

```bash
scripts/check-conexoes.sh hml
```

---

## Parâmetros publicados no SSM

Sob `/servicetrack/<env>/db/`:

| Parâmetro | Tipo | Consumidor |
|---|---|---|
| `endpoint`, `port`, `name` | String | infraestrutura (Lambda, secrets da app) |
| `username`, `password` | String, **SecureString** | infraestrutura, bootstrap de roles |
| `jdbc-url` | String | aplicação |
| `security-group-id` | String | infraestrutura, para criar o ingress |
| `max-connections` | String | diagnóstico |
| `pool/api-max-size`, `pool/api-migration-max-size`, `pool/lambda-max-size` | String | infraestrutura, para configurar os pools |
| `roles/<role>/usuario` | String | bootstrap de roles, secrets do Kubernetes |
| `roles/<role>/senha` | **SecureString** | bootstrap de roles, secrets do Kubernetes |

A URL, o endereço e a senha **mudam a cada recriação do ambiente**. Ler sempre do SSM ou dos
outputs, nunca de anotação.

---

## Roles de runtime

| Role | Para quê | Privilégios |
|---|---|---|
| `flyway_user` | aplicar migrations | `USAGE, CREATE` no schema `public` |
| `app_user` | runtime da aplicação | `SELECT, INSERT, UPDATE, DELETE`; **não altera estrutura** |
| `readonly_user` | diagnóstico e observabilidade | `SELECT`; `default_transaction_read_only = on` |

O usuário master só é usado para criar as roles. `CREATE` no schema `public` é revogado de
`PUBLIC`.

`scripts/init-roles.sql` é a fonte canônica. É idempotente e a esteira prova isso aplicando-o
duas vezes seguidas contra um PostgreSQL efêmero.

```bash
scripts/aplicar-roles.sh hml
```

Sem variáveis de ambiente: usuários e senhas são gerados no apply e lidos do SSM
(`DB-ADR-005`).

O script aplica extensões, roles e a verificação, nesta ordem.

---

## Scripts SQL

Tudo aqui é **infraestrutura de banco**, nunca DDL de tabela: o schema pertence às migrations
Flyway da aplicação (`DB-ADR-002`).

| Script | O que faz | Quando roda |
|---|---|---|
| `init-extensoes.sql` | `pg_stat_statements` para diagnóstico de consulta lenta | fase 4, antes das roles |
| `init-roles.sql` | cria `flyway_user`, `app_user`, `readonly_user` e seus privilégios; revoga `CREATE` de `PUBLIC` | fase 4 |
| `verificar-banco.sql` | confere que o estado esperado foi atingido; imprime `ok` ou `FALHOU` por item | fase 4, ao final |
| `diagnostico.sql` | conexões por usuário, consultas mais lentas, maiores tabelas, bloqueios em espera | sob demanda |

Todos são idempotentes. A esteira aplica extensões e roles **duas vezes seguidas** contra um
PostgreSQL efêmero e roda a verificação, porque eles executam a cada recriação de ambiente e
precisam ser seguros na segunda vez.

`pg_stat_statements` exige `shared_preload_libraries`, que é `pending-reboot` no RDS. Como
todo ambiente aqui nasce novo, isso é aplicado na criação e não custa reinicialização.

### O que deliberadamente não existe aqui

| | Por quê |
|---|---|
| DDL de tabelas, índices, seed | Pertence às migrations da aplicação (`DB-ADR-002`). Duplicar criaria duas verdades sobre o schema. |
| `CREATE DATABASE` | O RDS já cria o banco a partir de `db_name`. Um script seria código morto que nunca roda no fluxo real. |
| `uuid-ossp`, `pgcrypto` | Nenhuma é usada: `uuid` e `numeric` são tipos nativos e os identificadores são gerados na aplicação. |
| Schema dedicado no lugar de `public` | Melhoria real de isolamento, mas quebra `search_path`, Flyway e Hibernate. É mudança de arquitetura, não script — merece RFC própria. |

---

## Modelagem

[docs/modelagem/modelo-entidade-relacionamento.md](docs/modelagem/modelo-entidade-relacionamento.md)
— diagrama ER, cardinalidades, chaves e restrições do modelo relacional.

O documento **descreve** o schema; não o define. A fonte de verdade continua sendo as
migrations Flyway da aplicação (`DB-ADR-002`). Alterou migration, atualize o documento no
mesmo ciclo, senão ele vira ficção.

Ele também registra nove divergências conhecidas de modelagem — entre elas quatro relações sem
chave estrangeira e um `insumo_id` declarado como `varchar` contra um `uuid` do outro lado.
Nenhuma está corrigida: correção de schema é migration nova, e migrations são append-only.

---

## Pré-requisitos

- Terraform >= 1.10.0
- AWS CLI autenticada — as credenciais da conta educacional **expiram a cada laboratório**
- `psql` para os scripts operacionais
- Bucket S3 do backend já existente
- Rede do ambiente já aplicada (fase 1)

## Uso local

```bash
cd iac/environments/hml
terraform init
terraform plan
terraform apply

terraform output rds_endpoint
terraform output -json orcamento_de_conexoes
terraform output db_password
```

## Esteiras

| Esteira | Quando |
|---|---|
| **Terraform → validar** | automática, em push e PR que tocam `iac/` |
| **Terraform → sql** | automática — aplica `init-roles.sql` duas vezes num Postgres efêmero |
| **Terraform → plan/apply/destroy** | manual, por ambiente |

Antes de qualquer esteira, renovar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e
`AWS_SESSION_TOKEN` nos environments `hml` e `prd`.

## Decisões

| ADR | Assunto |
|---|---|
| [DB-ADR-001](docs/adr/DB-ADR-001-postgresql-gerenciado-no-rds.md) | PostgreSQL gerenciado no RDS |
| [DB-ADR-002](docs/adr/DB-ADR-002-flyway-dono-do-schema.md) | Flyway na aplicação é dono do schema |
| [DB-ADR-003](docs/adr/DB-ADR-003-fronteira-entre-rede-e-banco.md) | Fronteira entre rede e banco, e o ingress invertido |
| [DB-ADR-004](docs/adr/DB-ADR-004-orcamento-de-conexoes.md) | Orçamento de conexões como configuração versionada |
| [DB-ADR-005](docs/adr/DB-ADR-005-senhas-de-role-geradas-e-publicadas.md) | Senhas das roles geradas aqui e publicadas no SSM |
