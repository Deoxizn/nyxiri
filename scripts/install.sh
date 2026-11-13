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
target=${NYXIRI_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/pizza.dirty.nyxiri}
mode=add
bar_repo=${NYXIRI_REPO:-https://github.com/Deoxizn/nyxiri.git}
menu_repo=${NYXIRI_MENU_REPO:-https://github.com/Deoxizn/nyxiri-menu.git}
menu_target=${NYXIRI_MENU_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/pizza.dirty.nyxiri-menu}
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
  --target DIR    install the bar elsewhere (default ~/.config/omarchy/plugins/pizza.dirty.nyxiri)
  --menu-target DIR  install the menu elsewhere (default ~/.config/omarchy/plugins/pizza.dirty.nyxiri-menu)
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

[[ -n $target && $target != "/" && $target != "$HOME" ]] || {
  printf 'install: refusing to replace %s\n' "$target" >&2
  exit 1
}
[[ -n $menu_target && $menu_target != "/" && $menu_target != "$HOME" ]] || {
  printf 'install: refusing to replace %s\n' "$menu_target" >&2
  exit 1
}

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
  git clone -- "$url" "$target"
  printf 'cloned %s -> %s\n' "$url" "$target"
  if (( install_menu )); then
    rm -rf -- "$menu_target"
    git clone -- "$menu_repo" "$menu_target"
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
  cp -- manifest.json Bar.qml BarModel.js Nyxiri.js NyxiriSettings.qml README.md LICENSE "$target/"
  printf 'copied to %s\n' "$target"
  if (( install_menu )); then
    remove_if_installed pizza.dirty.nyxiri-menu "$menu_target"
    add_plugin "$menu_repo"
  fi
fi

printf '\nNext:\n'
printf '  omarchy-shell shell rescanPlugins\n'
printf '  omarchy bar use pizza.dirty.nyxiri\n'
if (( install_menu )); then
  printf '  omarchy bar put pizza.dirty.nyxiri-menu\n'
fi
printf 'or pick Nyxiri under Settings > Plugins in the Omarchy menu.\n'
