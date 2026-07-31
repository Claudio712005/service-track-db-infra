# DB-ADR-004: Orçamento de conexões como configuração versionada

## Data
26/07/2026

## Status
**Aceita**

> A classe de instância que sustenta cada teto está em
> [`DB-ADR-006`](DB-ADR-006-dimensionamento-do-rds-por-ambiente.md). Os dois documentos são
> inseparáveis: o teto de conexões decide a classe, e a classe limita o teto.

## Contexto

Nenhum dos consumidores tinha pool configurado. Aplicação e função de autenticação usavam o
padrão do Agroal, `max-size = 20`.

A conta que ninguém tinha feito:

| Consumidor | Pools | Por instância | Instâncias | Total |
|---|---|---|---|---|
| Aplicação | principal + migração | 20 + 20 = 40 | até 10 réplicas (HPA) | **400** |
| Autenticação | um | 20 | escala sem teto | **sem limite** |

`db.t3.micro` suporta cerca de 112 conexões; `db.t3.medium`, cerca de 450.

Ou seja: **quatro pods já esgotavam o banco em homologação**. O sintoma não é lentidão — é a
aplicação inteira parando de conectar, exatamente no pico que o HPA existe para atender.

Agrava: a função roda em Lambda, que atende **uma requisição por container de cada vez**. Um
pool de 20 ali é desperdício puro, e cada container quente segura conexões sem usá-las.

## Decisão

**O teto do banco e o pool de cada consumidor são declarados juntos, neste repositório, e o
Terraform recusa o `plan` quando a soma estoura.**

1. `max_connections` deixa de ser derivado da classe da instância e passa a ser explícito num
   parameter group.
2. O tamanho de pool de cada consumidor é variável de ambiente aqui, não configuração solta em
   cada repositório.
3. Os valores são publicados no SSM; os consumidores os aplicam.
4. Uma `precondition` calcula `réplicas × (pool + pool de migração) + concorrência × pool da
   função + folga` e **falha o plan** se passar do teto.

| Ambiente | Teto | Aplicação | Função | Folga | Total |
|---|---|---|---|---|---|
| hml | 100 | 10 × (4 + 2) = 60 | 5 × 2 = 10 | 10 | 80 |
| prd | 300 | 10 × (15 + 2) = 170 | 20 × 2 = 40 | 10 | 220 |

Complementos no parameter group: `idle_in_transaction_session_timeout` encerra transações
ociosas que seguram conexão, e `log_min_duration_statement` expõe consultas lentas.

## Consequências

### Positivas
- O estouro deixa de ser possível em produção: falha no `plan`, com mensagem dizendo o que
  reduzir.
- O orçamento fica auditável num arquivo, não espalhado por três repositórios.
- Aumentar o teto do HPA passa a exigir revisar o orçamento — que é o comportamento correto.
- `check-conexoes.sh` compara o uso real com o declarado.

### Negativas
- Mudar pool exige apply neste repositório e redeploy nos consumidores. Deliberado: o
  acoplamento é real e agora está explícito.
- Os números de concorrência da função e de réplicas são estimativas; se a realidade passar
  delas, o orçamento fica otimista. Mitigado por `check-conexoes.sh`.
- `max_connections` explícito exige reboot para mudar (`apply_method = "pending-reboot"`).

### Impacto em ambiente efêmero
Nenhum: são parâmetros, recriados a cada apply.

## Alternativas consideradas

**Pooler externo (PgBouncer / RDS Proxy)** — resolveria de forma mais elegante, multiplexando
conexões. Rejeitada por ora: RDS Proxy tem custo por hora relevante na conta educacional, e
PgBouncer no cluster adiciona um componente para operar. Reavaliar se a concorrência crescer.

**Deixar o padrão do Agroal e aumentar a instância** — Rejeitada: paga-se com dinheiro um
problema de configuração, e o teto voltaria a ser atingido no próximo aumento de réplicas.
