#!/usr/bin/env bash
set -euo pipefail
mode=${1:-omarchy}
[[ $mode == omarchy || $mode == waybar ]] || { echo 'Usage: ./install.sh [omarchy|waybar]' >&2; exit 1; }
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for cmd in python3 notify-send; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }; done
python3 -c 'import gi; gi.require_version("Gtk", "4.0"); from gi.repository import Gtk'
if [[ $mode == omarchy ]]; then
  command -v jq >/dev/null
  omarchy plugin validate "$source_dir"
fi
target="$HOME/.config/omarchy/plugins/local.cycle-timer"
# Resume an interrupted installation without overwriting plugin edits.
if [[ -e $target ]]; then
  [[ -f $target/manifest.json ]] && python3 - "$target/manifest.json" <<'CHECK'
import json, sys
assert json.load(open(sys.argv[1]))['id'] == 'local.cycle-timer', 'Unexpected plugin ID'
CHECK
  [[ -f $target/timer.py && -f $target/Widget.qml ]] || { echo "Incomplete plugin at $target" >&2; exit 1; }
  if [[ $mode == omarchy ]]; then omarchy plugin validate "$target"; fi
  echo "Resuming installation using existing plugin: $target"
else
  mkdir -p "$(dirname "$target")"
  cp -R -- "$source_dir" "$target"
fi
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
if [[ -e $HOME/.local/bin/cycle-timer ]]; then
  expected=$(printf '%s\n' '#!/bin/sh' 'exec python3 "$HOME/.config/omarchy/plugins/local.cycle-timer/timer.py" "$@"')
  [[ $(cat "$HOME/.local/bin/cycle-timer") == "$expected" ]] || { echo 'Unrelated cycle-timer command already exists; leaving it unchanged' >&2; exit 1; }
fi
cat > "$HOME/.local/bin/cycle-timer" <<'EOF'
#!/bin/sh
exec python3 "$HOME/.config/omarchy/plugins/local.cycle-timer/timer.py" "$@"
EOF
chmod +x "$HOME/.local/bin/cycle-timer"
# Desktop Exec expands neither $HOME nor ~. Escape reserved characters in its quoted argument.
python3 - "$target" <<'PY'
import pathlib, sys
path = sys.argv[1] + '/timer.py'
for char in ['\\', '"', '`', '$']:
    path = path.replace(char, '\\' + char)
path = path.replace('%', '%%')
(pathlib.Path.home()/'.local/share/applications/local.cycle-timer.desktop').write_text(
    '[Desktop Entry]\nType=Application\nName=Cycle Timer\nName[ru]=Cycle Timer\n'
    'Comment=Repeating reminders and breaks\nExec=python3 "'+path+'" ui\n'
    'Icon=alarm-symbolic\nTerminal=false\nCategories=Utility;\n')
PY
if [[ $mode == omarchy ]]; then
  omarchy-shell shell rescanPlugins
  # Rescan schedules asynchronous discovery. Wait for the shell's registry,
  # as the official omarchy-plugin-add installer does.
  discovered=0
  for (( attempt=0; attempt<100; attempt++ )); do
    if omarchy plugin list --json | jq -e 'any(.[]; .id == "local.cycle-timer")' >/dev/null; then
      discovered=1
      break
    fi
    sleep 0.1
  done
  if (( ! discovered )); then
    echo 'Plugin files installed, but the shell did not discover them within 10 seconds.' >&2
    echo 'Check: omarchy plugin list --json. Then rerun this installer.' >&2
    exit 1
  fi
  omarchy plugin enable local.cycle-timer
fi
printf 'Installed. Open: %s/.local/bin/cycle-timer ui\n' "$HOME"
