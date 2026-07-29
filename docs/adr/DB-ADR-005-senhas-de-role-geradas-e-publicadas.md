# DB-ADR-005: Senhas das roles geradas aqui e publicadas no SSM

## Data
29/07/2026

## Status
**Aceita**

## Contexto

As senhas de `app_user`, `flyway_user` e `readonly_user` eram digitadas à mão em dois lugares:

1. no `app_secret_params` do repositório de infraestrutura, que as materializava como secret
   do Kubernetes para a aplicação usar;
2. como variáveis de ambiente do `aplicar-roles.sh`, que as usa para **criar** as roles.

Duas fontes para o mesmo valor, sincronizadas manualmente a cada recriação de ambiente. Se
divergissem, o sintoma seria a aplicação subindo e falhando na autenticação com o banco —
depois do deploy, não durante.

Este repositório já é dono das roles e dos seus privilégios (`DB-ADR-002`), mas não era dono
das credenciais delas.

## Decisão

**Quem cria a role gera a senha.**

Um `random_password` por role, publicado no SSM como `SecureString`:

```
/servicetrack/<env>/db/roles/<role>/usuario
/servicetrack/<env>/db/roles/<role>/senha
```

O `aplicar-roles.sh` lê do SSM em vez de exigir variáveis de ambiente. O bootstrap do
repositório de infraestrutura lê dos mesmos parâmetros para compor os secrets do Kubernetes.

Uma fonte, dois leitores.

## Consequências

### Positivas
- Divergência entre a senha criada no banco e a entregue à aplicação deixa de ser possível.
- `aplicar-roles.sh` roda sem nenhuma variável de ambiente — só o nome do ambiente.
- As senhas são rotacionadas a cada recriação, sem intervenção.
- Nenhuma senha de banco precisa existir como secret do GitHub.

### Negativas
- As senhas ficam no state deste repositório, como já acontecia com a senha do master
  (`I-16`).
- O repositório de infraestrutura passa a depender de parâmetros publicados por este. A falha,
  quando a ordem é violada, é explícita: o bootstrap para e diz qual repositório aplicar antes.
- Ler a senha para depuração passa a exigir AWS CLI, não é mais copiar de um `tfvars`.

### Impacto em ambiente efêmero
Favorável. Elimina dois passos manuais por recriação: compor o blob de segredos e exportar as
variáveis antes do script de roles.

## Alternativas consideradas

**Manter no `app_secret_params` e fazer o script de roles ler de lá** — o repositório de
infraestrutura continuaria dono de credencial de recurso que não é dele, e a ordem de leitura
ficaria invertida em relação à de criação.

**Senha por role gerada no primeiro `aplicar-roles.sh` e gravada no SSM pelo script** — tiraria
o valor do state Terraform, mas o script deixaria de ser idempotente: uma segunda execução
geraria senha nova e quebraria a aplicação em execução.
