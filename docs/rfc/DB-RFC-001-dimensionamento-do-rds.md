# DB-RFC-001: Dimensionamento do RDS por ambiente

## Data

31/07/2026

## Status

- Implementada. ADR resultante: [`DB-ADR-006`](../adr/DB-ADR-006-dimensionamento-do-rds-por-ambiente.md).

---

## 1. Problema

`DB-ADR-001` decidiu usar RDS. `DB-ADR-004` decidiu o orçamento de conexões. Nenhum dos dois
diz por que HML roda `db.t3.micro` sem Multi-AZ e PRD roda `db.t3.medium` com Multi-AZ, nem por
que `max_connections` é 100 e 300 em vez do teto que cada classe suporta.

Sem isso registrado, o próximo ajuste de pool ou de réplicas vai esbarrar na `precondition` do
`plan` e a reação natural será aumentar `db_max_connections` até o erro sumir — que é
exatamente o caminho para o banco recusar conexão administrativa em produção.

---

## 2. Restrições

**Crédito finito e ambiente efêmero.** Conta AWS Academy. Os ambientes são destruídos após cada
teste ou apresentação. O que importa é custo por hora ligada.

**O teto de conexões é derivado da memória, não escolhido.** No RDS,
`LEAST({DBInstanceClassMemory / 9531392}, 5000)`:

| Classe | Memória | Teto físico |
|---|---|---|
| `db.t3.micro` | 1 GiB | ~112 |
| `db.t3.small` | 2 GiB | ~225 |
| `db.t3.medium` | 4 GiB | ~450 |

**O orçamento de PRD exige 220 conexões** (`DB-ADR-004`): 10 réplicas × (15 + 2) + 20 execuções
de Lambda × 2 + 10 de folga.

**Os dados de HML são reproduzíveis.** Flyway reaplica `V1..V3` com seed a cada subida.

---

## 3. Opções avaliadas

### Classe de PRD

| Classe | Teto | Folga sobre 220 | Custo aprox. Multi-AZ | Decisão |
|---|---|---|---|---|
| `db.t3.micro` | ~112 | **não cabe** | ~US$ 25/mês | impossível |
| `db.t3.small` | ~225 | 5 conexões | ~US$ 50/mês | rejeitada |
| `db.t3.medium` | ~450 | 230 conexões | ~US$ 100/mês | **adotada** |

`db.t3.small` foi a disputa real. Cabe no orçamento atual, e economiza ~US$ 50/mês. Rejeitada
porque a folga de 5 conexões significa que qualquer ajuste de pool — subir o pool da aplicação
de 15 para 16, ou a concorrência estimada da Lambda de 20 para 22 — quebra o `plan`. Margem de
2% não é margem; é uma armadilha para quem mexer no arquivo daqui a um mês.

### `max_connections`: teto físico ou valor declarado

Declarar `max_connections` igual ao teto físico maximiza o orçamento disponível. Rejeitado: um
PostgreSQL que atinge `max_connections` recusa **também** a conexão administrativa, e a
recuperação vira reboot da instância. As conexões reservadas (manutenção do RDS, superusuário,
`psql` de diagnóstico) precisam existir fora do orçamento.

Adotado 100 em HML (teto ~112) e 300 em PRD (teto ~450).

### Multi-AZ

| | Custo | Ganho | Decisão |
|---|---|---|---|
| HML | dobra (~US$ 12 → ~US$ 25) | failover num banco cujo conteúdo é o seed | **não** |
| PRD | dobra (~US$ 50 → ~US$ 100) | torna a topologia de duas AZs defensável | **sim** |

Multi-AZ não melhora leitura — o standby não atende consulta. O ganho é exclusivamente
disponibilidade.

### Backup

`db_backup_retention_days = 0` desliga o backup automático. Em HML isso é coerente: os dados
são reproduzíveis e o ambiente é destruído toda semana.

Em PRD ficou 7 dias porque o backup automático do RDS é **gratuito até 100% do storage
alocado** — 50 GB de backup para 50 GB alocados custa zero. Passar disso seria pago.

### Parameter group: igual ou diferente por ambiente

Avaliado deixar `log_min_duration_statement` mais permissivo em HML para reduzir ruído.
Rejeitado: ajuste que só existe em PRD nunca é exercitado antes de chegar lá. Os três
parâmetros ficaram idênticos nos dois ambientes.

---

## 4. Solução adotada

`db.t3.micro` / 20 GB / single-AZ / sem backup / 100 conexões em HML.
`db.t3.medium` / 50 GB / Multi-AZ / 7 dias / 300 conexões em PRD.
Parameter group idêntico.

Detalhe e aritmética em [`DB-ADR-006`](../adr/DB-ADR-006-dimensionamento-do-rds-por-ambiente.md).

---

## 5. Custo

Referência us-east-1, sob demanda, aproximado. Só conta enquanto o ambiente está ligado.

| Item | HML | PRD |
|---|---|---|
| Instância | `db.t3.micro` ~US$ 0,017/h (~US$ 12/mês) | `db.t3.medium` Multi-AZ ~US$ 0,136/h (~US$ 100/mês) |
| Storage `gp3` | 20 GB ~US$ 2,30/mês | 50 GB × 2 (Multi-AZ) ~US$ 11,50/mês |
| Backup | zero, desligado | zero, dentro da franquia |
| **Total ligado** | **~US$ 14/mês** | **~US$ 112/mês** |

PRD custa cerca de **oito vezes** HML. É o número que sustenta a regra de destruir o ambiente
ocioso e de manter HML como o primeiro a cair.

---

## 6. Riscos conhecidos

| Risco | Mitigação |
|---|---|
| HML não exercita failover, latência de commit síncrono nem o comportamento da aplicação durante a troca | Aceito. Nenhum teste de Multi-AZ antes de PRD |
| HML sem backup: erro é irrecuperável | Por desenho. Recuperação é `terraform apply` |
| `db.t3.medium` é burstable; carga sustentada esgota crédito de CPU | Não usar para teste de carga longo |
| Subir o teto do HPA sem rever a classe do banco quebra o `plan` | É o comportamento desejado da `precondition` de `DB-ADR-004` |
| Storage expandido pelo autoscaling não encolhe | Irrelevante em ambiente efêmero |

---

## 7. Evolução possível

- `db.t4g.micro` / `db.t4g.medium` (Graviton): mesma memória, ~10% mais barato. Depende de a
  conta educacional expor as classes ARM na região.
- Reduzir o pool da aplicação de 15 para 10 e reavaliar `db.t3.small` em PRD (~US$ 50/mês de
  economia), se o teto do HPA cair junto.
- Réplica de leitura em PRD, se surgir consulta analítica pesada. Hoje não há: o caminho quente
  é leitura de `ordens_servico` com `JOIN`, que o primário atende.
