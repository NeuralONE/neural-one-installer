#!/usr/bin/env bash
#
# Neural ONE — Instalador de onboarding (capa pre-bootstrap)
# =========================================================
#
# Punto de entrada único para dejar una laptop macOS virgen lista para trabajar
# con el ecosistema de data. Se ejecuta con el one-liner:
#
#   curl -fsSL https://raw.githubusercontent.com/NeuralONE/neural-one-installer/main/install.sh | bash
#
# Qué hace (y qué NO):
#   - Instala los prerequisitos que el bootstrap del equipo da por hechos
#     (Homebrew, git, gh, gcloud, jq, yq, python3, node, VS Code, Claude Code).
#   - Autentica gcloud + GitHub (lo mínimo para clonar el repo privado).
#   - Verifica que tu cuenta está autorizada en el equipo (mensaje neutro si no).
#   - Clona el repo de configuración privado y delega TODO el resto al
#     bootstrap del equipo (settings, hooks, MCP, skills, memoria, healthcheck).
#
#   Este script NO contiene nada sensible: solo orquesta. Toda la configuración
#   del equipo vive en el repo privado, que se descarga tras autenticarte.
#
# Es idempotente: re-ejecutarlo no rompe nada; sirve también para self-heal.

set -euo pipefail

# ============================================================
# Config
# ============================================================

OPS_REPO_SLUG="NeuralONE/neural-one-data-ops"
OPS_REPO_URL="https://github.com/${OPS_REPO_SLUG}.git"
TEAM_YAML_PATH="bootstrap/team.yaml"          # ruta dentro del repo privado
CODE_DIR="${HOME}/Code"
OPS_DIR="${CODE_DIR}/neural-one-data-ops"

# Lee de la terminal real, no del stdin (que es el propio script bajo `curl | bash`).
TTY=/dev/tty

# ============================================================
# Logging (self-contained, sin dependencias del repo)
# ============================================================

