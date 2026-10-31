# Changelog

## 1.1.1 - 2026-10

- `--update` no longer silently drops a part that is new since the install: it is added when the
  machine can use it (e.g. `ddc` with `ddcutil` present), otherwise a line says how to add it.
  Parts pruned on purpose stay pruned. The install record now lists the parts it knew (`PARTS=`);
  records from 1.0.x are read as the four parts that existed then.

## 1.1.0 - 2026-10

- New optional `ddc` part: `LOCK_BACKLIGHT` lowers the monitors' real backlight over DDC/CI
  (`ddcutil`) on lock and restores each monitor's saved value at unlock, on X11 and Wayland.
  `BACKLIGHT_BUSES` and `DDCUTIL_OPTIONS` choose monitors and options. Runs in an ordered
  background worker, retries the restore while a monitor sleeps, repairs a crash at the next start.
- `UNDIM_KEY` and `lock-guard --undim` restore the backlight as well.
- The installer offers `ddc` (kept by default when `ddcutil` is installed) and checks the
  `i2c` group and `/dev/i2c-*`.

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
