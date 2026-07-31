# Modelo entidade-relacionamento

Modelo relacional do PostgreSQL do ServiceTrack.

**Fonte de verdade:** as migrations Flyway em
`service-track-api/software/service-track-api/_infrastructure/src/main/resources/db/migration/`.
O schema pertence à aplicação (`DB-ADR-002`); este documento descreve o resultado, não o
define. Ao alterar uma migration, atualizar este documento no mesmo ciclo.

Estado descrito: `V1__baseline_schema.sql` + `V3__update_notificacao_tipo_conteudo_constraint.sql`.

---

## Diagrama

```mermaid
erDiagram
    usuarios ||--o{ usuario_roles : "possui"
    usuarios ||--o| mecanicos : "especializa"
    usuarios ||--o{ veiculos : "e proprietario de"
    usuarios ||--o{ ordens_servico : "abre como cliente"
    usuarios ||--o{ ordens_servico : "atende como mecanico"
    usuarios ||--o{ itens_ordem_servico : "executa"
    usuarios ||--o{ notificacoes : "recebe"
    usuarios ||--o{ notificacao_copias : "recebe copia"

    veiculos ||--o{ ordens_servico : "e objeto de"

    ordens_servico ||--o| orcamentos : "tem"
    ordens_servico ||--o{ itens_ordem_servico : "contem"
    ordens_servico ||--o{ ordem_servico_insumos : "consome"

    servicos ||--o{ itens_ordem_servico : "tipifica"
    insumos ||--o{ ordem_servico_insumos : "e consumido em"

    notificacoes ||--o{ notificacao_copias : "tem"

    usuarios {
        uuid id PK
        varchar cpf UK
        varchar email UK
        varchar nome
        varchar telefone
        date data_nascimento
        varchar senha_hash
        boolean ativo
        timestamp data_criacao
        timestamp data_atualizacao
    }

    usuario_roles {
        uuid usuario_id FK
        varchar role "CLIENTE, MECANICO"
    }

    mecanicos {
        uuid usuario_id PK
        varchar nivel "JUNIOR, PLENO, SENIOR"
        numeric valor_hora
    }

    veiculos {
        uuid veiculo_id PK
        uuid proprietario_id FK
        varchar placa UK
        varchar marca
        varchar modelo
        integer ano
        varchar codigo_fipe
        varchar imagem_url
        varchar ativo "S, N"
        timestamp data_criacao
        timestamp data_atualizacao
    }

    ordens_servico {
        uuid id PK
        uuid cliente_id FK
        uuid mecanico_id FK
        uuid veiculo_id FK
        varchar status "CANCELADA, RECEBIDA, EM_DIAGNOSTICO, AGUARDANDO_APROVACAO, EM_EXECUCAO, FINALIZADA, ENTREGUE"
        varchar motivo
        text observacao
        timestamp prazo_conclusao
        timestamp data_criacao
        timestamp data_atualizacao
    }

    orcamentos {
        uuid id PK
        uuid ordem_servico_id FK "UNIQUE"
        numeric custo_insumos
        numeric custo_mao_de_obra
        boolean aprovado
        text observacao
        timestamp data_criacao
        timestamp data_atualizacao
    }

    itens_ordem_servico {
        uuid id PK
        uuid ordem_servico_id FK
        uuid servico_id FK
        uuid mecanico_responsavel_id FK
        numeric valor
        boolean feito
        text observacao
        timestamp data_realizacao
        timestamp data_criacao
        timestamp data_atualizacao
    }

    servicos {
        uuid id PK
        varchar nome_servico
        text descricao_servico
        numeric valor_referencia
        boolean ativo
        timestamp data_criacao
        timestamp data_atualizacao
    }

    insumos {
        uuid id PK
        varchar nome
        text descricao
        numeric custo
        integer qtd_estoque
        integer estoque_minimo
        boolean ativo
        timestamp data_criacao
        timestamp data_atualizacao
    }

    ordem_servico_insumos {
        uuid ordem_servico_id FK
        varchar insumo_id
    }

    notificacoes {
        uuid id PK
        uuid destinatario_id
        varchar tipo_notificacao "EMAIL"
        varchar tipo_conteudo_notificacao "MUDANCA_STATUS_OS, SOLICITACAO_APROVACAO_ORCAMENTO_OS, DECISAO_ORCAMENTO_OS"
        varchar status_envio "PENDENTE, ENVIADA, FALHA_ENVIO"
        varchar assunto
        varchar titulo
        text descricao
        text variaveis_json
        text ultimo_erro
        integer tentativas_envio
        boolean visualizada
        timestamp data_envio
        timestamp data_visualizacao
        timestamp data_criacao
    }

    notificacao_copias {
        uuid notificacao_id FK
        uuid usuario_id
    }

    auditorias {
        uuid id PK
        varchar responsavel_acao
        varchar tipo_entidade
        varchar tipo_evento
        varchar referencia_id
        varchar endereco_ip
        text dados
        text descricao_evento
        timestamp data_criacao
    }
```

