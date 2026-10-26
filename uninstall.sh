#!/usr/bin/env bash
# Enlève « Agent de contexte » de ce Mac : l'app et le lien avec Chrome, puis, si tu le confirmes,
# tes données et ta base de connaissances.
#   curl -fsSL https://raw.githubusercontent.com/sashabriffaux-png/context-agent-releases/main/uninstall.sh | bash
#   ... | bash -s -- --yes     (sans question : supprime aussi les données)
# Pour les tests : AGENT_INSTALL_DIR, AGENT_TTY (d'où lire les réponses).
#
# Tout se passe dans main(), appelée à la toute dernière ligne : si le téléchargement du script
# est coupé, bash ne lit qu'une définition de fonction incomplète et ne fait rien.
set -euo pipefail

APP_NAME="Agent de contexte"
BUNDLE_ID="app.contextagent.mac"
# Posé par l'app dans une base qu'elle a créée elle-même (app/main/knowledge/store.ts).
KB_MARKER=".agent-knowledge"
YES=0

say() { printf '%s\n' "$*"; }
fail() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}

# Réponse lue au clavier même quand le script arrive par « curl | bash ». Sans clavier : non.
confirm() {
  [ "$YES" = 1 ] && return 0
  local answer=""
  printf '%s [o/N] ' "$1" >&2
  { read -r answer <"${AGENT_TTY:-/dev/tty}"; } 2>/dev/null || answer=""
  case "$answer" in
    o | O | oui | Oui | OUI | y | Y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

APP_PATTERN="/${APP_NAME}\.app/Contents/MacOS/${APP_NAME}\$"
app_running() { pgrep -f "$APP_PATTERN" >/dev/null 2>&1; }
quit_app() {
  app_running || return 0
  say "Fermeture de ${APP_NAME}…"
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  local _
  for _ in $(seq 1 20); do
    app_running || return 0
    sleep 0.5
  done
  pkill -f "$APP_PATTERN" >/dev/null 2>&1 || true
  sleep 1
}

# Chemin réel d'un dossier existant (liens, « .. » et « // » résolus) ; échoue sinon.
real_dir() { (cd "$1" 2>/dev/null && pwd -P); }

# La base n'est effacée que si elle est strictement sous le dossier personnel et marquée par l'app.
kb_deletable() {
  local home_real="$1" kb_real
  kb_real="$(real_dir "$2")" || return 1
  case "$kb_real" in
    "${home_real}"/?*) ;;
    *) return 1 ;;
  esac
  [ -f "${kb_real}/${KB_MARKER}" ]
}

main() {
  local arg install_dir data_dir host_manifest home_real kb_dir stored dir removed
  for arg in "$@"; do
    case "$arg" in
      --yes | -y) YES=1 ;;
      *) fail "option inconnue : ${arg} (seule --yes existe)." ;;
    esac
  done
  if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
    fail "dossier personnel (HOME) vide ou égal à / : rien n'a été supprimé."
  fi
  home_real="$(real_dir "$HOME")" || fail "dossier personnel introuvable : ${HOME}."
  [ "$home_real" != "/" ] || fail "dossier personnel égal à / : rien n'a été supprimé."

  install_dir="${AGENT_INSTALL_DIR:-/Applications}"
  data_dir="${home_real}/Library/Application Support/context-agent"
  host_manifest="${home_real}/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.naboo.context_agent.json"

  quit_app

  # Base de connaissances : celle des réglages si on peut la lire (app fermée), sinon celle par défaut.
  kb_dir="${home_real}/agent-knowledge"
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "${data_dir}/agent.sqlite" ]; then
    stored="$(sqlite3 "${data_dir}/agent.sqlite" \
      "select json_extract(value, '\$.kbPath') from settings where key = 'settings'" 2>/dev/null || true)"
    if [ -n "$stored" ]; then kb_dir="$stored"; fi
  fi

  removed=0
  for dir in "$install_dir" "${home_real}/Applications"; do
    if [ -d "${dir}/${APP_NAME}.app" ]; then
      rm -rf "${dir:?}/${APP_NAME}.app"
      say "App supprimée : ${dir}/${APP_NAME}.app"
      removed=1
    fi
  done
  [ "$removed" = 1 ] || say "App introuvable dans ${install_dir} ni dans ~/Applications."

  if [ -f "$host_manifest" ]; then
    rm -f "$host_manifest"
    say "Lien avec Chrome supprimé."
  fi

  if [ -d "$data_dir" ]; then
    if confirm "Supprimer aussi tes réglages et ton historique (${data_dir}) ?"; then
      rm -rf "$data_dir"
      say "Données supprimées."
    else
      say "Données gardées : ${data_dir}"
    fi
  fi

  if [ -d "$kb_dir" ]; then
    if ! kb_deletable "$home_real" "$kb_dir"; then
      say "Base de connaissances gardée (dossier que l'app n'a pas créé) : ${kb_dir}"
      say "Supprime-la toi-même si tu n'en as plus besoin."
    elif confirm "Supprimer aussi ta base de connaissances (${kb_dir}) ?"; then
      rm -rf "$(real_dir "$kb_dir")"
      say "Base de connaissances supprimée."
    else
      say "Base de connaissances gardée : ${kb_dir}"
    fi
  fi

  say ""
  say "Dernière étape : dans Chrome, ouvre chrome://extensions et clique sur « Supprimer » sous ${APP_NAME}."
}

main "$@"
