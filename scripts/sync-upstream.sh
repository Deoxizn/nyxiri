#!/usr/bin/env bash
# Rebase Nyxiri's working Bar.qml onto the installed Omarchy bar.
#
# `upstream/` is a pristine copy of the last upstream files we merged. The
# working Bar.qml differs from it only inside NYXIRI-BEGIN/END blocks, so a
# three-way merge is enough: base = old upstream, ours = working, theirs = the
# installed file. BarModel.js is kept unmodified and is simply replaced when
# it matches the old upstream copy.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
src=${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/bar
upstream="$root/upstream"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

die() { printf 'sync-upstream: %s\n' "$*" >&2; exit 1; }

[[ -d $src ]] || die "upstream bar not found at $src"
for file in Bar.qml BarModel.js manifest.json; do
  [[ -f $src/$file ]] || die "missing $src/$file"
done

sha() { sha256sum "$1" | cut -d' ' -f1; }

merge_file() {
  local name=$1
  local work=$root/$name
  local base=$upstream/$name
  local theirs=$tmp/$name
  cp -- "$src/$name" "$theirs"

  if [[ ! -f $base ]]; then
    printf 'sync-upstream: %s has no base copy; installing first copy and leaving %s untouched\n' "$name" "$name"
    cp -- "$theirs" "$base"
    return
  fi

  if cmp -s -- "$work" "$base"; then
    cp -- "$theirs" "$work"
    printf 'sync-upstream: %s replaced (no local changes)\n' "$name"
  elif cmp -s -- "$base" "$theirs"; then
    printf 'sync-upstream: %s unchanged upstream\n' "$name"
  else
    cp -- "$work" "$tmp/ours-$name"
    if git merge-file -q --diff3 "$tmp/ours-$name" "$base" "$theirs"; then
      cp -- "$tmp/ours-$name" "$work"
      printf 'sync-upstream: %s merged cleanly\n' "$name"
    else
      cp -- "$tmp/ours-$name" "$root/$name.rebase"
      die "$name has conflicts; review $name.rebase, then move it over $name"
    fi
  fi

  cp -- "$theirs" "$base"
}

merge_file Bar.qml
merge_file BarModel.js
cp -- "$src/manifest.json" "$upstream/bar-manifest.json"

printf 'sync-upstream: upstream base now Bar.qml %s, BarModel.js %s\n' \
  "$(sha "$src/Bar.qml")" "$(sha "$src/BarModel.js")"