if [ -t 1 ] || [ -e "$TTY" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

log()       { printf '%s\n' "$*"; }
log_step()  { printf '\n%s▶ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
log_ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '  %s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_info()  { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
log_err()   { printf '\n%s✗ %s%s\n' "$C_BOLD$C_RED" "$*" "$C_RESET" >&2; }
die()       { log_err "$*"; exit 1; }

banner() {
  printf '\n%s╔════════════════════════════════════════════════╗%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
  printf '%s║   Neural ONE — Onboarding                      ║%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
  printf '%s╚════════════════════════════════════════════════╝%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
}

# Pregunta [Y/n] leyendo de la terminal real. Default: yes.
confirm() {
  local prompt="$1" reply
  if [ ! -e "$TTY" ]; then
    # Sin terminal interactiva (CI, etc.): asumimos sí y seguimos.
    return 0
  fi
  printf '  %s? %s [Y/n] %s' "$C_YELLOW" "$prompt" "$C_RESET" > "$TTY"
  read -r reply < "$TTY" || reply=""
  case "$reply" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# ============================================================
# 0. Pre-checks de plataforma
# ============================================================

banner

if [ "$(uname -s)" != "Darwin" ]; then
  die "Este instalador es para macOS. Plataforma detectada: $(uname -s)."
fi

# ============================================================
# 1. Homebrew + prerequisitos
# ============================================================

log_step "Prerequisitos"

# Persistencia de PATH en el perfil de login (~/.zprofile): brew y gcloud deben
# quedar disponibles también en sesiones futuras (no solo en la del instalador).
# Bloque marcado e idempotente — re-ejecutar reemplaza el bloque, no duplica.
NEURAL_PROFILE="$HOME/.zprofile"
PROFILE_BEGIN="# === BEGIN Neural ONE installer (PATH) ==="
PROFILE_END="# === END Neural ONE installer (PATH) ==="

persist_profile_block() {
  local block="$1" tmp
  touch "$NEURAL_PROFILE"
  if grep -qF "$PROFILE_BEGIN" "$NEURAL_PROFILE" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v b="$PROFILE_BEGIN" -v e="$PROFILE_END" \
      '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$NEURAL_PROFILE" > "$tmp"
    mv "$tmp" "$NEURAL_PROFILE"
  fi
  printf '\n%s\n%s\n%s\n' "$PROFILE_BEGIN" "$block" "$PROFILE_END" >> "$NEURAL_PROFILE"
}

ensure_homebrew() {
  if command -v brew &>/dev/null; then
    log_ok "Homebrew disponible"
    return 0
  fi
  log_warn "Homebrew no está instalado (gestor de paquetes necesario para el resto)."
  if ! confirm "¿Instalar Homebrew ahora?"; then
    die "Homebrew es imprescindible. Instálalo desde https://brew.sh y reintenta."
  fi
  /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < "$TTY"
  # Cargar brew en el PATH de esta sesión (Apple Silicon e Intel).
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)";
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  command -v brew &>/dev/null || die "Homebrew no quedó en el PATH. Abre una terminal nueva y reintenta."
  log_ok "Homebrew instalado"
}

# Instala una fórmula brew si el comando no existe.
ensure_formula() {
  local cmd="$1" formula="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    log_ok "$cmd disponible"
    return 0
  fi
  log_warn "Falta '$cmd'."
  if ! confirm "¿Instalar '$formula' vía Homebrew?"; then
    die "'$cmd' es necesario. Instálalo y reintenta."
  fi
  brew install "$formula"
  log_ok "$cmd instalado"
}

# Instala un cask brew si el binario testigo no existe.
ensure_cask() {
  local witness="$1" cask="$2" label="${3:-$cask}"
  if command -v "$witness" &>/dev/null; then
    log_ok "$label disponible"
    return 0
  fi
  log_warn "Falta '$label'."
  if ! confirm "¿Instalar '$label' vía Homebrew?"; then
    log_warn "'$label' omitido — algunas funciones pueden no estar disponibles."
    return 0
  fi
  brew install --cask "$cask"
  log_ok "$label instalado"
}

# gcloud: caso especial. El cask `google-cloud-sdk` NO deja `gcloud` en el PATH
# del shell actual (a diferencia de las fórmulas, que symlinkean a la bin de
# brew): hay que sourcear su `path.zsh.inc`. Sin esto, el `gcloud auth login`
# de la siguiente fase fallaría con "command not found" incluso en máquina nueva.
ensure_gcloud() {
  if command -v gcloud &>/dev/null; then
    log_ok "Google Cloud SDK disponible"
    return 0
  fi
  log_warn "Falta 'Google Cloud SDK'."
  if ! confirm "¿Instalar 'Google Cloud SDK' vía Homebrew?"; then
    die "Google Cloud SDK es necesario para autenticarte. Instálalo y reintenta."
  fi
  brew install --cask google-cloud-sdk
  local inc; inc="$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
  if [ -f "$inc" ]; then source "$inc"; fi
  command -v gcloud &>/dev/null \
    || die "Google Cloud SDK instalado pero 'gcloud' no quedó en el PATH. Abre una terminal nueva y reintenta."
  log_ok "Google Cloud SDK instalado"
}

# Claude Code (el CLI del equipo). Instalación nativa de Anthropic → ~/.local/bin
# (el layout que usa el equipo). El wrapper `claude()` del bootstrap (módulo 45)
# hace `command claude`, así que el binario debe existir antes del primer uso.
ensure_claude_code() {
  if command -v claude &>/dev/null || [ -x "$HOME/.local/bin/claude" ]; then
    log_ok "Claude Code disponible"
    return 0
  fi
  log_warn "Falta Claude Code (el CLI del equipo)."
  if ! confirm "¿Instalar Claude Code ahora?"; then
    die "Claude Code es necesario para trabajar. Instálalo (https://claude.ai/install.sh) y reintenta."
  fi
  curl -fsSL https://claude.ai/install.sh | bash
  if ! command -v claude &>/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
    die "Claude Code instalado pero no se encontró el binario. Abre una terminal nueva y reintenta."
  fi
  log_ok "Claude Code instalado"
}

ensure_homebrew
ensure_formula git
ensure_formula gh
ensure_formula jq
ensure_formula yq
ensure_formula python3 python
ensure_formula node               # trae npx — el bootstrap (módulo 35, MCP Looker) lo exige
ensure_gcloud
ensure_cask code visual-studio-code "VS Code"
ensure_claude_code

# Persistir el PATH para sesiones futuras (brew + gcloud) en ~/.zprofile. En la
# sesión del instalador ya están cargados; esto asegura que el `claude` diario y
# cualquier terminal nueva (incl. la integrada de VS Code) los encuentren.
if command -v brew &>/dev/null; then
  _brew_bin="$(command -v brew)"
  _gcloud_inc="$("$_brew_bin" --prefix)/share/google-cloud-sdk/path.zsh.inc"
  persist_profile_block "eval \"\$(${_brew_bin} shellenv)\"
[ -f \"${_gcloud_inc}\" ] && source \"${_gcloud_inc}\""
  log_ok "PATH persistido en ~/.zprofile (brew + gcloud)"
fi

# ============================================================
# 2. Autenticación
# ============================================================

log_step "Autenticación"

# gcloud — define la identidad del equipo (email @neural.one, clave de team.yaml).
USER_EMAIL="$(gcloud config get-value account 2>/dev/null || true)"
if [ -z "$USER_EMAIL" ] || [ "$USER_EMAIL" = "(unset)" ]; then
  log_info "Autenticando con Google Cloud…"
  gcloud auth login < "$TTY"
  USER_EMAIL="$(gcloud config get-value account 2>/dev/null || true)"
fi
[ -n "$USER_EMAIL" ] && [ "$USER_EMAIL" != "(unset)" ] \
  || die "No se pudo determinar tu cuenta de Google Cloud tras el login."
log_ok "Cuenta Google Cloud: $USER_EMAIL"

# GitHub — necesario para clonar el repo de configuración privado.
if gh auth status &>/dev/null; then
  log_ok "GitHub autenticado"
else
  log_info "Autenticando con GitHub…"
  # Flags pre-respondidos para saltar las preguntas internas de gh (hostname,
  # protocolo, método): va directo al flujo web del navegador.
  gh auth login --hostname github.com --git-protocol https --web < "$TTY"
  gh auth status &>/dev/null || die "No se pudo autenticar con GitHub."
  log_ok "GitHub autenticado"
fi

# ============================================================
# 3. Verificación de autorización en el equipo (neutro)
# ============================================================

log_step "Autorización"

# Lee team.yaml del repo privado vía API (sin clonar todavía). Si la cuenta no
# tiene acceso al repo, la llamada falla → mismo tratamiento que "no autorizado".
team_yaml_content=""
if team_yaml_content="$(gh api \
      "repos/${OPS_REPO_SLUG}/contents/${TEAM_YAML_PATH}" \
      --jq '.content' 2>/dev/null | base64 --decode 2>/dev/null)"; then
  :
fi

if [ -z "$team_yaml_content" ] || ! printf '%s' "$team_yaml_content" | grep -q "$USER_EMAIL"; then
  log_err "Tu cuenta no está autorizada en el equipo."
  log "  Pide al team_admin que te añada para completar el onboarding."
  exit 1
fi
log_ok "Cuenta autorizada en el equipo"

# ============================================================
# 4. Clonar el repo de configuración
# ============================================================

log_step "Repo de configuración"

mkdir -p "$CODE_DIR"
if [ -d "$OPS_DIR/.git" ]; then
  log_info "Ya existe — actualizando…"
  git -C "$OPS_DIR" pull --ff-only || log_warn "No se pudo hacer fast-forward; continúo con el estado local."
  log_ok "Repo de configuración actualizado"
else
  gh repo clone "$OPS_REPO_SLUG" "$OPS_DIR"
  log_ok "Repo de configuración clonado en $OPS_DIR"
fi

# ============================================================
# 5. Delegar al bootstrap del equipo
# ============================================================

log_step "Bootstrap del equipo"
log_info "Delegando en bootstrap/install.sh (settings, hooks, MCP, skills, memoria, healthcheck)…"

# Le pasamos la terminal real como stdin: bajo `curl | bash` el stdin de este
# script es el pipe, no el tty, y el bootstrap (o sus módulos) podrían necesitar
# input interactivo. Si no hay tty (CI), se ejecuta normal y cada módulo decide.
if [ -e "$TTY" ]; then
  bash "${OPS_DIR}/bootstrap/install.sh" < "$TTY"
else
  bash "${OPS_DIR}/bootstrap/install.sh"
fi

# ============================================================
# 6. Bienvenida
# ============================================================
# La cascada de preferencias personales NO se dispara desde aquí: la maneja la
# primera sesión de Claude vía la instrucción condicional del CLAUDE.md (si
# personal-preferences.md sigue sin rellenar, Claude la ofrece). Así evitamos
# arrancar Claude de forma no-interactiva desde el instalador.

display_name="$(printf '%s' "${USER_EMAIL%%@*}" | sed 's/[._-]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')"

printf '\n%s╔════════════════════════════════════════════════╗%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
printf '%s║   Bienvenido, %-33s║%s\n' "$C_BOLD$C_GREEN" "$display_name" "$C_RESET"
printf '%s╚════════════════════════════════════════════════╝%s\n' "$C_BOLD$C_GREEN" "$C_RESET"
log ""
log "  Tu laptop está lista. Para empezar:"
log ""
log "    1. Abre el workspace en VS Code:"
log "       ${C_DIM}code ${OPS_DIR}/neural-one.code-workspace${C_RESET}"
log ""
log "    2. En la terminal integrada, escribe ${C_BOLD}claude${C_RESET} para tu primera sesión."
log "       Te saludará y te ayudará a configurar tus preferencias."
log ""
