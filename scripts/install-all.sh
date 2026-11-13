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

# Rename plugins installed under the old devi.*/deoxizn.* ids to the new
# pizza.dirty.* ids, and carry their settings across. No reinstall: the
# plugin dirs are renamed in place, the shell.json layout entries are
# re-keyed (a string entry, or an object's "id" field, keeping every
# other setting), bar.id is updated, and the clock's config/cache dirs
# move with it. The bar's own settings live under bar.nyxiri, which is
# not id-derived, so they are untouched. Anything already under a new
# id is left alone, and a rename never clobbers an existing new-id dir.
migrate_ids() {
  local old new
  migrate_one() {
    old="$1" new="$2"
    if [[ -e $PLUGINS_DIR/$old || -L $PLUGINS_DIR/$old ]]; then
      if [[ -e $PLUGINS_DIR/$new || -L $PLUGINS_DIR/$new ]]; then
        printf '%s: both old and new ids installed, leaving %s in place\n' "$old" "$old"
      else
        mv -- "$PLUGINS_DIR/$old" "$PLUGINS_DIR/$new"
        printf '%s: renamed to %s\n' "$old" "$new"
      fi
    fi
  }
  migrate_one devi.nyxiri pizza.dirty.nyxiri
  migrate_one devi.nyxiri-menu pizza.dirty.nyxiri-menu
  migrate_one devi.nyxiri-workspaces pizza.dirty.nyxiri-workspaces
  migrate_one deoxizn.clock pizza.dirty.clock
  migrate_one devi.weather pizza.dirty.weather
  migrate_one devi.arch-updates pizza.dirty.arch-updates
  migrate_one deoxizn.cpurr pizza.dirty.cpurr
  migrate_one deoxizn.bongocat pizza.dirty.bongocat
  migrate_one devi.wallcraft pizza.dirty.wallcraft

  # The clock keeps its calendars under ~/.config/deoxizn.clock/ and its
  # cache under ~/.cache/deoxizn.clock/; move both to the new id.
  if [[ -e $HOME/.config/deoxizn.clock && ! -e $HOME/.config/pizza.dirty.clock ]]; then
    mv -- "$HOME/.config/deoxizn.clock" "$HOME/.config/pizza.dirty.clock"
    printf 'deoxizn.clock config: moved to ~/.config/pizza.dirty.clock\n'
  fi
  if [[ -e $HOME/.cache/deoxizn.clock && ! -e $HOME/.cache/pizza.dirty.clock ]]; then
    mv -- "$HOME/.cache/deoxizn.clock" "$HOME/.cache/pizza.dirty.clock"
    printf 'deoxizn.clock cache: moved to ~/.cache/pizza.dirty.clock\n'
  fi

  # Re-key the shell.json layout entries and bar.id. A layout entry is a
  # plain id string or an object with an "id" field; either way only the
  # id changes, the inline settings stay. If shell.json cannot be parsed
  # (it is plain JSON, but be safe), warn and leave it alone rather than
  # failing the install; the widgets fall back to defaults in that case.
  python3 - "$HOME/.config/omarchy/shell.json" <<'PYEOF' || printf 'install-all: could not re-key shell.json, widget settings may reset to defaults\n'
import json, sys
path = sys.argv[1]
mapping = {
    "devi.nyxiri": "pizza.dirty.nyxiri",
    "devi.nyxiri-menu": "pizza.dirty.nyxiri-menu",
    "devi.nyxiri-workspaces": "pizza.dirty.nyxiri-workspaces",
    "deoxizn.clock": "pizza.dirty.clock",
    "devi.weather": "pizza.dirty.weather",
    "devi.arch-updates": "pizza.dirty.arch-updates",
    "deoxizn.cpurr": "pizza.dirty.cpurr",
    "deoxizn.bongocat": "pizza.dirty.bongocat",
    "devi.wallcraft": "pizza.dirty.wallcraft",
}
try:
    with open(path) as f:
        data = json.load(f)
except (OSError, ValueError):
    sys.exit(1)
bar = data.get("bar") or {}
bar_changed = False
if bar.get("id") in mapping:
    bar["id"] = mapping[bar["id"]]
    bar_changed = True
layout = bar.get("layout") or {}
changed = False
for entries in layout.values():
    if not isinstance(entries, list):
        continue
    for i, entry in enumerate(entries):
        if isinstance(entry, str) and entry in mapping:
            entries[i] = mapping[entry]
            changed = True
        elif isinstance(entry, dict) and entry.get("id") in mapping:
            entry["id"] = mapping[entry["id"]]
            changed = True
if changed or bar_changed:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("shell.json: re-keyed layout entries to pizza.dirty.*")
PYEOF
}

migrate_ids

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
add_plugin pizza.dirty.nyxiri https://github.com/Deoxizn/nyxiri.git
add_plugin pizza.dirty.nyxiri-menu https://github.com/Deoxizn/nyxiri-menu.git
add_plugin pizza.dirty.nyxiri-workspaces https://github.com/Deoxizn/nyxiri-workspaces.git
add_plugin pizza.dirty.clock https://github.com/Deoxizn/omarchy-clock.git
add_plugin pizza.dirty.weather https://github.com/Deoxizn/omarchy-weather.git
add_plugin pizza.dirty.arch-updates https://github.com/Deoxizn/Arch-Updates.git

# Optional: the cat widgets. Fun, not core.
if (( with_cats )); then
  add_plugin pizza.dirty.cpurr https://github.com/Deoxizn/omarchy-cpurr.git
  add_plugin pizza.dirty.bongocat https://github.com/Deoxizn/omarchy-bongocat.git
fi

omarchy-shell shell rescanPlugins >/dev/null || true
omarchy bar use pizza.dirty.nyxiri

# Place the widgets. Menu first, then workspaces, so the trigger glyph
# sits before the workspace numbers on the left. A put that fails (the
# shell was not ready, or the plugin is installed but disabled) prints a
# note instead of failing the install; enable it in the settings card
# and put it on the bar from there.
put() {
  omarchy bar put "$1" --section "$2" ||
    printf '%s: could not put on the bar; enable it in the settings card and add it from there\n' "$1"
}
put pizza.dirty.nyxiri-menu left
put pizza.dirty.nyxiri-workspaces left
put pizza.dirty.clock centerEnd
put pizza.dirty.weather centerEnd
put pizza.dirty.arch-updates right
if (( with_cats )); then
  put pizza.dirty.cpurr center
  put pizza.dirty.bongocat center
fi

omarchy restart shell

printf '\nNyxiri installed.\n'
printf 'Wallcraft is a separate install (it works without the bar):\n'
printf '  omarchy plugin add https://github.com/Deoxizn/wallcraft.git --enable\n'
