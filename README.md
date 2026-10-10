# Cycle Timer for Omarchy

A lightweight repeating reminder timer for Omarchy. Set a reminder, choose an interval and break duration, and control everything from a popup attached to your bar.

The interface is in English and follows your current Omarchy theme. A countdown appears while the timer is running; when stopped, only the timer icon remains.

> **AI-generated project.** The code, interface implementation, scripts, documentation, and notification sound were created with OpenAI ChatGPT/Codex. The project owner provided the idea, requirements, feedback, and hands-on testing; they do not claim to have written the implementation. This is a community project, not an official Omarchy or OpenAI product. See [AI_DISCLOSURE.md](AI_DISCLOSURE.md).

## Features

- Reminder text, interval in minutes, and breaks in seconds or minutes.
- A fixed number of repetitions or unlimited cycles.
- Start, restart, pause, resume, and stop.
- Countdown in the bar; an icon alone when stopped.
- Native popup with the same foreground color role as the Omarchy calendar.
- Empty input fields with placeholders; no prefilled reminder or durations.
- Desktop notifications and an optional chime at the start and end of each break.
- Shared timer across monitors; closing the popup does not stop it.
- Optional Waybar integration with a separate GTK4 window.

## Requirements

For the native popup, use an Omarchy installation with the Quickshell-based shell, `omarchy plugin`, and its `qs.Ui` components (`KeyboardPanel`, `WidgetButton`, and `Panel`). This does not support the native popup on older Waybar-only Omarchy installations.

Install dependencies on Arch Linux:

```sh
sudo pacman -S --needed python python-gobject gtk4 libnotify
```

Native Omarchy provides Quickshell and `jq`. Sound uses `pw-play` (PipeWire), with `paplay` as a fallback. Without either player, the timer continues silently. Desktop notifications require a running notification server.

## Install

Download or clone this repository, then run from its directory:

```sh
./install.sh omarchy
```

The installer validates the manifest, copies the plugin into `~/.config/omarchy/plugins/local.cycle-timer`, creates `~/.local/bin/cycle-timer` and an application launcher, and enables the bar widget. It waits for asynchronous plugin discovery. Re-running it resumes an incomplete installation but does not overwrite existing plugin code.

This repository intentionally keeps the ID `local.cycle-timer` for compatibility with early installations. It is not yet published in the Omarchy plugin registry.

## Use

Click the bar icon to open the popup. Enter a reminder and durations, choose a repeat mode, and press **Start**. Changes to fields and **Sound** apply on the next start. **Restart** begins a new cycle from zero.

| Action | Result |
| --- | --- |
| Left-click the bar icon | Open or close the popup |
| Right-click the bar icon | Pause or resume |
| Middle-click the bar icon | Stop the timer |
| Press Escape or click outside | Close the popup |
| **Start / Restart** | Apply the form and begin a new cycle |
| **Sound: On / Off** | Choose sound behavior for the next start |

For example, an interval of **25 minutes**, a break of **5 minutes**, and **4 repetitions** gives you four work intervals, each followed by a reminder and a break.

One repetition is **interval → reminder → break**. The first reminder appears after the first interval. After the final break, the timer stops. Use a break of `0` to skip waiting between intervals. Pausing freezes the remaining time in either phase.

When the computer wakes from sleep, an expired phase advances once; missed reminders are not replayed in a burst. The timer does not wake the computer. Restarting the backend or signing into a new session leaves it stopped. Settings are saved, but the native popup deliberately starts with empty text and numeric fields.

Sound follows system audio volume/mute and can play even when notification Do Not Disturb is enabled. Use **Sound: Off** to silence it. Your reminder text is stored locally and passed as an argument, never evaluated as shell code.

## Update

Stop the timer and close any standalone GTK window before updating. From the new checkout or extracted release:

```sh
./update.sh
```

