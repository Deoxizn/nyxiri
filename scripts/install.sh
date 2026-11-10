#!/usr/bin/env bash
# Install Nyxiri (bar + menu) into the user plugin directory. The default
# is a real git clone of each repo's origin: proper checkouts under
# ~/.config/omarchy/plugins/devi.nyxiri and devi.nyxiri-menu, so
# `omarchy plugin update` works on both. Pass --no-menu for the bar only.
# A symlinked install (--link) is convenient while editing, but Omarchy's
# plugin validator refuses symlinks inside a plugin folder, so `omarchy
# plugin update` always fails validation (and rolls back) on one.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${NYXIRI_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/devi.nyxiri}
mode=clone
menu_repo=${NYXIRI_MENU_REPO:-https://github.com/Deoxizn/nyxiri-menu.git}
menu_target=${NYXIRI_MENU_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/devi.nyxiri-menu}
install_menu=1

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--clone|--link|--copy] [--no-menu] [--target DIR] [--menu-target DIR]

  --clone  git clone the repo origin into the plugin directory (default)
  --link   symlink this checkout to the plugin directory (live editing;
           `omarchy plugin update` will fail validation on a symlink)
  --copy   copy the plugin files instead (no .git, so no plugin updates)
  --no-menu  install the bar only, skip the Nyxiri menu
  --target install the bar somewhere other than $target
  --menu-target install the menu somewhere other than $menu_target
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --clone) mode=clone; shift ;;
    --link) mode=link; shift ;;
    --copy) mode=copy; shift ;;
    --no-menu) install_menu=0; shift ;;
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

if [[ $mode == clone ]]; then
  url=$(git -C "$root" config --get remote.origin.url || true)
  [[ -n $url ]] || {
    printf 'install: cannot determine the repo origin URL; use --link, --copy, or omarchy plugin add <url>\n' >&2
    exit 1
  }
  rm -rf -- "$target"
  git clone -- "$url" "$target"
  printf 'cloned %s -> %s\n' "$url" "$target"
elif [[ $mode == link ]]; then
  rm -rf -- "$target"
  ln -s -- "$root" "$target"
  printf 'linked %s -> %s\n' "$root" "$target"
else
  rm -rf -- "$target"
  mkdir -p -- "$target"
  cp -- manifest.json Bar.qml BarModel.js Nyxiri.js NyxiriSettings.qml README.md LICENSE "$target/"
  printf 'copied to %s\n' "$target"
fi

# The menu is part of Nyxiri: same install, same update story. It is always
# a real clone (there is no menu checkout in this repo to link or copy),
# unless --no-menu was passed.
if (( install_menu )); then
  rm -rf -- "$menu_target"
  git clone -- "$menu_repo" "$menu_target"
  printf 'cloned %s -> %s\n' "$menu_repo" "$menu_target"
fi

printf '\nNext:\n'
printf '  omarchy-shell shell rescanPlugins\n'
printf '  omarchy bar use devi.nyxiri\n'
if (( install_menu )); then
  printf '  omarchy plugin enable devi.nyxiri-menu\n'
  printf '  omarchy bar put devi.nyxiri-menu\n'
fi
printf 'or pick Nyxiri under Settings > Plugins in the Omarchy menu.\n'
