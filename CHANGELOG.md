# Changelog

## 1.0.0 - 2026-10

First public release.

- `lock-guard`: switches off chosen input devices while the screen is locked, optionally dims the
  monitors, saves window positions for `randr-fix`, runs your lock / unlock commands.
- `randr-fix` (X11): puts the monitor layout, window positions and Xfce desktop icons back after
  the monitors are switched off and on.
- Early undim shortcut (`UNDIM_KEY`, or `lock-guard --undim` from a keybind).
- One file per program with parts for X11, Wayland, D-Bus lock detection and locker-process
  detection; the installer detects the machine and removes the parts you do not need. Autostart
  through xdg, systemd, a Guix/shepherd sketch, or your window manager's startup commands.
- `install.sh --check-update` / `--update`.
- Start / stop / restart / restart-all (`-s -S -r -R`), `--status`, config files that are parsed
  and never executed (except the lock / unlock commands you write yourself).
