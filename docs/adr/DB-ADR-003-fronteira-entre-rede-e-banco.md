# DB-ADR-003: Fronteira entre rede e banco, com ingress invertido

## Data
26/07/2026

## Status
**Aceita**

## Contexto

Separar o RDS para um repositório próprio criava uma dependência circular real entre states:

```
banco   precisa de  vpc_id, private_subnet_ids   ──► da infraestrutura
infra   precisa de  endpoint, credenciais        ──► do banco
```

Nenhum dos dois poderia ser aplicado primeiro. Havia ainda um segundo laço: o security group
do banco liberava a porta 5432 referenciando os security groups dos nodes do EKS e da Lambda,
que nascem no outro state.

## Decisão

**Três fronteiras, aplicadas em ordem determinística.**

1. **A rede sai para um state próprio** (`iac/network/<env>` no repositório de
   infraestrutura), seguindo o padrão já usado pela hosted zone de DNS. Passa a ser a primeira
   fase de qualquer ambiente.
2. **O banco lê a rede por `terraform_remote_state`** e cria seus recursos dentro da VPC
   existente. Não conhece EKS, Lambda nem gateway.
3. **O ingress é invertido.** O security group do banco nasce **sem regras de entrada**. Quem
   tem os security groups consumidores é a infraestrutura, e é lá que as regras de entrada são
   criadas, apontando para o SG do banco lido do SSM.

A comunicação de volta — endpoint, credenciais, orçamento de pool — é feita por **SSM
Parameter Store**, não por remote state, para que o acoplamento seja um contrato explícito e
nomeado em vez de leitura do state alheio.

Ordem final: **rede → banco → stack**.

## Consequências

### Positivas
- Circularidade eliminada; cada state tem um dono e uma ordem.
- O banco não conhece nada de computação; a infraestrutura não gerencia banco.
- O contrato entre repositórios é um conjunto de parâmetros nomeados, auditável no SSM.
- `aws_security_group_rule` separado já era usado no módulo original, então a inversão não
  exigiu reescrever o SG.

### Negativas
- **Três applies por recriação de ambiente**, contra um antes. Custo pago toda semana.
- Ordem errada produz falha: mitigada por checagem explícita na esteira, que aponta o que
  aplicar antes em vez de falhar com erro de atributo inexistente.
- Um `destroy` precisa da ordem inversa; destruir a rede antes do banco deixa recursos órfãos.
- Regra de segurança gerenciada em state diferente do security group que ela altera — legal no
  Terraform, mas exige que ninguém volte a usar bloco `ingress` inline no SG.

### Impacto em ambiente efêmero
É o principal custo desta decisão. Foi aceito porque a alternativa — manter o banco na
infraestrutura — não atenderia o requisito de quatro repositórios da Fase 3.

## Alternativas consideradas

**`-target` para aplicar só a rede na primeira fase** — evitaria extrair o state. Rejeitada:
`-target` é desaconselhado pela própria HashiCorp, e o plan parcial esconde drift.

**Banco com VPC própria e peering** — desacoplamento total. Rejeitada: peering, rotas e custo
adicional para resolver um problema que a ordem de apply já resolve.

**Infraestrutura lendo o banco por remote state** — Rejeitada: acopla ao formato interno do
state alheio. SSM é contrato nomeado e também serve aos scripts operacionais.
