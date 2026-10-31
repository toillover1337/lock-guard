# screen-guard

**Version 1.0.0** - <https://github.com/toillover1337/lock-guard>

Two small POSIX `sh` scripts that keep a desktop tidy around screen locking and monitor power
cycling. Built on Xfce/X11 first, with parts for Wayland compositors and for other ways of
noticing a lock; the installer keeps only the parts for the environments you have (see
"Environments").

| script | job |
|---|---|
| `lock-guard` | While the screen is locked, switch off chosen input devices (so a twitching mouse cannot wake the monitors), remember where the windows on the secondary monitor(s) were, optionally dim the monitors while locked, and optionally run your own commands on lock / unlock (for example to change RGB lighting). |
| `randr-fix` | X11 only. When the monitor layout changes (monitor switched off and on, hotplug, slow DisplayPort link), reassert the layout, put the windows back and restore the desktop icons (Xfce). In a Wayland session it does nothing. |

No Python, no X libraries: only standard tools.

## Install

```
git clone https://github.com/toillover1337/lock-guard.git
cd lock-guard
./install.sh            # detect this machine, show what it found, ask what to install
./install.sh --list     # only show what was detected
./install.sh --yes      # accept the detected defaults
./install.sh --update       # install a newer release, if there is one (see "Updating")
./install.sh --uninstall
```

Run it as your user, not root. It prints what it found (init system, X11 and Wayland sessions
and window managers), then lists the **parts** of the program:

| part | what it is for |
|---|---|
| `x11` | X11 sessions: `xrandr` dimming, `xinput` device switching, `wmctrl` window saving, the raw key listener |
| `wayland` | Wayland sessions: dimming through wl-gammarelay-rs or your own commands, your own input commands, `libinput` key listener |
| `dbus` | noticing a lock over D-Bus (Xfce, GNOME, KDE and others announce it) |
| `process` | noticing a lock by its locker program running (swaylock, gtklock, hyprlock, i3lock ...) |

The default keeps the parts for what is installed and removes the others from the installed copy
(a machine where nothing can be detected keeps everything). Answer the prompt with a list
(`x11,dbus`), `all`, or changes to the default (`+wayland`, `-process`); or give the answer up
front: `./install.sh --variants x11,wayland,dbus,process`. At least one of x11/wayland and one of
dbus/process must stay. A removed part is gone from that copy only; re-run the installer from the
unpacked folder to add it back. `randr-fix` is installed only when `x11` is kept.

At login the programs start through `--autostart xdg` (default: `~/.config/autostart`, read by
Xfce, GNOME, KDE and similar), `systemd` (writes user units; you enable them), `shepherd`
(prints a Guix Home service sketch) or `none`. Window managers and compositors that do not read
`~/.config/autostart` (oxwm, mangowm ...) need `lock-guard --start` and `randr-fix --start` added
to their own startup commands; the installer prints those lines. The init system does not change
how the programs run, only how they are started.

The installer never overwrites an existing config. On an upgrade it keeps every setting and
comments, and appends only the options your config does not mention yet, as commented-out
defaults under a dated marker (a key you commented out yourself is not added again), so new
versions never change behaviour until you uncomment something. `randr-fix --detect` is used to fill in the
monitor section from what is connected at install time (only from an X11 session); check it.

## Updating

```
./install.sh --check-update    # compare the installed version with the newest release (exit 10 = newer exists)
./install.sh --update          # download it, show what changes, ask, install, restart the programs
./install.sh --update --yes    # the same without questions
```

Both the programs (`lock-guard --version`) and the installer carry a version number
(`MAJOR.MINOR.PATCH`). The newest release is read from the `VERSION` file on the main branch of
the repository; the release itself is the GitHub archive of the matching tag (`vX.Y.Z`). An update
is offered only when that number is higher than the installed one.

What an update does and does not do:

* It repeats the choices you made at the first install (kept parts, autostart method, prefix),
  recorded in `~/.config/screen-guard/install.conf`; options on the command line win.
* Your configs are kept; new options are appended commented out, as on any upgrade.
* The previous scripts are copied to `~/.config/screen-guard/previous/` first, so going back is a
  copy. The running programs are restarted at the end (it asks, unless `--yes`).
* The download is plain HTTPS from GitHub; **there is no signature or checksum**, so trust is
  the same as for `git pull` from that repository. Before installing it checks that the archive
  holds no absolute or `..` paths, that the three scripts are valid shell, and that the version
  numbers inside agree with the announced one; anything else is refused and nothing is changed.
  It needs `curl`, `wget` or BSD `fetch`. If you installed from a git clone, `git pull` and
  `./install.sh` do the same job.

## Environments

