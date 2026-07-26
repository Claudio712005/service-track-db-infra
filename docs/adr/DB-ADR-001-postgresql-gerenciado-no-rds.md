# DB-ADR-001: PostgreSQL gerenciado no Amazon RDS

## Data
26/07/2026

## Status
**Aceita** — formaliza uma escolha já em uso desde a Fase 2 (`API-ADR-002`), agora sob a
propriedade deste repositório.

## Contexto

O domínio é transacional: uma ordem de serviço muda de status por um fluxo com invariantes,
tem itens de serviço e insumos com integridade referencial, e orçamento com valores monetários.
Perder consistência aqui é perder o produto.

Dois serviços leem o mesmo banco — a aplicação e a função de autenticação — o que exige um
motor com controle de concorrência maduro e roles segregadas.

A Fase 3 exige justificativa formal da escolha do banco.

## Decisão

**PostgreSQL 16 no Amazon RDS**, instância privada, criptografada, sem acesso público.

Motivos, em ordem de peso:

1. **Transacional com integridade referencial.** O ciclo de vida da OS depende de chaves
   estrangeiras e transações. Um banco de documentos exigiria reimplementar em código o que o
   motor já garante.
2. **Gerenciado.** Backup, patch e failover deixam de ser trabalho nosso. Com ambientes
   recriados semanalmente, qualquer operação manual de banco seria paga toda semana.
3. **Multi-AZ disponível por configuração.** Alta disponibilidade sem mudar arquitetura.
4. **Tipos e recursos que o domínio usa.** `numeric` exato para dinheiro, `uuid` nativo,
   `check` para máquina de estados, índices parciais.
5. **Continuidade.** Já era PostgreSQL desde a Fase 1; migrar de motor seria custo sem ganho.

## Consequências

### Positivas
- Integridade garantida pelo motor.
- Operação de rotina terceirizada.
- Multi-AZ e autoscaling de storage por variável.

### Negativas
- Custo fixo por instância mesmo ociosa — mitigado destruindo ambientes.
- Escala vertical primeiro; escala horizontal de escrita exigiria outra arquitetura.
- Acoplamento a um serviço gerenciado da AWS.

### Impacto em ambiente efêmero
Os dados não sobrevivem, e isso é aceito. O que precisa sobreviver é a **modelagem** e o
**seed**, ambos versionados. `skip_final_snapshot = true` e `deletion_protection = false`
existem justamente para que o `destroy` funcione sem intervenção.

## Alternativas consideradas

**Aurora Serverless v2** — escala a zero e casaria com o ciclo efêmero. Rejeitada: custo
mínimo por ACU maior que `db.t3.micro` na conta educacional, e complexidade desnecessária.

**PostgreSQL em contêiner no próprio EKS** — custo marginal zero. Rejeitada: o enunciado pede
banco **gerenciado**, e o dado morreria junto com o cluster, sem backup nem failover.

**DynamoDB** — Rejeitada: o domínio é relacional e transacional entre agregados.
