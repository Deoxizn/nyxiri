#!/usr/bin/env bash
# Nyxiri all-in-one installer: the bar and its bar widgets in one command.
# Core plugins are always installed; the cat widgets (cpurr and Bongo Cat)
# are opt-in with --with-cats. Wallcraft is deliberately NOT included: it
# is a background service whose settings work without the bar, so it stays
# an independent install.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/main/scripts/install-all.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/main/scripts/install-all.sh) --with-cats
#
# Fish has no process substitution, so wrap it:
#   bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/main/scripts/install-all.sh) --with-cats'
#
# Already-installed plugins are skipped, never removed or re-added, so
# re-running the installer is safe. Widgets already on the bar are left
# where they are (`omarchy bar put` only adds a widget that is not on
# the bar yet). Everything goes through `omarchy plugin add --enable
# --yes`, so no prompts: the installer trusts Deoxizn's repos, and
# `plugin add` still validates each manifest before installing.
set -euo pipefail

PLUGINS_DIR=${HOME}/.config/omarchy/plugins
with_cats=0

usage() {
  cat <<'USAGE'
Usage: scripts/install-all.sh [--with-cats]

  --with-cats  also install the cat widgets (cpurr and Bongo Cat)
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --with-cats) with_cats=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install-all: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

command -v omarchy >/dev/null 2>&1 || {
  printf 'install-all: omarchy is not on PATH\n' >&2
  exit 1
}

# plugin add refuses when the id is already installed, so skip those.
add_plugin() {
  local id="$1" url="$2"
  if [[ -e $PLUGINS_DIR/$id || -L $PLUGINS_DIR/$id ]]; then
    printf '%s: already installed, skipping\n' "$id"
    return 0
  fi
  printf '%s: installing from %s\n' "$id" "$url"
  omarchy plugin add "$url" --enable --yes
}

# Core: the bar and the widgets that belong to it.
add_plugin devi.nyxiri https://github.com/Deoxizn/nyxiri.git
add_plugin devi.nyxiri-menu https://github.com/Deoxizn/nyxiri-menu.git
add_plugin devi.nyxiri-workspaces https://github.com/Deoxizn/nyxiri-workspaces.git
add_plugin deoxizn.clock https://github.com/Deoxizn/omarchy-clock.git
add_plugin devi.weather https://github.com/Deoxizn/omarchy-weather.git
add_plugin devi.arch-updates https://github.com/Deoxizn/Arch-Updates.git

# Optional: the cat widgets. Fun, not core.
if (( with_cats )); then
  add_plugin deoxizn.cpurr https://github.com/Deoxizn/omarchy-cpurr.git
  add_plugin deoxizn.bongocat https://github.com/Deoxizn/omarchy-bongocat.git
fi

omarchy-shell shell rescanPlugins >/dev/null || true
omarchy bar use devi.nyxiri

# Place the widgets. Menu first, then workspaces, so the trigger glyph
# sits before the workspace numbers on the left. A put that fails (the
# shell was not ready, or the plugin is installed but disabled) prints a
# note instead of failing the install; enable it in the settings card
# and put it on the bar from there.
put() {
  omarchy bar put "$1" --section "$2" ||
    printf '%s: could not put on the bar; enable it in the settings card and add it from there\n' "$1"
}
put devi.nyxiri-menu left
put devi.nyxiri-workspaces left
put deoxizn.clock centerEnd
put devi.weather centerEnd
put devi.arch-updates right
if (( with_cats )); then
  put deoxizn.cpurr center
  put deoxizn.bongocat center
fi

omarchy restart shell

printf '\nNyxiri installed.\n'
printf 'Wallcraft is a separate install (it works without the bar):\n'
printf '  omarchy plugin add https://github.com/Deoxizn/wallcraft.git --enable\n'
