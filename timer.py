#!/usr/bin/env python3
"""Cycle Timer: private per-session daemon and JSON client; no shell evaluation."""
import argparse
import fcntl
import html
import json
import math
import os
from pathlib import Path
import socket
import shutil
import threading
import subprocess
import sys
import time

BASE = Path(__file__).resolve().parent

def now():
    return time.clock_gettime(time.CLOCK_BOOTTIME)

class Timer:
    def __init__(self):
        self.phase = 'stopped'
        self.paused = False
        self.completed = 0
        self.deadline = 0
        self.remaining = 0
        self.config = dict(message='Time for a break', interval=25.0, rest=300.0, repeats=0, sound=True)

    def start(self, config, t):
        c = dict(config)
        c['message'] = str(c['message']).strip()
        c['interval'], c['rest'] = float(c['interval']), float(c['rest'])
        repeats = float(c['repeats'])
        if not c['message'] or len(c['message']) > 1000:
            raise ValueError('Enter a reminder between 1 and 1000 characters')
        if not math.isfinite(c['interval']) or not 0 < c['interval'] <= 10080:
            raise ValueError('Interval must be greater than 0 and at most 10080 minutes')
        if not math.isfinite(c['rest']) or not 0 <= c['rest'] <= 604800:
            raise ValueError('Break must be between 0 and 604800 seconds')
        if not math.isfinite(repeats) or not repeats.is_integer() or not 0 <= repeats <= 100000:
            raise ValueError('Repeat count must be a whole number from 0 to 100000')
        c['repeats'] = int(repeats)
        c["sound"] = bool(c.get("sound", True))
        self.config = c
        self.phase, self.paused, self.completed = 'work', False, 0
        self.deadline = t + c['interval'] * 60

    def tick(self, t):
        events = []
        if self.phase == 'stopped' or self.paused or t < self.deadline:
            return events
        if self.phase == 'work':
            self.completed += 1
            events.append(('Break', self.config['message']))
            self.phase = 'rest'
            self.deadline = t + self.config['rest']
        else:
            if self.config['repeats'] and self.completed >= self.config['repeats']:
                self.phase = 'stopped'
                events.append(('Timer complete', 'All repetitions completed.'))
            else:
                self.phase = 'work'
                self.deadline = t + self.config['interval'] * 60
                events.append(('Break finished', 'The next interval has started.'))
        return events

    def toggle(self, t):
        if self.phase == 'stopped':
            return
        if self.paused:
            self.deadline = t + self.remaining
        else:
            self.remaining = max(0, self.deadline - t)
        self.paused = not self.paused

    def status(self, t):
        seconds = math.ceil(self.remaining if self.paused else max(0, self.deadline-t))
        if self.phase == 'stopped':
            seconds = 0
        duration = f'{seconds//60:02d}:{seconds%60:02d}'
        label = {'work':'Interval', 'rest':'Break', 'stopped':'Stopped'}[self.phase]
        prefix = 'Ⅱ' if self.paused else ('☕' if self.phase == 'rest' else '◷')
        return dict(phase=self.phase, paused=self.paused, seconds=seconds,
                    completed=self.completed, config=self.config,
                    text=f'{prefix} {duration}' if self.phase != 'stopped' else '◷ Timer',
                    tooltip=f'{label}{" · Pause" if self.paused else ""}\n{self.config["message"]}\nCompleted: {self.completed} / {self.config["repeats"] or "∞"}',
                    **{'class': 'paused' if self.paused else self.phase})

def runtime():
    root = os.environ.get('XDG_RUNTIME_DIR')
    if not root:
        raise RuntimeError('XDG_RUNTIME_DIR is not set. Run from your desktop session.')
    path = Path(root) / 'cycle-timer'
    path.mkdir(mode=0o700, exist_ok=True)
    return path

def preferences():
    return Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'cycle-timer/settings.json'

