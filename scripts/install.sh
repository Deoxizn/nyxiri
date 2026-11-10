#!/usr/bin/env bash
# Install Nyxiri into the user plugin directory. The default is a real git
# clone of the repo's origin: a proper checkout under
# ~/.config/omarchy/plugins/devi.nyxiri, so `omarchy plugin update` works.
# A symlinked install (--link) is convenient while editing, but Omarchy's
# plugin validator refuses symlinks inside a plugin folder, so `omarchy
# plugin update` always fails validation (and rolls back) on one.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${NYXIRI_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/devi.nyxiri}
mode=clone

usage() {
  cat <<USAGE
Usage: scripts/install.sh [--clone|--link|--copy] [--target DIR]

  --clone  git clone the repo origin into the plugin directory (default)
  --link   symlink this checkout to the plugin directory (live editing;
           `omarchy plugin update` will fail validation on a symlink)
  --copy   copy the plugin files instead (no .git, so no plugin updates)
  --target install somewhere other than $target
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --clone) mode=clone; shift ;;
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

printf '\nNext:\n'
printf '  omarchy-shell shell rescanPlugins\n'
printf '  omarchy bar use devi.nyxiri\n'
printf 'or pick Nyxiri under Settings > Plugins in the Omarchy menu.\n'
