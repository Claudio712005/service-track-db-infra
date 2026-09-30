# DB-ADR-007: nenhum identificador de conta AWS no código

## Data
29/09/2026

## Status
Aceita. Alinhada com `IAC-ADR-029`, que é onde a decisão nasceu.

---

## Contexto

Este repositório escrevia o identificador da conta AWS em quatro lugares: o `bucket` do
`backend "s3"` dos dois ambientes e o `default` da variável `state_bucket`, usada para ler o
state de rede.

A conta é de laboratório educacional e muda. Quando muda, `terraform init` falha apontando para
um bucket que não existe naquela conta — e destravar exigia um pull request mecânico aqui, mais
outros dois nos repositórios vizinhos, antes de qualquer trabalho.

## Decisão

O identificador da conta não aparece em arquivo versionado:

- O `backend "s3"` fica parcial. O `bucket` chega por `-backend-config` no `init`.
- `state_bucket` passa a ter `default` vazio, e o valor efetivo vem de
  `data.aws_caller_identity`. A variável permanece como escotilha para apontar outro bucket.
- A esteira descobre a conta com `aws sts get-caller-identity` e passa o bucket no `init`.

## Consequências

- Trocar de laboratório não exige alteração neste repositório.
- **Credencial AWS válida passou a ser pré-requisito do `init`**, não só do `plan`: o nome do
  bucket vem do `sts`. A esteira já configurava credencial antes; no uso local, o comando do
  README traz o `-backend-config` pronto.
- `terraform init` sem argumento falha pedindo o `bucket`. É o comportamento desejado: erro
  explícito em vez de state criado no lugar errado.
- O state da conta anterior continua naquela conta. Não há migração: ambiente em conta nova
  nasce do zero, como manda `GLOBAL-ADR-002`.