---

## Agregados e cardinalidades

| Relação | Cardinalidade | Como é imposta |
|---|---|---|
| `usuarios` → `usuario_roles` | 1:N | FK `fk_usuario_roles_usuario` |
| `usuarios` → `mecanicos` | 1:0..1 | PK compartilhada, **sem FK** |
| `usuarios` → `veiculos` | 1:N | FK `fk_veiculo_proprietario` |
| `usuarios` → `ordens_servico` (cliente) | 1:N | FK `fk_ordem_cliente` |
| `usuarios` → `ordens_servico` (mecânico) | 1:N | FK `fk_ordem_mecanico` |
| `veiculos` → `ordens_servico` | 1:N | FK `fk_ordem_veiculo` |
| `ordens_servico` → `orcamentos` | 1:0..1 | FK + `UNIQUE` em `ordem_servico_id` |
| `ordens_servico` → `itens_ordem_servico` | 1:N | FK `fk_item_ordem_servico` |
| `servicos` → `itens_ordem_servico` | 1:N | FK `fk_item_servico` |
| `usuarios` → `itens_ordem_servico` | 1:N, opcional | FK `fk_item_mecanico_responsavel` |
| `ordens_servico` → `ordem_servico_insumos` | 1:N | FK `fk_ordem_servico_insumos_ordem` |
| `insumos` → `ordem_servico_insumos` | 1:N | **sem FK** — tipos divergentes |
| `notificacoes` → `notificacao_copias` | 1:N | FK `fk_notificacao_copias_notificacao` |

A raiz transacional é `ordens_servico`: orçamento, itens e insumos só existem em função dela.
`usuarios` é a única entidade referenciada por quase todo o modelo — cliente, mecânico
responsável e destinatário de notificação são o mesmo registro em papéis diferentes,
distinguidos por `usuario_roles`.

---

## Chaves e restrições

**Unicidade de negócio:** `usuarios.cpf`, `usuarios.email`, `veiculos.placa` e
`orcamentos.ordem_servico_id`. O `cpf` único é o que sustenta a autenticação por CPF.

**Domínios fechados por `CHECK`:** `usuario_roles.role`, `mecanicos.nivel`,
`ordens_servico.status`, `veiculos.ativo`, e os três de `notificacoes`. São enums da aplicação
espelhados no banco — mudar o enum sem migration nova quebra a inserção em runtime.

**Índices explícitos:** apenas `idx_auditoria_referencia_id` e `idx_auditoria_data_criacao`.
As demais consultas dependem dos índices implícitos de PK e `UNIQUE`.

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
[`DB-ADR-004`](../adr/DB-ADR-004-orcamento-de-conexoes.md), não aqui. O modelo não impõe
carga relevante de escrita: o caminho quente é leitura de `ordens_servico` com `JOIN` em
`usuarios` e `veiculos`, que é exatamente onde M-08 pesa.
