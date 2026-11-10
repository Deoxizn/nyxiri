# Nyxiri

Nyxiri is a drop-in **bar plugin** for the Omarchy shell. It keeps the upstream
`omarchy.bar` engine intact and adds three things on top:

- **Section pills** — each of the left, center and right sections can be one
  island pill around the whole section, or a mini pill per widget.
- **Per-monitor rules** — switch a monitor's bar off, and choose which widgets
  it shows with `all`, `only` or `except` lists.
- **Palette colours** — pick any role from the active theme's `colors.toml`
  (not just the accent), or a custom hex, with separate fill and border
  opacity.

Settings live in an in-bar card, opened by right-clicking the bar or with:

```sh
omarchy-shell devi.nyxiri openSettings
```

Nyxiri is a plugin. It does not fork the shell and touches nothing under
`/usr/share/omarchy`.

## Requirements

- Omarchy with the Quickshell-based shell (`/usr/share/omarchy/shell`).
- `omarchy-shell` on `PATH` for the settings IPC.
- `omarchy plugin` for the Widgets tab (enable/disable and bar options).

## Install

```sh
git clone https://github.com/Deoxizn/nyxiri.git
cd nyxiri
scripts/install.sh            # git clone into ~/.config/omarchy/plugins/devi.nyxiri
omarchy-shell shell rescanPlugins
omarchy bar use devi.nyxiri
```

The default install is a real git checkout, so `omarchy plugin update`
works on it. It installs both parts: the bar (`devi.nyxiri`) and the menu
(`devi.nyxiri-menu`, cloned from its own repo). Pass `--no-menu` for the
bar only. Live-edit with `scripts/install.sh --link` instead, but note a
symlinked install always fails `omarchy plugin update` validation:
Omarchy's validator refuses symlinks inside a plugin folder. A plain copy
(`scripts/install.sh --copy`) has no `.git`, so it can't be updated either.

To go back:

```sh
omarchy bar reset
omarchy plugin disable devi.nyxiri
```

## Configuration

Nyxiri stores everything under `bar.nyxiri` in `~/.config/omarchy/shell.json`.
The settings card writes this file through the bar API; hand edits are fine and
are picked up on the next shell reload.

```jsonc
{
  "bar": {
    "id": "devi.nyxiri",
    "nyxiri": {
      "version": 1,
      "sections": {
        "left": "island",   // island | mini
        "center": "island",
        "right": "mini"
      },
      "pill": {
        "color": "accent",        // any colors.toml role, "custom", or a hex
        "customColor": "#7aa2f7",
        "fillOpacity": 0.18,
        "borderOpacity": 0.35,
        "borderWidth": 1,
        "radius": 999,            // 999 = fully rounded
        "padding": 6,             // along-bar space around an island
        "inset": 2,               // across-bar space around a pill
        "miniGap": 2,             // gap between a mini pill and its neighbours
        "surface": "theme"        // theme | clear
      },
      "monitors": {
        "DP-1": {
          "enabled": true,
          "widgets": {
            "mode": "except",     // all | only | except
            "list": ["omarchy.tray"]
          }
        },
        "HDMI-A-1": { "enabled": false }
      }
    }
  }
}
```

### Sections

`centerBegin` and `centerEnd` follow `center`: all three form one island, and
mini mode pills each widget in any of the three regions.

### Monitor rules

A monitor with no entry is fully enabled and shows every widget. In a rule:

- `all` ignores `list`.
- `only` shows the listed widget ids (an empty list shows nothing).
- `except` hides the listed widget ids.

Rules match either the whole layout key (`omarchy.clock#4`) or the plugin id
(`omarchy.clock`). The id form is what the settings card writes and survives
reloads; `#serial` keys are an internal layout detail.

Disabling a monitor's bar unmaps that surface and reserves no space. Other
monitors are unaffected.

### Colours

`pill.color` names a role read from
`~/.local/state/omarchy/current/theme/colors.toml` (`accent`, `foreground`,
`red`, `bright_blue`, `color4`, …). `custom` uses `pill.customColor`, which must
be a hex colour. A hex in `pill.color` works directly too.

`surface: "clear"` drops the bar's own background so only the pills read;
`"theme"` keeps the configured Omarchy bar background.

## Settings card

Right-click any bar surface, or run one of:

```sh
omarchy-shell devi.nyxiri openSettings
omarchy-shell devi.nyxiri toggleSettings
omarchy-shell devi.nyxiri closeSettings
```

The card is a `PopupCard` centered under the bar. Its tabs are:

- **Appearance** — section modes, colour role, custom hex, fill/border
  opacity, border width, island padding, bar surface.
- **Monitors** — per-monitor bar toggle and widget rules.
- **Widgets** — enable/disable installed plugins, add one to the bar, use a bar
  option as the active bar, or reset to the built-in bar. These actions run
  the official `omarchy` CLI, so behaviour matches the menu.

## Menu integration

The separate [nyxiri-menu](https://github.com/Deoxizn/nyxiri-menu) fork adds a
**Nyxiri** entry to the Omarchy menu and calls `openSettings` over IPC. It is
optional; Nyxiri works without it.

## How it works

`Bar.qml` is a copy of upstream `omarchy.bar` with marked blocks:

```
// NYXIRI-BEGIN nyxiri-config
...
// NYXIRI-END nyxiri-config
```

There are no changes outside those blocks. `BarModel.js` is untouched.
`Nyxiri.js` holds the pure config logic and is loaded by both QML and
`node --test`.

`upstream/` holds the pristine files we last merged. To rebase:

```sh
scripts/sync-upstream.sh
```

The script runs a three-way merge (`base = upstream/`, `ours = working`,
`theirs = installed`). A clean merge updates the working files; conflicts are
written to `Bar.qml.rebase` for review and the script stops. See
[`patches/README.md`](patches/README.md).

## Development

```sh
scripts/test.sh        # node tests, shellcheck, QML parse check
scripts/sync-upstream.sh
```

The tests cover normalization, prototype-safe merging, monitor matching,
palette parsing and colour resolution.

## Limitations

- The settings card is per bar surface; opening it on another monitor replaces
  the one already open (the bar only tracks one popout at a time).
- Widget enabling uses `omarchy plugin`, so it affects the whole session, not
  one monitor. Per-monitor visibility is the rule list, not plugin enablement.
- Custom workspace icons are not part of this version.
- `omarchy-shell` IPC requires the bar to be loaded; if Nyxiri failed to load,
  the stock bar is active and the IPC target is unavailable.

## Licence

MIT.
