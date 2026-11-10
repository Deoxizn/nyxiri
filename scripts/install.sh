#!/usr/bin/env bash
# Install Nyxiri into the user plugin directory. A symlink (the default) is
# what you want while editing this checkout: the shell rescans and reloads
# without a copy step.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${NYXIRI_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/devi.nyxiri}
mode=link

usage() {
  cat <<USAGE
Usage: scripts/install.sh [--link|--copy] [--target DIR]

  --link   symlink this checkout to the plugin directory (default)
  --copy   copy the plugin files instead
  --target install somewhere other than $target
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --link) mode=link; shift ;;
    --copy) mode=copy; shift ;;
    --target) target=${2:?--target needs a directory}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

mkdir -p -- "$(dirname -- "$target")"

[[ -n $target && $target != "/" && $target != "$HOME" ]] || {
  printf 'install: refusing to replace %s\n' "$target" >&2
  exit 1
}

if [[ $mode == link ]]; then
  rm -rf -- "$target"
  ln -s -- "$root" "$target"
  printf 'linked %s -> %s\n' "$root" "$target"
else
  rm -rf -- "$target"
  mkdir -p -- "$target"
  cp -- manifest.json Bar.qml BarModel.js Nyxiri.js NyxiriSettings.qml README.md LICENSE "$target/"
  printf 'copied to %s\n' "$target"
fi

printf '\nNext:\n'
printf '  omarchy-shell shell rescanPlugins\n'
printf '  omarchy bar use devi.nyxiri\n'
printf 'or pick Nyxiri under Settings > Plugins in the Omarchy menu.\n'
