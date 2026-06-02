#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Automação de deploy para development e homolog
# =============================================================================
#
# Uso:
#   deploy [--target dev|hml|both] [--dry-run] [--force]
#   deploy dev          # atalho para --target dev
#   deploy hml          # atalho para --target hml
#   deploy --log        # exibe histórico de deploys
#
# Exemplos:
#   deploy                     Sobe para development e homolog
#   deploy dev                 Sobe apenas para development
#   deploy hml --dry-run       Simula deploy para homolog
#   deploy --force             Recria branches de deploy se já existirem
#
# Padrão de branch esperado: sprint-XXX/TICKET  (ex: sprint-234/12345678)
# Branches geradas:
#   feat/sprint-XXX/TICKET-dev  → PR para development
#   feat/sprint-XXX/TICKET-hml  → PR para homolog
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES
# ─────────────────────────────────────────────────────────────────────────────
readonly VERSION="1.0.0"
readonly LOG_FILE="$HOME/.deploy_history.log"
readonly BRANCH_PATTERN='^sprint-[0-9]+/[0-9]+$'

# ─────────────────────────────────────────────────────────────────────────────
# CORES (desabilita automaticamente quando não é terminal)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'  GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' CYAN='\033[0;36m'  BOLD='\033[1m' RESET='\033[0m'
  DIM='\033[2m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET='' DIM=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
section() { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }
ok()      { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
info()    { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
fail()    { echo -e "  ${RED}✗${RESET}  ${RED}$*${RESET}" >&2; }
ts()      { echo -e "  ${DIM}$(date '+%H:%M:%S')${RESET} $*"; }
blank()   { echo ""; }

# ─────────────────────────────────────────────────────────────────────────────
# ESTADO GLOBAL
# ─────────────────────────────────────────────────────────────────────────────
TARGET="both"
DRY_RUN=false
FORCE=false
SHOW_LOG=false
FEATURE=""
SPRINT=""
TICKET=""
REPO_NAME=""
DEPLOYED_ENVS=()

# ─────────────────────────────────────────────────────────────────────────────
# EXECUÇÃO COM SUPORTE A DRY-RUN
# Uso: cmd <comando> [args...]
# Em dry-run: imprime o comando sem executar
# Em modo normal: executa e passa stdout/stderr adiante
# ─────────────────────────────────────────────────────────────────────────────
cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[dry]${RESET} $*"
    return 0
  fi
  "$@"
}

# Variante que captura stdout (retorna vazio em dry-run)
capture() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[dry]${RESET} $*" >&2
    echo ""
    return 0
  fi
  "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# AJUDA
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}deploy.sh${RESET} v${VERSION} — Automação de deploy para dev/homolog\n"
  echo -e "${BOLD}Uso:${RESET}"
  echo "  deploy [--target dev|hml|both] [--dry-run] [--force]"
  echo ""
  echo -e "${BOLD}Atalhos:${RESET}"
  echo "  deploy dev         Equivalente a --target dev"
  echo "  deploy hml         Equivalente a --target hml"
  echo "  deploy both        Equivalente a --target both (padrão)"
  echo ""
  echo -e "${BOLD}Opções:${RESET}"
  printf "  ${CYAN}%-25s${RESET} %s\n" "-t, --target <env>"   "Ambiente alvo: dev | hml | both  (padrão: both)"
  printf "  ${CYAN}%-25s${RESET} %s\n" "-d, --dry-run"        "Simula sem executar nenhum comando git/gh"
  printf "  ${CYAN}%-25s${RESET} %s\n" "-f, --force"          "Recria branches de deploy já existentes"
  printf "  ${CYAN}%-25s${RESET} %s\n" "-l, --log"            "Exibe histórico de deploys (~/.deploy_history.log)"
  printf "  ${CYAN}%-25s${RESET} %s\n" "-h, --help"           "Mostra esta mensagem"
  echo ""
  echo -e "${BOLD}Exemplos:${RESET}"
  echo "  deploy                       # dev + homolog"
  echo "  deploy dev                   # apenas development"
  echo "  deploy hml --dry-run         # simula deploy para homolog"
  echo "  deploy --force               # recria branches existentes"
  echo ""
  echo -e "${BOLD}Padrão de branch:${RESET}  sprint-XXX/TICKET  (ex: sprint-234/12345678)"
  echo -e "${BOLD}Branches geradas:${RESET}"
  echo "  feat/sprint-XXX/TICKET-dev  → PR para development"
  echo "  feat/sprint-XXX/TICKET-hml  → PR para homolog"
  echo ""
  echo -e "${BOLD}Histórico:${RESET}  $LOG_FILE"
  blank
  exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# HISTÓRICO