The updater refuses to interrupt an active timer, saves a backup in `~/.local/state/cycle-timer/backups/`, replaces runtime files, and restarts the backend. User preferences remain intact. The shell watches plugin files; if it still displays an old widget, run `omarchy restart shell`.

## Waybar (optional)

```sh
./install.sh waybar
```

Merge the object from `waybar.jsonc` into your existing Waybar configuration, add `custom/cycle-timer` to `modules-right`, and append `waybar.css` to your stylesheet. Back up those files first. The JSONC file is a fragment, not a complete Waybar configuration. Restart Waybar after editing it.

Do not add an `interval` setting: the command streams JSON once per second. Clicking the Waybar module opens the GTK4 window, not the native Omarchy popup. The GTK frontend does not expose all native popup options; use the CLI for silent starts.

## CLI

```sh
~/.local/bin/cycle-timer start --message 'Stretch and look away' --interval 25 --rest 300 --repeats 4
~/.local/bin/cycle-timer toggle
~/.local/bin/cycle-timer stop
~/.local/bin/cycle-timer status
```

`--rest` is in seconds; `--repeats 0` means unlimited; `--silent` disables sounds. Use a decimal point for fractional CLI durations. `cycle-timer ui` opens the optional GTK window.

## Troubleshooting

**The widget does not appear**

```sh
omarchy plugin validate ~/.config/omarchy/plugins/local.cycle-timer
omarchy-shell shell rescanPlugins
omarchy plugin enable local.cycle-timer
```

**The old interface is still visible**

Close any standalone GTK window. If the bar still loads the previous widget after updating, run `omarchy restart shell`.

**No sound**

Enable **Sound: On** before starting a cycle. Check system volume and whether `pw-play` or `paplay` is installed.

**No notifications**

Run `notify-send 'Cycle Timer' 'Test notification'` from your desktop session and check your notification settings.

**`omarchy plugin` is unavailable**

Your installation does not provide the required native plugin mechanism. Use the Waybar integration if you run Waybar.

## Data and architecture

- `Widget.qml` and `TimerPanel.qml`: bar widget and native popup.
- `timer.py`: per-session daemon, state machine, CLI, notifications, and sound playback.
- `ui.py`: optional GTK4 frontend.
- `reminder.wav`: generated one-second chime, included under the project license.
- `$XDG_RUNTIME_DIR/cycle-timer/`: private socket and daemon lock.
- `${XDG_CONFIG_HOME:-~/.config}/cycle-timer/settings.json`: saved settings and reminder text.

The backend uses a lock to prevent duplicate daemons and a private Unix socket. It does not require a network connection. No telemetry is included.

## Validation and limitations

```sh
python3 -m unittest discover -s tests -v
python3 -m py_compile timer.py ui.py
bash -n install.sh update.sh
omarchy plugin validate .
```

Automated tests cover finite cycles, infinite cycles, pause/resume, zero-duration breaks, wake-from-sleep behavior, invalid values, and restart. GitHub CI runs the Python tests and syntax checks; the Omarchy manifest validator is a local check.

The native interface has been iterated through hands-on user testing. Full automated Wayland, GTK, audio, and notification delivery tests are not included. The shell APIs may change between Omarchy versions. Please include your Omarchy version, steps to reproduce, and relevant errors when reporting problems; remove personal reminder text first.

## Uninstall

Disable the native widget:

```sh
omarchy plugin disable local.cycle-timer
```

For Waybar, remove the module from its config and restart Waybar instead. Close the GTK window, then run `~/.local/bin/cycle-timer shutdown`. Remove the plugin directory, `~/.local/bin/cycle-timer`, and `~/.local/share/applications/local.cycle-timer.desktop`. Optionally remove saved settings and backups.

## License and credits

[MIT](LICENSE), to the extent applicable. AI-generated provenance is documented in [AI_DISCLOSURE.md](AI_DISCLOSURE.md). The native UI uses Omarchy shell components supplied by the user's installation; those dependencies retain their own licenses. The repository does not bundle the Omarchy shell or fonts.
