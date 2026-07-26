# DB-ADR-002: O Flyway na aplicação é dono do schema

## Data
26/07/2026

## Status
**Aceita**

## Contexto

Ao separar a infraestrutura do banco neste repositório, era preciso decidir quem passa a ser
dono do schema. As migrations Flyway vivem na aplicação (`db/migration`, `V1..V3`) e rodam na
subida dela, com um datasource dedicado usando `flyway_user`.

A função de autenticação lê as tabelas `usuarios` e `usuario_roles` e **não migra nada**
(`schema-management.strategy=none`).

Mover as migrations para cá tornaria a propriedade do banco mais coerente no papel, mas
introduziria ordem entre "migrar" e "subir a aplicação" em toda recriação de ambiente — e os
ambientes são recriados a cada teste ou apresentação.

## Decisão

**As migrations permanecem na aplicação.** Este repositório é dono da instância, das roles e
dos limites; a aplicação é dona da estrutura das tabelas.

A fronteira é a role: `flyway_user` pode criar e alterar estrutura, `app_user` não.

## Consequências

### Positivas
- Nenhuma ordem nova no ciclo de recriação: a aplicação sobe e migra sozinha.
- Schema versionado junto do código que o usa; um PR muda entidade e migration juntos.
- Sem janela em que a aplicação sobe antes do schema existir.

### Negativas
- O dono do banco não é o dono do schema. Exige disciplina para que uma migration não quebre a
  função de autenticação, que lê as mesmas tabelas sem participar do versionamento.
- Alteração incompatível em `usuarios` quebra a autenticação **sem sinal em CI**, porque os
  dois repositórios não se conhecem.

### Impacto em ambiente efêmero
Positivo e decisivo: é o que mantém a recriação em um passo automático.

## Mitigação da consequência negativa

O contrato de dados entre aplicação e autenticação está registrado em
`workspace/contracts/README.md` como contrato implícito. Alteração nas tabelas `usuarios` e
`usuario_roles` segue a skill `mudanca-de-contrato`.
