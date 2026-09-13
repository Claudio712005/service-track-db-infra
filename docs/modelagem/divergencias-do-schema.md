# Divergências do schema

Extraído do documento de modelagem em 13/09/2026, quando o diagrama passou a ser mantido em
`modelo-entidade-relacionamento.drawio`.

**Fonte de verdade:** as migrations Flyway em
`service-track-api/software/service-track-api/_infrastructure/src/main/resources/db/migration/`.

---

## Divergências conhecidas

Levantadas na leitura do schema. Nenhuma está corrigida — correção é migration nova, e
migrations são append-only.

| # | Divergência | Consequência |
|---|---|---|
| M-01 | `ordem_servico_insumos.insumo_id` é `varchar(255)`, mas `insumos.id` é `uuid` | Impede a FK. Insumo inexistente pode ser gravado numa OS sem o banco recusar |
| M-02 | `mecanicos.usuario_id` é PK sem FK para `usuarios` | Mecânico órfão é possível; remover o usuário não é barrado |
| M-03 | `notificacoes.destinatario_id` sem FK | Notificação para destinatário inexistente é aceita |
| M-04 | `notificacao_copias.usuario_id` sem FK | Cópia para usuário inexistente é aceita |
| M-05 | `auditorias.responsavel_acao` é `varchar(36)` sem FK | Deliberado: auditoria precisa sobreviver à remoção do usuário. Documentado aqui para não ser lido como esquecimento |
| M-06 | `veiculos.ativo` é `varchar` com `CHECK ('S','N')`, enquanto `usuarios.ativo` e `insumos.ativo` são `boolean` | Inconsistência de representação do mesmo conceito |
| M-07 | PK de `veiculos` chama-se `veiculo_id`; nas demais tabelas chama-se `id` | Quebra a convenção de nomenclatura |
| M-08 | Nenhuma FK tem índice explícito | `JOIN` e verificação de integridade varrem a tabela filha. Sensível em `itens_ordem_servico` e `ordens_servico` |
| M-09 | Sem `ON DELETE` declarado em nenhuma FK | Comportamento padrão é `NO ACTION`; remoção de OS com itens falha sem mensagem de domínio |

M-01 a M-04 são de integridade referencial e valem uma migration corretiva antes de tratar
o modelo como estável. M-08 tende a aparecer primeiro como latência, não como erro.

---

## Volumetria e orçamento de conexões

O dimensionamento da instância e o teto de conexões de cada consumidor estão em
[`DB-ADR-004`](../adr/DB-ADR-004-orcamento-de-conexoes.md). O modelo não impõe carga relevante
de escrita: o caminho quente é leitura de `ordens_servico` com `JOIN` em `usuarios` e
`veiculos`, que é exatamente onde M-08 pesa.