One installed copy serves several environments. Each time `lock-guard` starts it decides, from
`SESSION` (default `auto`), whether this is an X11 or a Wayland session: `XDG_SESSION_TYPE`
first, then `WAYLAND_DISPLAY`. So on a machine with both Xfce and a Wayland compositor the same
autostart entry does the right thing in each. `randr-fix` does nothing in a Wayland session.

| | X11 | Wayland |
|---|---|---|
| lock noticed by | D-Bus (`dbus`) | locker process (`process`); `LOCK_DETECT="dbus process"` uses both |
| input devices | `xinput`, chosen by `LOCK_DEVICE_PATTERN` | your own `INPUT_OFF_COMMAND` / `INPUT_ON_COMMAND` (there is no generic way) |
| dimming | `xrandr --brightness` (+ keeper that re-dims) | wl-gammarelay-rs (needs `busctl`), or `DIM_COMMAND` / `UNDIM_COMMAND` |
| early undim | raw key events from `xinput` | raw key events from `libinput debug-events` (needs the `input` group or root); or `lock-guard --undim` from a compositor keybind |
| windows | saved on lock, restored by randr-fix | compositor keeps them |
| monitor layout | `randr-fix` | compositor |

What has and has not been tried: the X11 parts ran on one Xfce/Gentoo machine. The Wayland parts
are tested against stand-ins for `busctl`, `libinput` and `pgrep` only; they have not run on a
real compositor yet. Wayland compositors differ, so expect to set `LOCKER_PROCESSES`,
`INPUT_OFF_COMMAND` and the dimming commands for yours. Wayland edge cases where `randr-fix`
might be useful (outputs that come back at the wrong position after a power cycle) are not handled; a
port would use `wlr-randr` and would be added as another part.

Tools used, by part: `awk` and `sed` always; `x11`: `xrandr` `xset` `xev` `xinput` `xprop` `wmctrl`
(`xfdesktop` for icons, `xmodmap` for more key names in `UNDIM_KEY`, optional); `dbus`:
`dbus-monitor`; `process`: `pgrep`; `wayland`: `busctl` + wl-gammarelay-rs for dimming, `libinput`
for `UNDIM_KEY`. Tested with gawk, mawk and busybox awk. Debian/Ubuntu packages: `x11-apps x11-xserver-utils xinput wmctrl
x11-utils dbus`; other distributions name them similarly. `stdbuf` (GNU coreutils) is used when present.

## randr-fix

```
randr-fix                 watch for monitor changes (what autostart runs, stays in the foreground)
randr-fix -s, --start     start it in the background (nothing happens if it already runs)
randr-fix -S, --stop      stop it
randr-fix -r, --restart   stop, then start (use after changing the config or upgrading)
randr-fix -R, --restart-all  restart randr-fix AND lock-guard (starts whichever is not running)
randr-fix --status        running? settings, whether the layout is right now, latest log lines
randr-fix --once          reassert now
randr-fix --detect        print a config for the monitors connected right now
randr-fix --icon-update   save the current icon layout as the "golden" copy (old one backed up)
randr-fix --icon-clean    delete the golden-copy backups
```

How it behaves:

* Waits `DEBOUNCE` seconds after the *last* monitor event, so one power cycle is one run.
* Does nothing while the monitors are asleep, and nothing if the primary is not connected;
  the next RandR event retries. If only the secondary is missing it waits `SECONDARY_WAIT`
  seconds for it, then carries on with the primary alone.
* Only runs `xrandr` when the layout (mode, position, primary flag, refresh rate) is actually
  wrong, so its own changes cannot trigger an endless loop.
* Icons (Xfce): desktop icons are restored only after the primary monitor is confirmed to be
  primary at its configured position, so icons are never pushed onto the secondary. It quits
  `xfdesktop`, copies the golden `icons.screen0.yaml` back and starts `xfdesktop` again,
  at most once per `ICON_COOLDOWN` seconds.
* Move icons on purpose? Run `randr-fix --icon-update`; it shows how many lines changed, asks,
  and keeps a timestamped backup of the old golden copy.

Config: `~/.config/randr-fix/config` (`randr-fix --print-config` shows every key).

## lock-guard

```
lock-guard                watch for lock / unlock (what autostart runs, stays in the foreground)
lock-guard -s, --start    start it in the background (nothing happens if it already runs)
lock-guard -S, --stop     stop it (input devices and brightness are put back)
lock-guard -r, --restart  stop, then start (use after changing the config or upgrading)
lock-guard -R, --restart-all  restart lock-guard AND randr-fix (starts whichever is not running)
lock-guard --status       running? settings, the devices it would switch off, current
                          brightness, latest log lines
lock-guard --enable       switch input devices back on and restore brightness now (rescue)
lock-guard --undim        restore the brightness now, while locked (for a compositor keybind)
```

