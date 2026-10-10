"""Native GTK4 settings and controls (Wayland)."""
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib
from timer import call

def run():
    app = Gtk.Application(application_id='org.local.CycleTimer')
    def activate(app):
        if app.get_active_window():
            app.get_active_window().present()
            return
        win = Gtk.ApplicationWindow(application=app, title='Cycle Timer')
        win.set_default_size(440, 480)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for edge in ['top','bottom','start','end']:
            getattr(box, 'set_margin_'+edge)(24)
        win.set_child(box)
        status = Gtk.Label(label='Connecting…', wrap=True)
        status.add_css_class('title-2')
        box.append(status)
        error = Gtk.Label(wrap=True)
        error.add_css_class('error')
        def field(title, widget):
            box.append(Gtk.Label(label=title, xalign=0))
            box.append(widget)
            return widget
        message = field('Reminder text', Gtk.Entry())
        message.set_max_length(1000)
        def spin(low, high, step, digits=0):
            s = Gtk.SpinButton.new_with_range(low, high, step)
            s.set_digits(digits)
            return s
        interval = field('Interval, minutes', spin(.01,10080,1,2))
        rest_box = Gtk.Box(spacing=8)
        rest = spin(0,604800,1,2)
        rest.set_hexpand(True)
        units = Gtk.DropDown.new_from_strings(['seconds','minutes'])
        rest_box.append(rest)
        rest_box.append(units)
        field('Break duration', rest_box)
        repeats = field('Repeat count', spin(1,100000,1))
        forever = Gtk.CheckButton(label='Repeat until stopped')
        forever.connect('toggled', lambda b: repeats.set_sensitive(not b.get_active()))
        box.append(forever)
        buttons = Gtk.Box(spacing=8, homogeneous=True)
        box.append(buttons)
        box.append(error)
        def action(cmd):
            try:
                config = dict(message=message.get_text(), interval=interval.get_value(),
                              rest=rest.get_value()*(60 if units.get_selected()==1 else 1),
                              repeats=0 if forever.get_active() else repeats.get_value_as_int())
                call(cmd, config)
                error.set_text('')
                refresh()
            except Exception as e:
                error.set_text(str(e))
        start = Gtk.Button(label='Start')
        pause = Gtk.Button(label='Pause')
        stop = Gtk.Button(label='Stop')
        start.add_css_class('suggested-action')
        for button, cmd in [(start,'start'),(pause,'toggle'),(stop,'stop')]:
            button.connect('clicked', lambda b,c=cmd: action(c))
            buttons.append(button)
        def refresh():
            try:
                s = call()
                status.set_text(s['text']+'\n'+s['tooltip'])
                pause.set_label('Resume' if s['paused'] else 'Pause')
                pause.set_sensitive(s['phase']!='stopped')
                stop.set_sensitive(s['phase']!='stopped')
                start.set_label('Restart' if s['phase']!='stopped' else 'Start')
            except Exception as e:
                error.set_text(str(e))
            return True
        try:
            c = call()['config']
            message.set_text(c['message'])
            interval.set_value(c['interval'])
            rest.set_value(c['rest'])
            repeats.set_value(c['repeats'] or 1)
            forever.set_active(c['repeats']==0)
        except Exception as e:
            error.set_text(str(e))
        refresh()
        source = GLib.timeout_add_seconds(1, refresh)
        win.connect('close-request', lambda w: (GLib.source_remove(source), False)[1])
        win.present()
    app.connect('activate', activate)
    app.run([])