# ─────────────────────────────────────────────────────────────────────────────
show_log() {
  if [[ ! -f "$LOG_FILE" ]]; then
    info "Nenhum histórico encontrado em: ${LOG_FILE}"
    exit 0
  fi
  echo -e "\n${BOLD}Histórico de deploys${RESET} — ${DIM}${LOG_FILE}${RESET}\n"
  tail -n 50 "$LOG_FILE" | while IFS= read -r line; do
    if [[ "$line" == *"ERRO"* ]]; then
      echo -e "  ${RED}${line}${RESET}"
    elif [[ "$line" == *"Sucesso"* ]]; then
      echo -e "  ${GREEN}${line}${RESET}"
    else
      echo -e "  ${DIM}${line}${RESET}"
    fi
  done
  blank
  exit 0
}

append_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${REPO_NAME:-?}] $*" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# PARSE DE ARGUMENTOS
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--target)
        [[ -z "${2:-}" ]] && { fail "--target requer um valor: dev, hml ou both"; exit 1; }
        TARGET="$2"; shift 2 ;;
      -d|--dry-run) DRY_RUN=true;  shift ;;
      -f|--force)   FORCE=true;    shift ;;
      -l|--log)     SHOW_LOG=true; shift ;;
      -h|--help)    usage ;;
      dev|hml|both) TARGET="$1";   shift ;;
      *)
        fail "Argumento inválido: '$1'"
        info "Use --help para ver as opções disponíveis."
        exit 1 ;;
    esac
  done

  if [[ "$SHOW_LOG" == true ]]; then show_log; fi

  if [[ ! "$TARGET" =~ ^(dev|hml|both)$ ]]; then
    fail "Target inválido: '${TARGET}'"
    info "Valores aceitos: dev, hml, both"
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PRÉ-VOOS — valida ambiente antes de começar
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
  section "Verificações iniciais"

  # Repositório git
  if ! git rev-parse --git-dir &>/dev/null; then
    fail "Não está em um repositório git."
    exit 1
  fi
  REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

  # GitHub CLI instalado e autenticado
  if ! command -v gh &>/dev/null; then
    fail "GitHub CLI não encontrado."
    info "Instale em: https://cli.github.com"
    exit 1
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    fail "GitHub CLI não autenticado."
    info "Execute: gh auth login"
    exit 1
  fi

  # Branch atual
  FEATURE=$(git branch --show-current)
  if [[ -z "$FEATURE" ]]; then
    fail "HEAD detached — faça checkout em uma branch antes de continuar."
    exit 1
  fi
  if [[ ! "$FEATURE" =~ $BRANCH_PATTERN ]]; then
    fail "Branch '${FEATURE}' não segue o padrão esperado."
    info "Esperado:  sprint-XXX/TICKET"
    info "Exemplo:   sprint-234/12345678"
    exit 1
  fi

  # Working tree limpa
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    if [[ "$FORCE" == true ]]; then
      warn "Working tree com mudanças não commitadas (ignorando com --force)"
    else
      fail "Existem mudanças não commitadas na branch atual."
      info "Faça commit ou stash antes de continuar."
      info "Use --force para ignorar este aviso."
      exit 1
    fi
  fi

  # Extrai sprint e ticket do nome da branch
  SPRINT="${FEATURE%%/*}"   # sprint-234
  TICKET="${FEATURE##*/}"   # 12345678

  # Garante que a feature branch existe no remote (push se necessário)
  if ! git ls-remote --exit-code --heads origin "$FEATURE" &>/dev/null; then
    ts "Branch '${FEATURE}' não está no remote. Fazendo push..."
    cmd git push -u origin "$FEATURE"
  fi

  # Resumo do que vai acontecer
  blank
  ok "Repo:    ${BOLD}${REPO_NAME}${RESET}"
  ok "Branch:  ${BOLD}${FEATURE}${RESET}"
  ok "Sprint:  ${BOLD}${SPRINT}${RESET}"
  ok "Ticket:  ${BOLD}${TICKET}${RESET}"
  ok "Target:  ${BOLD}${TARGET}${RESET}"
  if [[ "$FORCE"   == true ]]; then warn "Modo --force ativo: branches existentes serão recriadas"; fi
  if [[ "$DRY_RUN" == true ]]; then warn "Modo --dry-run ativo: nenhum comando será executado"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CRIA OU REUTILIZA PR