On X11 it listens for `ActiveChanged` on `org.xfce.ScreenSaver` and `org.freedesktop.ScreenSaver`
(configurable); on Wayland it watches for a locker program (`LOCKER_PROCESSES`, default
swaylock gtklock hyprlock waylock i3lock slock xsecurelock). On lock it saves the windows on non-primary monitors (`SAVE_WINDOWS`) and
disables input devices matching `LOCK_DEVICE_PATTERN` (default: every slave pointer except
XTEST; keyboards are not touched). They are enabled again on unlock, when it stops, and when it
starts (so a crash while locked is repaired by the next start). Use `lock-guard --enable` if a
device is ever left disabled.

Config: `~/.config/lock-guard/config`.

The two programs are independent (they only share the saved window positions), so each can be
started, stopped and restarted on its own, which is what you want after changing one config.
After an upgrade both need restarting: `lock-guard -R` (or `randr-fix -R`) does it in one go, and
also starts whichever of the two was not running. The other program is looked up in the same
folder as the one you ran.

In config files, spaces around a key or a value are ignored. A key the program does not know
(a typo) is ignored, but it is written to the log at start-up and shown by `--status`.

### Dimming while locked

```
LOCK_BRIGHTNESS=0.2
```

Dims the monitors while the screen is locked, so a stray key press (a cat on the keyboard) that
wakes them shows a faint lock screen instead of a bright flash. `0.05` is the dimmest allowed
(so the lock screen stays usable), `1.0` does nothing, empty (the default) never touches
brightness. `DIM_OUTPUTS` limits it to named outputs (default: every connected one).

* It uses `xrandr --brightness`, which is software dimming: it scales what is drawn, and the
  monitor's backlight stays as it is, so a very dark room still sees a faint glow. For a real
  backlight change use a hook with `ddcutil` instead (monitors differ in how well DDC/CI works).
* The brightness each output had is saved and put back exactly at unlock, when `lock-guard`
  stops or starts, and by `lock-guard --enable`. A saved value that is not plausible (some
  drivers report `0.0`) is restored as `1.0`, never as a black screen.
* Something else often puts the brightness back: the screensaver's own fade, or the driver when
  the monitors wake from sleep. While the screens are dimmed, a small keeper checks about twice
  a second whether they are still dim and dims them again if not (it logs `brightness was
  reset (...)`). Sleeping monitors are checked only rarely, so a key press that wakes them is
  corrected within about half a second, which is usually before the panel has lit up. If the
  brightness keeps reading back differently right after dimming (a driver quirk), it stops
  hammering after three tries and pauses for 30 seconds.
* If a monitor loses power or is unplugged while locked, the new connection starts at full
  brightness; the keeper dims it again. Tools that set the gamma ramps directly (Redshift,
  gammastep) will fight with this.
* `lock-guard --status` shows the session, the parts in this copy, the settings it parsed, the brightness each output has right now
  and the last log lines, which is the first thing to look at if dimming does not seem to work.

**Wayland dimming.** Software dimming there goes through
[wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) (it must be running; the
brightness is read and set through its D-Bus property with `busctl --user`). For another tool set
both `DIM_COMMAND` (gets the wanted level in `$LEVEL`) and `UNDIM_COMMAND` (must put it back).
Nothing can read the brightness back from a compositor in general, so there is no keeper loop: if
something else resets the brightness while locked, it stays reset.

### Early undim shortcut (optional)

```
UNDIM_KEY=Ctrl+Shift+b
```

Gives you a keyboard shortcut that restores the brightness while the screen is still locked, for
the moments you want the lock screen bright to see what you are doing. Everything else stays the
same: dimmed at lock, restored at unlock. After the shortcut the screens stay bright until the
next lock.

* Write the keys joined by `+`: the modifiers `Ctrl`, `Alt`, `Shift`, `Super` (either side), then
  a key name as `xmodmap -pke` spells it (`b`, `F9`, `XF86MonBrightnessUp`, ...), or a plain
  number, which is a keycode (find it with `xinput test-xi2 --root`, look at `detail:`).
  Hold the modifiers, then press the last key. A single key (`F9`) works too.
* Avoid `Ctrl+Alt+F1` ... `F12`: the system switches to a text console on those.
* Key names are looked up with `xmodmap -pke` when `xmodmap` is installed. Without it a built-in
  table of the standard X11 keycodes is used: `Ctrl`, `Shift`, `Alt`, `Super`, letters `a`-`z`,
  `F1`-`F12`, `space`, `Return`, `Escape`, `Tab`, `BackSpace`, `Home`, `End`, `Insert`, `Delete`,
  `Page_Up`, `Page_Down` and the arrow keys (`Up` `Down` `Left` `Right`). Letters follow the
  physical key position of a QWERTY keyboard; on another layout, or for keys not listed (digits,
  `XF86...`), use keycodes. A bare number is always a keycode, so write `11` for the key `1`.
  `lock-guard --status` shows how the shortcut resolves, and the log says so if a key name is
  not found.
