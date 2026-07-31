# DB-ADR-006: Dimensionamento do RDS por ambiente

## Data

31/07/2026

## Status

- Aceita

Origem: [`DB-RFC-001`](../rfc/DB-RFC-001-dimensionamento-do-rds.md).
Complementa [`DB-ADR-001`](DB-ADR-001-postgresql-gerenciado-no-rds.md), que decide o RDS, e
[`DB-ADR-004`](DB-ADR-004-orcamento-de-conexoes.md), que decide o teto de conexões.

---

## Contexto

Os dois ambientes rodam o mesmo schema, as mesmas migrations e as mesmas roles. O que muda é a
instância:

| | HML | PRD |
|---|---|---|
| `db_instance_class` | `db.t3.micro` | `db.t3.medium` |
| `db_allocated_storage` | 20 GB | 50 GB |
| `db_max_allocated_storage` | 50 GB | 200 GB |
| `db_multi_az` | `false` | `true` |
| `db_backup_retention_days` | 0 | 7 |
| `db_max_connections` | 100 | 300 |

Este ADR registra por que cada número é esse, e não um arredondamento.

As restrições que decidem: conta AWS Academy com crédito finito, ambiente destruído após cada
teste ou apresentação, e o orçamento de conexões que já amarra o teto de réplicas da aplicação.

---

## Decisão

### 1. Classe da instância

**HML — `db.t3.micro` (2 vCPU burstable, 1 GiB).** É a menor classe que roda PostgreSQL 16 no
RDS. O volume de HML é o do seed mais o que uma sessão de teste gera: dezenas de ordens de
serviço, não milhares. Memória é o limite real, e 1 GiB comporta o *shared_buffers* padrão
mais as ~100 conexões declaradas.

**PRD — `db.t3.medium` (2 vCPU burstable, 4 GiB).** O salto não é por CPU: as duas classes têm
2 vCPU. É por **memória e por teto de conexões**.

O teto de conexões do PostgreSQL no RDS é derivado da memória:

```
LEAST({DBInstanceClassMemory / 9531392}, 5000)

db.t3.micro   1 GiB  →  ~112 conexões
db.t3.medium  4 GiB  →  ~450 conexões
```

O orçamento de `DB-ADR-004` exige **220 conexões em PRD** (10 réplicas × 17 + 20 execuções de
Lambda × 2 + folga). Isso não cabe em `db.t3.micro`, que tem teto físico de ~112. A escolha da
classe de PRD é consequência aritmética do teto de réplicas do HPA, não preferência.

`db.t3.small` (2 GiB, ~225 conexões) foi avaliada e rejeitada: caberia nas 220 com folga de 5
conexões, o que significa que qualquer ajuste de pool quebra o `plan`. Margem de 2% não é
margem.

### 2. `max_connections` declarado abaixo do teto físico

| Ambiente | Teto físico | Declarado | Orçamento usado | Folga |
|---|---|---|---|---|
| HML | ~112 | 100 | 80 | 20 |
| PRD | ~450 | 300 | 220 | 80 |

Declarar abaixo do teto é deliberado. O que consome as conexões que ficam fora do orçamento:
sessão de manutenção do RDS, conexão de superusuário reservada, e o `psql` de quem está
depurando. Um banco que chega a `max_connections` recusa **inclusive a conexão administrativa**,
e a recuperação vira reboot.

`max_connections` tem `apply_method = "pending-reboot"`. Mudar exige reinício da instância — em
ambiente efêmero isso é irrelevante, mas é a razão de o valor ser declarado no parameter group
e não ajustado em runtime.

### 3. Storage: 20 GB em HML, 50 GB em PRD, com autoscaling

`gp3` nos dois. O volume de dados do projeto é pequeno; o que dimensiona o storage no RDS é
**IOPS**, não espaço — e o baseline de `gp3` já entrega 3000 IOPS independentemente do tamanho.

`max_allocated_storage` (50 GB em HML, 200 GB em PRD) liga o autoscaling de storage. Existe
como rede de segurança contra crescimento não previsto de log ou de tabela temporária: o RDS
expande sozinho em vez de o banco parar com disco cheio. Nunca foi acionado. O storage
expandido **não encolhe** — em ambiente efêmero isso não importa, porque o próximo `destroy`
zera tudo.

### 4. Multi-AZ apenas em PRD