def play_sound():
    player = shutil.which('pw-play') or shutil.which('paplay')
    if not player:
        return
    def play():
        try:
            subprocess.run([player, str(BASE/'reminder.wav')], timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass
    threading.Thread(target=play, daemon=True).start()

def notify(title, body, sound=False):
    if sound:
        play_sound()
    try:
        subprocess.run(['notify-send', '--app-name=Cycle Timer', '--icon=alarm-symbolic', '--hint=boolean:suppress-sound:true',
                        '--', title, html.escape(body)], timeout=4, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass

def daemon():
    path = runtime()
    with (path/'daemon.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        address = path/'socket'
        address.unlink(missing_ok=True)
        timer = Timer()
        try:
            timer.start(json.loads(preferences().read_text()), now())
            timer.phase = 'stopped'
        except (OSError, ValueError, KeyError, TypeError):
            pass
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(address))
            os.chmod(address, 0o600)
            server.listen(8)
            server.settimeout(0.2)
            while True:
                for title, body in timer.tick(now()):
                    notify(title, body, sound=title in ("Break", "Break finished", "Timer complete") and timer.config.get("sound", True))
                try:
                    conn, _ = server.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(1)
                    try:
                        raw = b''
                        while not raw.endswith(b'\n') and len(raw) < 16384:
                            part = conn.recv(4096)
                            if not part:
                                break
                            raw += part
                        request = json.loads(raw)
                        cmd = request['command']
                        if cmd == 'start':
                            timer.start(request['config'], now())
                            p = preferences()
                            p.parent.mkdir(parents=True, exist_ok=True)
                            temp = p.with_suffix('.tmp')
                            temp.write_text(json.dumps(timer.config, ensure_ascii=False))
                            temp.replace(p)
                        elif cmd == 'toggle':
                            timer.toggle(now())
                        elif cmd in ('stop', 'shutdown'):
                            timer.phase, timer.paused = 'stopped', False
                        elif cmd != 'status':
                            raise ValueError('Unknown command')
                        result = timer.status(now())
                    except (ValueError, KeyError, TypeError, OSError) as e:
                        result = {'error': str(e)}
                    try:
                        conn.sendall((json.dumps(result, ensure_ascii=False)+'\n').encode())
                    except OSError:
                        pass
                    if result.get('phase') == 'stopped' and request.get('command') == 'shutdown':
                        address.unlink(missing_ok=True)
                        return

def call(command='status', config=None):
    path = runtime()/'socket'
    for attempt in range(25):
        try:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(6)
                client.connect(str(path))
                client.sendall((json.dumps(dict(command=command, config=config))+'\n').encode())
                data = b''
                while not data.endswith(b'\n'):
                    part = client.recv(4096)
                    if not part:
                        raise RuntimeError('Timer closed the connection')
                    data += part
                result = json.loads(data)
                if 'error' in result:
                    raise ValueError(result['error'])
                return result
        except (FileNotFoundError, ConnectionRefusedError):
            if attempt == 0:
                subprocess.Popen([sys.executable, str(BASE/'timer.py'), 'daemon'],
                                 start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(.05)
    raise RuntimeError('Could not start timer')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['daemon','ui','status','waybar','start','toggle','stop','shutdown'])
    parser.add_argument('--message', default='Time for a break')
    parser.add_argument('--interval', type=float, default=25, help='minutes')
    parser.add_argument('--rest', type=float, default=300, help='seconds')
    parser.add_argument('--repeats', type=int, default=0, help='0 = unlimited')
    parser.add_argument("--silent", action="store_true", help="Disable reminder sound")
    args = parser.parse_args()
    if args.command == 'daemon':
        daemon()
    elif args.command == 'ui':
        from ui import run
        run()
    elif args.command == 'waybar':
        while True:
            result = call()
            result['tooltip'] = html.escape(result['tooltip'])
            print(json.dumps(result, ensure_ascii=False), flush=True)
            time.sleep(1)
    else:
        config = dict(message=args.message, interval=args.interval, rest=args.rest, repeats=args.repeats, sound=not args.silent)
        print(json.dumps(call(args.command, config), ensure_ascii=False))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
