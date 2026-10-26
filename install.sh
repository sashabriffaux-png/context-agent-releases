#!/usr/bin/env bash
# Installe ou met à jour « Agent de contexte » sur ce Mac.
#   curl -fsSL https://raw.githubusercontent.com/sashabriffaux-png/context-agent-releases/main/install.sh | bash
# Les données (réglages, historique, base de connaissances) ne sont jamais touchées.
# Pour les tests : AGENT_RELEASES_URL (adresse de l'API des versions, file:// accepté), AGENT_INSTALL_DIR.
#
# Tout se passe dans main(), appelée à la toute dernière ligne : si le téléchargement du script
# est coupé, bash ne lit qu'une définition de fonction incomplète et ne fait rien.
set -euo pipefail

APP_NAME="Agent de contexte"
BUNDLE_ID="app.contextagent.mac"
REPO="sashabriffaux-png/context-agent-releases"
RAW="https://raw.githubusercontent.com/${REPO}/main"

# Remplis pendant l'installation ; lus par cleanup() quoi qu'il arrive.
TMP_DIR=""
TARGET=""
BACKUP=""

say() { printf '%s\n' "$*"; }
fail() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}

# HTTPS seulement ; file:// n'est permis que pour les tests (AGENT_RELEASES_URL).
fetch() {
  if [ -n "${AGENT_RELEASES_URL:-}" ]; then
    curl -fsSL --retry 2 "$@"
  else
    curl -fsSL --proto '=https' --tlsv1.2 --retry 2 "$@"
  fi
}

# L'app elle-même (pas l'hôte de Chrome, qui lance le même exécutable avec un script en argument).
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

# Sortie, normale ou non : l'ancienne app revient si la nouvelle n'est pas en place, sinon elle part.
cleanup() {
  if [ -n "$BACKUP" ] && [ -e "$BACKUP" ]; then
    if [ -n "$TARGET" ] && [ ! -e "$TARGET" ]; then
      mv "$BACKUP" "$TARGET" || true
    else
      rm -rf "$BACKUP" || true
    fi
  fi
  if [ -n "$TMP_DIR" ]; then rm -rf "$TMP_DIR"; fi
}

check_system() {
  [ "$(uname -s)" = "Darwin" ] || fail "ce script ne marche que sur un Mac."
  local macos major
  macos="$(sw_vers -productVersion)"
  major="${macos%%.*}"
  case "$major" in
    '' | *[!0-9]*) fail "version de macOS illisible : ${macos}." ;;
  esac
  [ "$major" -ge 14 ] || fail "macOS ${macos} : il faut macOS 14 (Sonoma) ou plus récent."
}

# arm64 ou x64 ; un Terminal sous Rosetta sur un Mac Apple prend quand même arm64.
detect_arch() {
  local machine
  machine="$(uname -m)"
  if [ "$machine" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    machine="arm64"
  fi
  case "$machine" in
    arm64) echo "arm64" ;;
    x86_64) echo "x64" ;;
    *) fail "processeur non pris en charge : ${machine}." ;;
  esac
}

