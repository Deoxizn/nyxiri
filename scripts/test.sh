#!/usr/bin/env bash
# Run the checks available on this machine. qmllint resolves neither the qs.*
# imports nor Quickshell's Io module, so it is used only to catch parse errors;
# its unresolved-import warnings are not failures.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$root"

fail=0

printf '== node tests ==\n'
node --test tests/*.test.js || fail=1

printf '\n== shellcheck ==\n'
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh || fail=1
else
  printf 'shellcheck not installed; skipped\n'
fi

printf '\n== QML parse ==\n'
qmllint_bin=/usr/lib/qt6/bin/qmllint
if [[ -x $qmllint_bin ]]; then
  for file in Bar.qml NyxiriSettings.qml; do
    if "$qmllint_bin" "$file" 2>&1 | grep -E '^Error|Syntax|Expected|Unexpected' >&2; then
      printf 'parse errors in %s\n' "$file" >&2
      fail=1
    else
      printf 'ok  %s\n' "$file"
    fi
  done
else
  printf 'qmllint not installed; skipped\n'
fi

exit "$fail"