# Não bloqueia se já existir — exibe URL e segue em frente
# ─────────────────────────────────────────────────────────────────────────────
ensure_pr() {
  local base="$1"
  local head="$2"

  ts "Verificando PRs existentes para ${head} → ${base}..."

  # Leitura sempre ocorre, mesmo em dry-run (operação read-only)
  local existing_url
  existing_url=$(gh pr list \
    --head  "$head" \
    --base  "$base" \
    --state open    \
    --json  url     \
    --jq    '.[0].url // ""' 2>/dev/null || echo "")

  if [[ -n "$existing_url" ]]; then
    warn "PR já existe — ${existing_url}"
    return 0
  fi

  local master_pr body
  master_pr=$(gh pr list \
    --head  "$FEATURE" \
    --base  "master" \
    --state open \
    --json  number \
    --jq    '.[0].number // ""' 2>/dev/null || echo "")

  if [[ -n "$master_pr" ]]; then
    body="#${master_pr}"
  else
    body=""
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry] gh pr create --base ${base} --head ${head} --title '${SPRINT}/${TICKET}'"
    return 0
  fi

  local pr_url
  pr_url=$(gh pr create \
    --base  "$base" \
    --head  "$head" \
    --title "${SPRINT}/${TICKET}" \
    --body  "$body")

  ok "PR criado: ${pr_url}"
  append_log "PR | ${head} → ${base} | ${pr_url}"
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY PARA UM AMBIENTE
# ─────────────────────────────────────────────────────────────────────────────
deploy_to() {
  local base="$1"    # development | homolog
  local suffix="$2"  # dev | hml
  local deploy_branch="feat/${SPRINT}/${TICKET}-${suffix}"

  section "Deploy → ${BOLD}${base}${RESET}"
  ts "Branch de deploy: ${deploy_branch}"

  # ── 1. Atualiza a branch base ─────────────────────────────────────────────
  ts "Atualizando ${base}..."
  cmd git checkout "$base"
  cmd git pull origin "$base"

  # ── 2. Gerencia branch de deploy existente ────────────────────────────────
  local local_exists remote_exists
  local_exists=$(git branch --list "$deploy_branch")
  remote_exists=$(git ls-remote --heads origin "$deploy_branch" 2>/dev/null || true)

  if [[ -n "$local_exists" || -n "$remote_exists" ]]; then
    if [[ "$FORCE" == true ]]; then
      warn "Recriando '${deploy_branch}' (--force)..."
      if [[ -n "$local_exists"  ]]; then cmd git branch -D "$deploy_branch"; fi
      if [[ -n "$remote_exists" ]]; then cmd git push origin --delete "$deploy_branch"; fi
      # continua abaixo para criar do zero
    else
      ts "Branch '${deploy_branch}' já existe — atualizando..."
      cmd git checkout "$deploy_branch"
      cmd git pull origin "$deploy_branch" 2>/dev/null || true

      if ! cmd git merge "$FEATURE" --no-edit; then
        fail "Conflito de merge em '${deploy_branch}'."
        _conflict_hint "$deploy_branch" "$base"
        cmd git checkout "$FEATURE"
        return 1
      fi

      cmd git push origin "$deploy_branch"
      ensure_pr "$base" "$deploy_branch"
      cmd git checkout "$FEATURE"
      DEPLOYED_ENVS+=("$base")
      ok "Deploy para ${base} concluído"
      return 0
    fi
  fi

  # ── 3. Cria nova branch de deploy ─────────────────────────────────────────
  ts "Criando '${deploy_branch}'..."
  cmd git checkout -b "$deploy_branch"

  if ! cmd git merge "$FEATURE" --no-edit; then
    fail "Conflito de merge detectado."
    _conflict_hint "$deploy_branch" "$base"
    cmd git checkout "$FEATURE"
    return 1
  fi

  # ── 4. Push ───────────────────────────────────────────────────────────────
  ts "Push de '${deploy_branch}'..."
  cmd git push -u origin "$deploy_branch"

  # ── 5. Cria PR ────────────────────────────────────────────────────────────
  ensure_pr "$base" "$deploy_branch"

  # ── 6. Volta para a branch de trabalho ───────────────────────────────────
  cmd git checkout "$FEATURE"
  DEPLOYED_ENVS+=("$base")
  ok "Deploy para ${base} concluído"
}