Multi-AZ mantém um standby síncrono em outra AZ e faz failover automático. **Dobra o custo da
instância** e não melhora leitura — o standby não atende consulta.

Em PRD está ligado porque é o que torna a arquitetura defensável como produção: a topologia de
duas AZs (`IAC-ADR-024`) existe em parte para isto.

Em HML está desligado porque HML é o ambiente mais recriado e o primeiro a ser destruído
quando ocioso. Pagar redundância em um banco cujo conteúdo é o seed do Flyway não faz sentido —
a recuperação de HML é `terraform apply`, não failover.

### 5. Backup: 0 dias em HML, 7 em PRD

`db_backup_retention_days = 0` **desliga o backup automático** em HML. É consistente com o
resto: os dados de HML são reproduzíveis por `V1..V3` a cada subida, e snapshot de um banco que
é destruído toda semana é armazenamento pago sem destino.

PRD tem 7 dias. O backup automático do RDS é gratuito até 100% do storage alocado — 50 GB de
backup para 50 GB alocados custa zero. Retenção maior passaria a ser paga.

`skip_final_snapshot = true` nos dois: em um projeto cujo `destroy` é rotina, snapshot final
acumula custo e nunca é restaurado.

### 6. Parameter group: os três ajustes que não são padrão

Iguais nos dois ambientes, deliberadamente — ajuste que só existe em PRD não é exercitado.

| Parâmetro | Valor | Por quê |
|---|---|---|
| `idle_in_transaction_session_timeout` | 60000 ms | Mata transação aberta e ociosa por mais de 1 min. Uma transação esquecida segura conexão **e** bloqueia `VACUUM`. Com um orçamento de conexões apertado, é o que impede uma conexão vazada de virar exaustão do pool |
| `log_min_duration_statement` | 1000 ms | Loga consulta acima de 1 s. É o insumo do painel de consulta lenta sem precisar de APM no banco |
| `shared_preload_libraries` | `pg_stat_statements` | Estatística agregada por consulta normalizada. Exige reinício, por isso `pending-reboot` |

`pg_stat_statements.track = all` inclui consultas dentro de função e procedure.

---

## Consequências

### Positivas

- A classe de cada ambiente é derivada do orçamento de conexões, que por sua vez é derivado do
  teto do HPA. A cadeia inteira é verificável e o `plan` falha quando alguém a quebra.
- HML custa cerca de um quarto de PRD e é destruível sem perda.
- Os ajustes de parameter group iguais nos dois ambientes garantem que o comportamento
  observado em HML vale em PRD.

### Negativas

- **HML não valida nada de Multi-AZ.** Failover, latência de commit síncrono e o
  comportamento da aplicação durante a troca só aparecem em PRD.
- HML sem backup significa que um erro em HML é irrecuperável a não ser recriando. Aceito por
  desenho.
- `db.t3.medium` é burstable: carga sustentada esgota crédito de CPU. Não é problema no perfil
  de uso do projeto, mas inviabiliza teste de carga longo.
- O teto de 300 conexões em PRD limita o HPA a 10 réplicas. Aumentar réplicas exige subir a
  classe da instância — os dois números andam juntos.

### Impacto em ambiente efêmero

Endpoint, senha e as senhas de role mudam a cada apply e são publicados no SSM. Os dados são
perdidos e o Flyway reaplica `V1..V3` no start, incluindo o seed. O parameter group é recriado
com `create_before_destroy` para não colidir com a instância em remoção.

---

## Alternativas consideradas

**`db.t3.small` em PRD.** ~225 conexões contra as 220 do orçamento. Rejeitada: 5 conexões de
folga significam que qualquer ajuste de pool quebra o `terraform plan`.

**Aurora Serverless v2.** Escala por ACU e para quando ocioso, o que casaria bem com o padrão
de uso. Rejeitada em `DB-ADR-001`: o custo mínimo por ACU na conta educacional supera o
`db.t3.micro` e a complexidade não se paga para um banco deste tamanho.

**Mesma classe nos dois ambientes.** Igualaria o comportamento e eliminaria a classe de defeito
"só acontece em PRD". Rejeitada por custo: HML com `db.t3.medium` e Multi-AZ sairia por
~US$ 100/mês equivalente, contra ~US$ 12.

**Multi-AZ também em HML.** Permitiria ensaiar failover antes da apresentação. Rejeitada:
dobrar o custo do ambiente mais descartável do projeto para exercitar um evento que a
apresentação não cobre.
