#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target="$HOME/.config/omarchy/plugins/local.cycle-timer"
omarchy plugin validate "$source_dir"
if [[ ! -d $target ]]; then
  exec "$source_dir/install.sh" omarchy
fi
# Updating the backend requires a restart. Never interrupt an active timer.
status=$(python3 "$target/timer.py" status)
if [[ $(printf '%s' "$status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["phase"])') != stopped ]]; then
  echo 'Stop the timer before updating, then run ./update.sh again.' >&2
  exit 1
fi
python3 "$target/timer.py" shutdown >/dev/null
backup="$HOME/.local/state/cycle-timer/backups/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
cp -R "$target/." "$backup/"
# Dependency first: plugin files are watched by the shell.
for file in reminder.wav timer.py ui.py TimerPanel.qml Widget.qml manifest.json; do
  cp -- "$source_dir/$file" "$target/$file"
done
python3 "$target/timer.py" shutdown >/dev/null
omarchy-shell shell rescanPlugins
printf 'Updated. Backup: %s\n' "$backup"