# ─────────────────────────────────────────────────────────────────────────────
# DICAS PARA CONFLITO DE MERGE
# ─────────────────────────────────────────────────────────────────────────────
_conflict_hint() {
  local deploy_branch="$1"
  local base="$2"
  blank
  warn "Resolva os conflitos manualmente:"
  echo -e "  ${DIM}1. Edite os arquivos conflitantes${RESET}"
  echo -e "  ${DIM}2. git add <arquivos>${RESET}"
  echo -e "  ${DIM}3. git merge --continue${RESET}"
  echo -e "  ${DIM}4. git push -u origin ${deploy_branch}${RESET}"
  echo -e "  ${DIM}5. gh pr create -B ${base}${RESET}"
  blank
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP — executado pelo trap EXIT
# ─────────────────────────────────────────────────────────────────────────────
_cleanup() {
  local code=$?
  if [[ $code -eq 0 ]]; then return; fi

  blank
  fail "Script interrompido com exit code ${code}."

  # Tenta voltar para a branch de trabalho
  if [[ -n "${FEATURE:-}" ]]; then
    local current
    current=$(git branch --show-current 2>/dev/null || true)
    if [[ -n "$current" && "$current" != "$FEATURE" ]]; then
      warn "Retornando para '${FEATURE}'..."
      git checkout "$FEATURE" 2>/dev/null || true
    fi
    append_log "ERRO (exit=${code}) | ${FEATURE} → ${TARGET}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# RESUMO FINAL
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
  local sep="${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  blank
  echo -e "$sep"
  echo -e "  ${BOLD}${GREEN}Deploy concluído!${RESET}"
  echo -e "$sep"
  blank
  echo -e "  ${BOLD}Repo:${RESET}    ${REPO_NAME}"
  echo -e "  ${BOLD}Branch:${RESET}  ${FEATURE}"
  blank
  for env in "${DEPLOYED_ENVS[@]}"; do
    local suffix="dev"
    if [[ "$env" == "homolog" ]]; then suffix="hml"; fi
    echo -e "  ${GREEN}✓${RESET} ${env}   ${DIM}feat/${SPRINT}/${TICKET}-${suffix}${RESET}"
  done
  blank
  if [[ "$DRY_RUN" == true ]]; then echo -e "  ${YELLOW}(modo dry-run — nenhuma alteração foi feita)${RESET}\n"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
  trap _cleanup EXIT

  parse_args "$@"
  preflight

  if [[ "$TARGET" == "dev"  || "$TARGET" == "both" ]]; then deploy_to "development" "dev"; fi
  if [[ "$TARGET" == "hml"  || "$TARGET" == "both" ]]; then deploy_to "homolog"     "hml"; fi

  print_summary
  append_log "Sucesso | ${FEATURE} → ${TARGET}"
}

main "$@"
