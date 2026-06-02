# sprint-deploy

Shell script para automatizar o deploy de branches sprint para os ambientes **development** e **homolog** via Pull Request no GitHub.

## O que faz

A partir da branch de trabalho (`sprint-XXX/TICKET`), o script:

1. Atualiza a branch base (`development` ou `homolog`)
2. Cria a branch de deploy (`feat/sprint-XXX/TICKET-dev` ou `-hml`)
3. Faz merge da branch de trabalho
4. Faz push para o remote
5. Cria o PR automaticamente via GitHub CLI

## Requisitos

- [Git](https://git-scm.com/)
- [GitHub CLI](https://cli.github.com/) autenticado (`gh auth login`)
- Git Bash (Windows) ou bash (Linux/macOS)

## Instalação

```bash
cp deploy.sh /usr/local/bin/deploy
chmod +x /usr/local/bin/deploy
```

## Uso

```bash
# Estando na branch sprint-XXX/TICKET:

deploy           # sobe para development e homolog
deploy dev       # sobe apenas para development
deploy hml       # sobe apenas para homolog
deploy --log     # exibe histórico de deploys
```

## Opções

| Opção | Descrição |
|---|---|
| `dev` / `hml` / `both` | Ambiente alvo (padrão: `both`) |
| `-t, --target <env>` | Equivalente ao atalho acima |
| `-d, --dry-run` | Simula sem executar nenhum comando |
| `-f, --force` | Recria branches de deploy já existentes |
| `-l, --log` | Exibe histórico em `~/.deploy_history.log` |
| `-h, --help` | Mostra ajuda |

## Padrão de branch

```
Branch de trabalho:   sprint-234/12345678
Branches geradas:     feat/sprint-234/12345678-dev  →  PR para development
                      feat/sprint-234/12345678-hml  →  PR para homolog
```

## Comportamentos

- **Branch já existe**: atualiza com novo merge em vez de falhar
- **PR já existe**: exibe a URL sem tentar criar duplicata
- **Working tree suja**: bloqueia com mensagem clara (use `--force` para ignorar)
- **Branch não está no remote**: faz push automático antes de iniciar
- **Conflito de merge**: aborta e imprime os comandos exatos para resolver manualmente
- **Falha em qualquer etapa**: volta automaticamente para a branch de trabalho original

## Histórico

Cada deploy é registrado em `~/.deploy_history.log`:

```
[2025-06-02 14:30:00] [agility] PR | feat/sprint-234/12345678-dev → development | https://...
[2025-06-02 14:30:45] [agility] Sucesso | sprint-234/12345678 → both
```
