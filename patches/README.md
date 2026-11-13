# Patches

Nyxiri does not carry a `.patch` series. `Bar.qml` is a full copy of upstream
with marked insertions, because a context diff over a 3,000-line QML file
conflicts constantly and hides which lines are ours.

## Layout

| Path | Meaning |
| --- | --- |
| `upstream/Bar.qml` | Pristine upstream bar from the last merge |
| `upstream/BarModel.js` | Pristine upstream model from the last merge |
| `upstream/bar-manifest.json` | Upstream manifest, for reference only |
| `../Bar.qml` | Working copy: upstream plus Nyxiri blocks |
| `../BarModel.js` | Unmodified upstream copy |

## Markers

Every Nyxiri edit is wrapped:

```qml
// NYXIRI-BEGIN nyxiri-config
// NYXIRI-END nyxiri-config
```

Block names in use:

- `nyxiri-config` — normalized config and read helpers
- `nyxiri-palette` — `colors.toml` watcher
- `nyxiri-write` — `writeNyxiri()`
- `nyxiri-settings-state` — open/close state and IPC entry points
- `nyxiri-ipc` — `pizza.dirty.nyxiri` IPC handler
- `nyxiri-right-click` — bar background right-click
- `nyxiri-pill` — pill surface component
- `nyxiri-islands-horizontal` / `nyxiri-islands-vertical` — section islands
- `nyxiri-island-center` — union pill across the center regions
- `nyxiri-mini` / `nyxiri-mini-pill` — per-widget pills
- `nyxiri-settings-card` — the settings popup instance

`scripts/test.sh` fails if a `NYXIRI-BEGIN` has no matching
`NYXIRI-END`.

## Rebasing

```sh
scripts/sync-upstream.sh
```

The script:

1. Copies the installed files to a temporary directory.
2. Three-way merges each working file (`ours`) against `upstream/` (`base`)
   and the installed file (`theirs`).
3. Writes a clean result in place and refreshes `upstream/`.
4. Writes `Bar.qml.rebase` and stops on conflicts.

Conflicts should be resolved by keeping upstream's structure and re-applying
the marked block contents. Do not hand-edit outside the markers unless the
change belongs upstream; if it does, upstream it instead.