* **Privacy:** the lock screen owns the keyboard, so an ordinary hotkey cannot work there. The
  shortcut therefore listens to raw keyboard events (`xinput test-xi2 --root`) while the screen
  is dimmed and locked, which includes the password being typed. The events go straight into
  `awk`, which only tracks which keys are down and prints a line when the shortcut is complete.
  Nothing else is stored, logged or passed on, and the listener stops at unlock, when
  `lock-guard` stops, and by `--enable`. It is off unless you set `UNDIM_KEY`; pick a combination
  you never type in a password.
* It starts only if `LOCK_BRIGHTNESS` is set and the screens really were dimmed.
* **Wayland:** the same setting works through `libinput debug-events --show-keycodes`, which needs
  read access to `/dev/input` (root, or membership of the `input` group); if it cannot read the
  keyboards the log says so (`the key listener ended by itself`). Numbers are still the X keycodes
  (the evdev code from `libinput` plus 8, so the `b` key is 56 everywhere).
* **Without raw key listening:** `lock-guard --undim` does the same thing on demand. If your
  compositor can run a command from a key binding that still works while the lock screen is up,
  bind that command and leave `UNDIM_KEY` empty. Whether a binding works on a lock screen depends
  on the compositor and the locker; try it.

### Lock / unlock commands (hooks)

`LOCK_COMMAND` and `UNLOCK_COMMAND` run a command when the screen locks / unlocks. Example with
OpenRGB profiles (a profile that switches the RAM lights off, and your normal one):

```
LOCK_COMMAND=openrgb --profile Night
UNLOCK_COMMAND=openrgb --profile Day
```

* Commands run through `sh -c` in a separate worker, strictly one at a time and in order, so a
  slow or hung command never delays switching your input devices back on, and lock followed
  quickly by unlock cannot run out of order.
* `HOOK_TIMEOUT` (default 20 s) stops a hung command when a `timeout` tool exists (GNU
  coreutils or busybox); without one a hung command is simply left running.
* Output and exit status go to the log. A failing command does not stop the next one.
* Hooks do not run at start-up or shutdown: if `lock-guard` stops while the screen is locked, the
  unlock command is not run.
* Without an OpenRGB server running, every `openrgb` call scans the hardware itself and can
  take a few seconds; starting `openrgb --server` at login makes hooks quicker.

## Security notes

* Runtime files (window positions, logs, pid files, locks) live in a private `0700` directory:
  `$XDG_RUNTIME_DIR/screen-guard`, or `$TMPDIR/screen-guard-UID` when that is unset. Symlinks
  and directories owned by someone else are refused. Nothing is written to a fixed `/tmp` name.
* Config files are *parsed*, not sourced: only the documented keys are read. The one exception
  is by design: `LOCK_COMMAND` / `UNLOCK_COMMAND` are executed (`sh -c`), so keep
  `~/.config/lock-guard/config` writable only by you. Leave them empty and nothing is executed.
* Nothing is passed through `eval` except assignments to those known keys; window titles are
  never stored or used. Window IDs and numbers read back from the positions file are validated
  before they reach `wmctrl`.
* `pgrep` for `xfdesktop` is limited to your own user.
* Logs are capped (rotated at 100 KB) and contain no window titles.

## Portability

Everything is POSIX sh plus common tools; it passes its tests under dash, bash (also `--posix`)
and busybox ash. Things that are not strictly POSIX but available on Linux/BSD: `date +%s`,
fractional `sleep` (falls back to whole seconds), `pgrep -u/-x`, `mkfifo`, `ps -o args=`, `stdbuf`
and `timeout` (both optional). The Xfce-specific parts are the icon restore and the default
screensaver interface; others work with `ICON_RESTORE=no`. Window handling on X11 needs an EWMH
window manager (for `wmctrl`). No Python, no compiled code, and nothing depends on the init system
(systemd, OpenRC, shepherd and others only differ in how you start it at login).

## Tests

`sh test/test.sh` (try `SH=dash`, `SH=bash`, `SH="busybox sh"`). Fake X tools, `busctl`, `libinput` and
`pgrep` are used, so no display or compositor is needed. The suite includes a real `xinput list`
as a fixture and installs into scratch directories for three pretend machines (Debian + oxwm,
Guix + mango, Gentoo with both).

## Known limits

* Written and tested on one Xfce/Gentoo machine; the Wayland parts have only been run against
  stand-ins (see "Environments"); the xfdesktop restart and `icons.screen0.yaml`
  name follow that setup (other xfdesktop versions may name the file differently: set `ICON_FILE`).
* Windows are restored by saved geometry only; windows that moved to another workspace or were
  closed are not tracked.

## License

GNU General Public License v3.0, see [LICENSE](LICENSE).