main() {
  local api install_dir arch urls zip_url sums_url zip_name expected actual new_app user_apps dest_dir
  api="${AGENT_RELEASES_URL:-https://api.github.com/repos/${REPO}}"
  install_dir="${AGENT_INSTALL_DIR:-/Applications}"

  check_system
  arch="$(detect_arch)"

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  # Dernière version publiée.
  say "Recherche de la dernière version…"
  fetch -H "Accept: application/vnd.github+json" "${api}/releases/latest" -o "${TMP_DIR}/release.json" ||
    fail "impossible de joindre GitHub. Vérifie ta connexion, puis relance la commande."
  urls="$(grep -oE '"browser_download_url": *"[^"]+"' "${TMP_DIR}/release.json" | sed -E 's/^"browser_download_url": *"([^"]+)"$/\1/' || true)"
  zip_url="$(printf '%s\n' "$urls" | grep -E -- "-mac-${arch}\.zip\$" | head -n 1 || true)"
  sums_url="$(printf '%s\n' "$urls" | grep -E '/SHA256SUMS$' | head -n 1 || true)"
  [ -n "$zip_url" ] || fail "aucune version pour ce Mac (${arch}) dans la dernière publication."
  [ -n "$sums_url" ] || fail "la dernière publication n'a pas de fichier SHA256SUMS."
  zip_name="${zip_url##*/}"

  say "Téléchargement de ${zip_name}…"
  fetch "$zip_url" -o "${TMP_DIR}/${zip_name}" || fail "téléchargement impossible, relance la commande."
  fetch "$sums_url" -o "${TMP_DIR}/SHA256SUMS" || fail "téléchargement impossible, relance la commande."

  # Somme de contrôle : le fichier téléchargé est intact, identique à celui publié.
  expected="$(awk -v f="$zip_name" '$2 == f || $2 == "*" f { print $1 }' "${TMP_DIR}/SHA256SUMS" | head -n 1)"
  actual="$(shasum -a 256 "${TMP_DIR}/${zip_name}" | awk '{ print $1 }')"
  [ -n "$expected" ] || fail "${zip_name} absent de SHA256SUMS."
  [ "$expected" = "$actual" ] || fail "somme de contrôle incorrecte pour ${zip_name} : fichier abîmé ou modifié. Rien n'a été installé."

  mkdir -p "${TMP_DIR}/app"
  ditto -x -k "${TMP_DIR}/${zip_name}" "${TMP_DIR}/app" || fail "archive illisible."
  new_app="${TMP_DIR}/app/${APP_NAME}.app"
  [ -d "$new_app" ] || fail "l'archive ne contient pas ${APP_NAME}.app."

  # Où installer : là où l'app est déjà, sinon Applications, sinon ~/Applications (sans droits admin).
  user_apps="${HOME}/Applications"
  if [ -d "${install_dir}/${APP_NAME}.app" ]; then
    dest_dir="$install_dir"
  elif [ -d "${user_apps}/${APP_NAME}.app" ]; then
    dest_dir="$user_apps"
  elif [ -d "$install_dir" ] && [ -w "$install_dir" ]; then
    dest_dir="$install_dir"
  else
    dest_dir="$user_apps"
  fi
  if [ -e "$dest_dir" ] && [ ! -w "$dest_dir" ]; then
    if [ -d "${dest_dir}/${APP_NAME}.app" ]; then
      say "Ton app actuelle est dans ${dest_dir}, que tu ne peux pas modifier sans droits d'administrateur."
      say "La nouvelle version va dans ${user_apps} : tu auras deux copies."
      say "Supprime l'ancienne (${dest_dir}/${APP_NAME}.app) pour ne pas les confondre."
    fi
    dest_dir="$user_apps"
  fi
  mkdir -p "$dest_dir"
  TARGET="${dest_dir}/${APP_NAME}.app"

  quit_app

  # Remplacement : l'ancienne app attend à côté (même disque) jusqu'à ce que la nouvelle soit en place.
  BACKUP="${dest_dir}/.${APP_NAME}.app.old"
  rm -rf "$BACKUP"
  if [ -e "$TARGET" ]; then
    mv "$TARGET" "$BACKUP" || fail "impossible de remplacer ${TARGET}."
  fi
  if ! ditto "$new_app" "$TARGET"; then
    rm -rf "$TARGET"
    if [ -e "$BACKUP" ]; then mv "$BACKUP" "$TARGET"; fi
    fail "impossible d'écrire ${TARGET}. L'ancienne version est restée en place."
  fi
  rm -rf "$BACKUP"
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

  say ""
  say "${APP_NAME} est installé : ${TARGET}"
  open "$TARGET"
  say ""
  say "La suite se passe dans l'app, la visite guidée te montre les réglages :"
  say "  1. autorise l'enregistrement de l'écran et l'accessibilité quand macOS le demande ;"
  say "  2. colle la clé que tu as reçue ;"
  say "  3. charge l'extension Chrome en suivant le guide pas à pas (le lien avec l'app s'installe tout seul)."
  say ""
  say "Après une mise à jour, si un réglage d'autorisation est activé mais que l'app dit le contraire :"
  say "dans Réglages Système, retire l'app de la liste avec « – », puis ajoute-la de nouveau avec « + »."
  say ""
  say "Mettre à jour : relance la même commande."
  say "Tout enlever : curl -fsSL ${RAW}/uninstall.sh | bash"
}

main "$@"
