#!/usr/bin/env bash
# Nyxiri all-in-one installer: the bar and its bar widgets in one command.
# Core plugins are always installed; the cat widgets (cpurr and Bongo Cat)
# are opt-in with --with-cats.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/nyx/scripts/install-all.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/nyx/scripts/install-all.sh) --with-cats
#
# Fish has no process substitution, so wrap it:
#   bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/Deoxizn/nyxiri/nyx/scripts/install-all.sh) --with-cats'
#
# Hexciri only (nyx branch). hexciri plugin add has NO --branch flag,
# so nyx installs go via git clone --branch nyx + hexciri plugin enable.
#
# Already-installed plugins are skipped, never removed or re-added, so
# re-running the installer is safe. Widgets already on the bar are left
# where they are (`hexciri bar put` only adds a widget that is not on
# the bar yet). Everything goes through `git clone --branch nyx` +
# `hexciri-plugin-validate` + `hexciri plugin enable`, so no prompts:
# the installer trusts Deoxizn's repos, and validate still checks each
# manifest before installing.
set -euo pipefail

PLUGINS_DIR=${HOME}/.config/hexciri/plugins
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

command -v hexciri >/dev/null 2>&1 || {
  printf 'install-all: hexciri is not on PATH\n' >&2
  exit 1
}
_validate="/usr/share/hexciri/bin/hexciri-plugin-validate"
[ -x "$_validate" ] || _validate="hexciri-plugin-validate"

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

  # The catalog reads manifest.id, not the directory name, so a renamed
  # dir alone still shows up under the old id. Update the id inside each
  # installed manifest too, so the catalog (and the shell) sees the new
  # id. This also covers a re-run after the dirs were already renamed.
  fix_manifest_id() {
    local old="$1" new="$2" manifest
    # Assign manifest on its own line: bash expands every word in a
    # `local` statement before assigning any of them, so $new in the
    # same line would read the outer (stale) value.
    manifest="$PLUGINS_DIR/$new/manifest.json"
    [[ -f $manifest ]] || return 0
    if [[ $(jq -r '.id // ""' "$manifest") == "$old" ]]; then
      jq --arg id "$new" '.id = $id' "$manifest" > "$manifest.tmp" && mv -- "$manifest.tmp" "$manifest"
      printf '%s: manifest id updated to %s\n' "$old" "$new"
    fi
  }
  fix_manifest_id devi.nyxiri pizza.dirty.nyxiri
  fix_manifest_id devi.nyxiri-menu pizza.dirty.nyxiri-menu
  fix_manifest_id devi.nyxiri-workspaces pizza.dirty.nyxiri-workspaces
  fix_manifest_id deoxizn.clock pizza.dirty.clock
  fix_manifest_id devi.weather pizza.dirty.weather
  fix_manifest_id devi.arch-updates pizza.dirty.arch-updates
  fix_manifest_id deoxizn.cpurr pizza.dirty.cpurr
  fix_manifest_id deoxizn.bongocat pizza.dirty.bongocat

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
  python3 - "$HOME/.config/hexciri/shell.json" <<'PYEOF' || printf 'install-all: could not re-key shell.json, widget settings may reset to defaults\n'
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
  printf '%s: installing from %s (nyx)\n' "$id" "$url"
  git clone --branch nyx -- "$url" "$PLUGINS_DIR/$id" || { printf '%s: git clone failed\n' "$id" >&2; return 1; }
  "$_validate" "$PLUGINS_DIR/$id" || { printf '%s: manifest validation failed\n' "$id" >&2; rm -rf "$PLUGINS_DIR/$id"; return 1; }
  hexciri plugin enable "$id" || printf '%s: cloned but not enabled (shell not running, enable happens on first shell start)\n' "$id"
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

hexciri-shell shell rescanPlugins >/dev/null || true

# Restart the shell now, before the bar use and the puts: the shell only
# learns the new ids by rescanning, and a restart guarantees it. The
# puts retry while the shell comes back up.
hexciri restart shell
hexciri bar use pizza.dirty.nyxiri

# Place the widgets. Menu first, then workspaces, so the trigger glyph
# sits before the workspace numbers on the left. A put that fails (the
# shell was not ready, or the plugin is installed but disabled) prints a
# note instead of failing the install; enable it in the settings card
# and put it on the bar from there.
put() {
  hexciri bar put "$1" --section "$2" ||
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

# The stock workspaces widget stays in the layout unless it is disabled,
# so a fresh install shows two workspaces bars: the stock one and this
# one. Disable it (do not remove it) so it can be re-enabled later from
# the settings card or with `hexciri plugin enable hexciri.workspaces`.
hexciri plugin disable hexciri.workspaces ||
  printf 'install-all: could not disable the stock workspaces widget; disable it in the settings card (Plugins tab)\n'

# Classic workspaces need their Hyprland loader wired up, or the Classic
# toggle in the settings card has nothing to switch to. The setup script
# is idempotent and a no-op when the loader is already in place, so it is
# safe on a re-run. It installs the two workspaces files and the loader
# block, then reloads Hyprland.
classic_setup="$PLUGINS_DIR/pizza.dirty.nyxiri-workspaces/scripts/setup-classic.sh"
if [[ -f $classic_setup ]]; then
  bash "$classic_setup" || printf 'install-all: classic workspaces setup failed; run it by hand: bash %s\n' "$classic_setup"
fi

printf '\nNyxiri installed.\n'
