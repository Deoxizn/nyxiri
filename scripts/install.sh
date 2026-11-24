#!/usr/bin/env bash
# Install Nyxiri (bar + menu). Preferred install is Omarchy's own command,
# and this script is just a wrapper around it:
#
#   omarchy plugin add https://github.com/Deoxizn/nyxiri.git --enable
#   omarchy plugin add https://github.com/Deoxizn/nyxiri-menu.git --enable
#
# That clones a real checkout (so `omarchy plugin update` works) and
# validates the manifest, which a hand-rolled install cannot do as well.
# Re-running install removes any existing install first, because
# `plugin add` refuses when the id is already installed.
#
# --link is the live-editing escape hatch: a symlinked install, but note
# Omarchy's validator refuses symlinks inside a plugin folder, so
# `omarchy plugin update` always fails validation (and rolls back) on one.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${NYXIRI_PLUGIN_DIR:-$HOME/.config/hexciri/plugins/pizza.dirty.nyxiri}
mode=add
bar_repo=${NYXIRI_REPO:-https://github.com/Deoxizn/nyxiri.git}
menu_repo=${NYXIRI_MENU_REPO:-https://github.com/Deoxizn/nyxiri-menu.git}
menu_target=${NYXIRI_MENU_PLUGIN_DIR:-$HOME/.config/hexciri/plugins/pizza.dirty.nyxiri-menu}
install_menu=1
yes_flags=()

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--add|--clone|--link|--copy] [--no-menu] [--yes] [--target DIR] [--menu-target DIR]

  --add    omarchy plugin add <url> --enable for bar and menu (default)
  --clone  git clone the repo origin into the plugin directory
  --link   symlink this checkout to the plugin directory (live editing;
           `omarchy plugin update` will fail validation on a symlink)
  --copy   copy the plugin files instead (no .git, so no plugin updates)
  --no-menu  install the bar only, skip the Nyxiri menu
  --yes    pass --yes through to omarchy plugin add/remove (non-interactive)
  --target DIR    install the bar elsewhere (default ~/.config/hexciri/plugins/pizza.dirty.nyxiri)
  --menu-target DIR  install the menu elsewhere (default ~/.config/hexciri/plugins/pizza.dirty.nyxiri-menu)
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --add) mode=add; shift ;;
    --clone) mode=clone; shift ;;
    --link) mode=link; shift ;;
    --copy) mode=copy; shift ;;
    --no-menu) install_menu=0; shift ;;
    --yes) yes_flags=(--yes); shift ;;
    --target) target=${2:?--target needs a directory}; shift 2 ;;
    --menu-target) menu_target=${2:?--menu-target needs a directory}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

mkdir -p -- "$(dirname -- "$target")" "$(dirname -- "$menu_target")"

plugins_root=${HOME%/}/.config/hexciri/plugins

# --target must stay inside the Hexciri plugins tree: anything outside it
# (including $HOME itself or a path smuggled out via ..) is refused, since
# every mode below does rm -rf on the target first.
validate_target() {
  local dir="$1"
  local norm=${dir%/}
  [[ -n $norm ]] || {
    printf 'install: refusing to replace %s\n' "$dir" >&2
    exit 1
  }
  case $norm in
    *..*)
      printf 'install: refusing target with .. component: %s\n' "$dir" >&2
      exit 1
      ;;
  esac
  case $norm in
    "$plugins_root"/*)
      ;;
    *)
      printf 'install: target must be under %s: %s\n' "$plugins_root" "$dir" >&2
      exit 1
      ;;
  esac
}

validate_target "$target"
validate_target "$menu_target"

# plugin add refuses when the id is already installed, so clear the way
# first. plugin remove disables it and unlinks/removes the old directory.
remove_if_installed() {
  local id="$1" dir="$2"
  if [[ -e $dir || -L $dir ]]; then
    omarchy plugin remove "$id" "${yes_flags[@]}"
  fi
}

add_plugin() {
  local url="$1"
  omarchy plugin add "$url" --enable "${yes_flags[@]}"
}

# Clone with the transport locked down: only https and ssh are allowed,
# so a hostile origin URL (or a NYXIRI_*_REPO env var) cannot smuggle in
# an ext::, file:, or other protocol handler. fsmonitor is off so the
# clone cannot invoke an external watcher either.
clone_repo() {
  local url="$1" dir="$2"
  GIT_ALLOW_PROTOCOL=https:ssh git -c protocol.allow=https:ssh \
    -c core.fsmonitor=false clone -- "$url" "$dir"
}

if [[ $mode == add ]]; then
  command -v omarchy >/dev/null 2>&1 || {
    printf 'install: omarchy is not on PATH; use --clone, --link, or --copy instead\n' >&2
    exit 1
  }
  remove_if_installed pizza.dirty.nyxiri "$target"
  add_plugin "$bar_repo"
  if (( install_menu )); then
    remove_if_installed pizza.dirty.nyxiri-menu "$menu_target"
    add_plugin "$menu_repo"
  fi
elif [[ $mode == clone ]]; then
  url=$(git -C "$root" config --get remote.origin.url || true)
  [[ -n $url ]] || {
    printf 'install: cannot determine the repo origin URL; use --link, --copy, or omarchy plugin add <url>\n' >&2
    exit 1
  }
  rm -rf -- "$target"
  clone_repo "$url" "$target"
  printf 'cloned %s -> %s\n' "$url" "$target"
  if (( install_menu )); then
    rm -rf -- "$menu_target"
    clone_repo "$menu_repo" "$menu_target"
    printf 'cloned %s -> %s\n' "$menu_repo" "$menu_target"
  fi
elif [[ $mode == link ]]; then
  rm -rf -- "$target"
  ln -s -- "$root" "$target"
  printf 'linked %s -> %s\n' "$root" "$target"
  # No menu checkout lives in this repo, so the menu still goes through
  # plugin add even in link mode.
  if (( install_menu )); then
    remove_if_installed pizza.dirty.nyxiri-menu "$menu_target"
    add_plugin "$menu_repo"
  fi
else
  rm -rf -- "$target"
  mkdir -p -- "$target"
  cp -- manifest.json Bar.qml BarModel.js Nyxiri.js NyxiriSettingsWindow.qml README.md LICENSE "$target/"
  printf 'copied to %s\n' "$target"
  if (( install_menu )); then
    remove_if_installed pizza.dirty.nyxiri-menu "$menu_target"
    add_plugin "$menu_repo"
  fi
fi

printf '\nNext:\n'
printf '  hexciri-shell shell rescanPlugins\n'
printf '  omarchy bar use pizza.dirty.nyxiri\n'
if (( install_menu )); then
  printf '  omarchy bar put pizza.dirty.nyxiri-menu\n'
fi
printf 'or pick Nyxiri under Settings > Plugins in the Omarchy menu.\n'
