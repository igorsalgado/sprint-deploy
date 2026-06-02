# agent.md — sprint-deploy

Documentação técnica para agentes e automações que interagem com este projeto.

## Propósito

`deploy.sh` automatiza o fluxo de criação de PRs para os ambientes `development` e `homolog` a partir de branches no padrão `sprint-XXX/TICKET`.

Substitui manualmente:
```bash
git checkout development && git pull
git checkout -b feat/sprint-XXX/TICKET-dev
git merge sprint-XXX/TICKET
gh pr create -B development
# (repetir para homolog)
```

## Interface do script

### Invocação

```bash
deploy [--target dev|hml|both] [--dry-run] [--force]
```

### Parâmetros

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---|---|
| `--target` / primeiro arg | `dev\|hml\|both` | `both` | Ambiente(s) de destino |
| `--dry-run` | flag | `false` | Simula sem executar git/gh |
| `--force` | flag | `false` | Recria branches existentes |
| `--log` | flag | — | Exibe histórico e sai |

### Exit codes

| Code | Significado |
|---|---|
| `0` | Sucesso |
| `1` | Falha (branch inválida, merge conflict, gh não autenticado, etc.) |

### Variáveis de ambiente relevantes

| Variável | Uso |
|---|---|
| `HOME` | Base para `~/.deploy_history.log` |

## Pré-condições para execução bem-sucedida

1. Working directory é um repositório git com remote `origin`
2. Branch atual segue o padrão `sprint-[0-9]+/[0-9]+`
3. `gh` está instalado e autenticado (`gh auth status`)
4. Branches `development` e/ou `homolog` existem no remote
5. Working tree está limpa (sem mudanças não commitadas)

## Fluxo interno por ambiente

```
preflight()
  └── valida git, gh, branch, working tree
  └── push da feature branch se não estiver no remote

deploy_to(base, suffix)
  ├── git checkout <base> && git pull
  ├── se branch de deploy já existe:
  │     ├── --force: deleta local + remote e recria
  │     └── padrão: atualiza com novo merge
  ├── git checkout -b feat/<sprint>/<ticket>-<suffix>
  ├── git merge <feature> --no-edit
  ├── git push -u origin <deploy_branch>
  └── ensure_pr(base, deploy_branch)
        ├── gh pr list → se já existe, exibe URL e retorna
        └── gh pr create --title "<sprint>/<ticket>"
```

## Arquivos gerados / modificados

| Arquivo | Descrição |
|---|---|
| `~/.deploy_history.log` | Log de todos os deploys com timestamp, repo, status e URL do PR |

## Convenção de nomes de branch

```
Feature:   sprint-{sprint_num}/{ticket_id}
Deploy dev: feat/sprint-{sprint_num}/{ticket_id}-dev
Deploy hml: feat/sprint-{sprint_num}/{ticket_id}-hml
```

Exemplos:
```
sprint-234/12345678
feat/sprint-234/12345678-dev
feat/sprint-234/12345678-hml
```

## Instalação

```bash
cp deploy.sh /usr/local/bin/deploy
chmod +x /usr/local/bin/deploy
```

## Como sugerir o uso deste script

Quando o usuário estiver em uma branch `sprint-XXX/TICKET` e quiser abrir PRs para os ambientes, sugerir:

```bash
deploy        # para ambos os ambientes
deploy dev    # para development apenas
deploy hml    # para homolog apenas
```

Antes de sugerir, verificar:
- Branch atual segue o padrão sprint (`git branch --show-current`)
- Script está instalado (`which deploy`)
- `gh` está autenticado (`gh auth status`)
