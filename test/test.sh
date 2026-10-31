#!/bin/sh
# screen-guard tests.  Fake X tools (xrandr, xset, xinput, wmctrl, xprop, xev, dbus-monitor,
# xfdesktop, pgrep) are put first in PATH, so no display is needed.
#   sh test/test.sh            (SH=dash sh test/test.sh   to pick the shell under test)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
SH=${SH:-sh}
PASS=0
FAIL=0

check() {   # check "description" command...
    _d=$1; shift
    if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$_d"; fi
}
has()    { grep -q -- "$2" "$1" 2>/dev/null; }
hasnt()  { ! grep -q -- "$2" "$1" 2>/dev/null; }
count()  { [ "$(grep -c -- "$2" "$1" 2>/dev/null)" = "$3" ]; }
same()   { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; }
# raw XInput2 key events as printed by 'xinput test-xi2 --root'
kp() { printf 'EVENT type 13 (RawKeyPress)\n    device: 3 (10)\n    time:   1\n    detail: %s\n    valuators:\n\n' "$1"; }
kr() { printf 'EVENT type 14 (RawKeyRelease)\n    device: 3 (10)\n    time:   2\n    detail: %s\n    valuators:\n\n' "$1"; }
mo() { printf 'EVENT type 17 (RawMotion)\n    device: 2 (13)\n    time:   3\n    detail: 0\n    flags:\n    valuators:\n          0: 0.20 (1.00)\n\n'; }

# ------------------------------------------------------------------------------ fixtures
fresh() {
    TMP=$(mktemp -d)
    STUB=$TMP/stub; mkdir -p "$STUB" "$TMP/bin" "$TMP/run" "$TMP/home/.config/randr-fix" "$TMP/home/.config/lock-guard" "$TMP/home/.config/xfce4/desktop"
    chmod 700 "$TMP/run"
    HOME=$TMP/home; XDG_CONFIG_HOME=$HOME/.config; XDG_RUNTIME_DIR=$TMP/run
    export STUB HOME XDG_CONFIG_HOME XDG_RUNTIME_DIR
    PATH=$TMP/bin:$ORIGPATH; export PATH
    RD=$XDG_RUNTIME_DIR/screen-guard
    cp "$HERE/fixtures/xrandr-dual.txt" "$STUB/xrandr.state"
    cp "$HERE/fixtures/xinput-list.txt" "$STUB/xinput.list"
    cp "$HERE/fixtures/wmctrl-list.txt" "$STUB/wmctrl.list"
    cp "$HERE/fixtures/xrandr-verbose.txt" "$STUB/xrandr.verbose"
    cp "$HERE/fixtures/xmodmap-pke.txt" "$STUB/xmodmap.pke"
    printf 'DPMS (Display Power Management Signaling):\n  Standby: 1140    Suspend: 0    Off: 1200\n  DPMS is Enabled\n  Monitor is On\n' > "$STUB/xset.out"
    printf '0x02000005\n' > "$STUB/iconic"
    printf '0x02000007\n' > "$STUB/maxed"
    touch "$STUB/xfd.running"
    cat > "$XDG_CONFIG_HOME/randr-fix/config" <<EOF
PRIMARY_OUTPUT=DisplayPort-0
PRIMARY_MODE=1920x1080
PRIMARY_RATE=144
PRIMARY_POS=0x0
SECONDARY_OUTPUT=HDMI-A-1-1
SECONDARY_MODE=1920x1080
SECONDARY_RATE=60
SECONDARY_POS=1920x0
DEBOUNCE=1
SECONDARY_WAIT=2
EOF
    : > "$XDG_CONFIG_HOME/lock-guard/config"
    cat > "$TMP/bin/xrandr" <<'EOF'
#!/bin/sh
case " $* " in
  *" --verbose "*)
      awk -v f="$STUB/bright.txt" '
          BEGIN { while ((getline l < f) > 0) { split(l, a, " "); ov[a[1]] = a[2] } }
          /^[^ \t]/ { cur = $1 }
          $1 == "Brightness:" && (cur in ov) { print "\tBrightness: " ov[cur]; next }
          { print }' "$STUB/xrandr.verbose" ;;
  *" --output "*)
      echo "$*" >> "$STUB/xrandr.calls"
      out=
      while [ $# -gt 0 ]; do
          case $1 in
              --output) out=$2; shift ;;
              --brightness) [ -f "$STUB/no-bright" ] || echo "$out $2" >> "$STUB/bright.txt"; shift ;;
          esac
          shift
      done
      if [ -f "$STUB/xrandr.after" ]; then cp "$STUB/xrandr.after" "$STUB/xrandr.state"; fi ;;
  *) cat "$STUB/xrandr.state" ;;
esac
EOF
    cat > "$TMP/bin/xset" <<'EOF'
#!/bin/sh
cat "$STUB/xset.out"
EOF
    cat > "$TMP/bin/wmctrl" <<'EOF'
#!/bin/sh
case $1 in -lG) cat "$STUB/wmctrl.list" ;; *) echo "$*" >> "$STUB/wmctrl.calls" ;; esac
EOF
    cat > "$TMP/bin/xprop" <<'EOF'
#!/bin/sh
case $3 in
  WM_STATE) if grep -qx "$2" "$STUB/iconic" 2>/dev/null; then echo "WM_STATE(WM_STATE):  window state: Iconic"; else echo "WM_STATE(WM_STATE):  window state: Normal"; fi ;;
  _NET_WM_STATE) if grep -qx "$2" "$STUB/maxed" 2>/dev/null; then echo "_NET_WM_STATE(ATOM) = _NET_WM_STATE_MAXIMIZED_VERT, _NET_WM_STATE_MAXIMIZED_HORZ"; else echo "_NET_WM_STATE(ATOM) = "; fi ;;
esac
EOF
    cat > "$TMP/bin/xinput" <<'EOF'
#!/bin/sh
case $1 in
  list) cat "$STUB/xinput.list" ;;
  enable|disable) echo "$1 $2" >> "$STUB/xinput.calls" ;;
  test-xi2) echo "test-xi2 $*" >> "$STUB/xi2.calls"; cat "$STUB/xi2.script" 2>/dev/null; sleep 100 ;;
esac
EOF
    cat > "$TMP/bin/xmodmap" <<'EOF'
#!/bin/sh
case $1 in -pke) cat "$STUB/xmodmap.pke" ;; esac
EOF
    cat > "$TMP/bin/dbus-monitor" <<'EOF'
#!/bin/sh
echo "$*" > "$STUB/dbus.args"
sleep "${DBUS_DELAY:-0}"
cat "$STUB/dbus.script" 2>/dev/null
exec sleep 100
EOF
    cat > "$TMP/bin/xev" <<'EOF'
#!/bin/sh
cat "$STUB/xev.script" 2>/dev/null
exec sleep 100
EOF
    cat > "$TMP/bin/xfdesktop" <<'EOF'
#!/bin/sh
case $1 in --quit) echo quit >> "$STUB/xfd.calls"; rm -f "$STUB/xfd.running" ;; *) echo start >> "$STUB/xfd.calls"; touch "$STUB/xfd.running" ;; esac
EOF
    cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
case " $* " in
  *swaylock*) [ -f "$STUB/locker.running" ] ;;
  *) [ -f "$STUB/xfd.running" ] ;;
esac
EOF
    cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/sh
case $2 in
  get-property) echo "d $(cat "$STUB/gamma" 2>/dev/null || echo 1)" ;;
  set-property) echo "$8" >> "$STUB/busctl.calls"; echo "$8" > "$STUB/gamma" ;;
esac
EOF
    cat > "$TMP/bin/libinput" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB/li.calls"
cat "$STUB/li.script" 2>/dev/null
[ -f "$STUB/li.die" ] && exit 1
exec sleep 100
EOF
    chmod +x "$TMP"/bin/*
}

rf() { $SH "$ROOT/randr-fix" "$@"; }
lg() { $SH "$ROOT/lock-guard" "$@"; }
# the fake 'xinput test-xi2' listener (anchored, so a wrapper shell mentioning it does not count)
listener_gone() { ! "$REALPGREP" -f "^/bin/sh $TMP/bin/xinput test-xi2" >/dev/null 2>&1; }
done_with() { pkill -f "$TMP/bin/xev" 2>/dev/null; pkill -f "$TMP/bin/dbus-monitor" 2>/dev/null; pkill -f '^sleep 100$' 2>/dev/null; rm -rf "$TMP"; }

ORIGPATH=$PATH
export ORIGPATH
REALPGREP=$(command -v pgrep)     # the fake pgrep in the test PATH hides the real one
chmod +x "$ROOT/randr-fix" "$ROOT/lock-guard" 2>/dev/null
echo "shell under test: $SH"

# ============================================================================ lock-guard
fresh
check "lock-guard --version" test "$(lg -V)" = "lock-guard 1.0.0"
check "lock-guard --print-config has keys" sh -c "$SH $ROOT/lock-guard -p | grep -q '^SCREENSAVER_INTERFACES='"

# default pattern: the user's real device list -> only the slave pointer (id 13), not XTEST / keyboards
cat > "$STUB/dbus.script" <<'EOF'
signal time=1.1 sender=:1.5 -> destination=(null destination) serial=3 path=/org/xfce/ScreenSaver; interface=org.xfce.ScreenSaver; member=ActiveChanged
   boolean true
signal time=1.2 sender=:1.5 -> destination=(null destination) serial=4 path=/org/freedesktop/ScreenSaver; interface=org.freedesktop.ScreenSaver; member=ActiveChanged
   boolean true
signal time=1.3 sender=:1.5 -> destination=(null destination) serial=5 path=/org/xfce/ScreenSaver; interface=org.xfce.ScreenSaver; member=SomethingElse
   boolean true
signal time=2.1 sender=:1.5 -> destination=(null destination) serial=6 path=/org/xfce/ScreenSaver; interface=org.xfce.ScreenSaver; member=ActiveChanged
   boolean false
signal time=2.2 sender=:1.5 -> destination=(null destination) serial=7 path=/org/freedesktop/ScreenSaver; interface=org.freedesktop.ScreenSaver; member=ActiveChanged
   boolean false
EOF
lg >/dev/null 2>&1 &
sleep 2
check "lock-guard: listens on both interfaces" has "$STUB/dbus.args" "org.xfce.ScreenSaver"
check "lock-guard: listens on freedesktop interface" has "$STUB/dbus.args" "org.freedesktop.ScreenSaver"
check "lock-guard: locked exactly once (duplicate + foreign signal ignored)" count "$RD/lock-guard.log" "screen locked" 1
check "lock-guard: unlocked exactly once" count "$RD/lock-guard.log" "screen unlocked" 1
check "lock-guard: disabled the mouse (id 13)" has "$STUB/xinput.calls" "^disable 13$"
check "lock-guard: only one device disabled by default" count "$STUB/xinput.calls" "^disable" 1
check "lock-guard: never touches keyboards by default" hasnt "$STUB/xinput.calls" " 17$"
check "lock-guard: never touches XTEST (id 4)" hasnt "$STUB/xinput.calls" " 4$"
check "lock-guard: re-enabled the mouse on unlock" has "$STUB/xinput.calls" "^enable 13$"
check "lock-guard: saved secondary windows only (3)" same "$RD/window-positions" "0x02000004 2000 100 900 700 0
0x02000007 1920 0 1920 1080 1
0x02000008 1700 100 800 600 0"
check "lock-guard: single instance guard" sh -c "$SH $ROOT/lock-guard 2>&1 | grep -q 'already running'"
: > "$STUB/xinput.calls"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
check "lock-guard: re-enables input when stopped" has "$STUB/xinput.calls" "^enable 13$"
check "lock-guard: cleans its pid/fifo" test ! -e "$RD/lock-guard.pid" -a ! -e "$RD/lock-guard.fifo"
check "runtime dir is mode 700" sh -c "ls -ld $RD | grep -q '^drwx------'"
done_with

# pattern selects every interface of one vendor, still no keyboards of other vendors
fresh
printf 'LOCK_DEVICE_PATTERN=acme\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2; kill "$(cat "$RD/lock-guard.pid")"; sleep 1
for id in 13 15 22 14; do check "pattern: disables id $id" has "$STUB/xinput.calls" "^disable $id$"; done
check "pattern: leaves the Example keyboard (17) alone" hasnt "$STUB/xinput.calls" "^disable 17$"
check "pattern: leaves the Compact Board (10) alone" hasnt "$STUB/xinput.calls" "^disable 10$"
done_with

# SAVE_WINDOWS=all, DISABLE_INPUT=no
fresh
printf 'SAVE_WINDOWS=all\nDISABLE_INPUT=no\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2; kill "$(cat "$RD/lock-guard.pid")"; sleep 1
check "SAVE_WINDOWS=all keeps the primary window too" has "$RD/window-positions" "^0x01000003 "
check "SAVE_WINDOWS=all still skips minimised and sticky" hasnt "$RD/window-positions" "0x02000005\|0x02000006"
check "DISABLE_INPUT=no touches no device" test ! -s "$STUB/xinput.calls"
done_with

# hooks: LOCK_COMMAND / UNLOCK_COMMAND (e.g. OpenRGB profiles)
LOCKSEQ='signal time=1 member=ActiveChanged
   boolean true
signal time=2 member=ActiveChanged
   boolean false'
fresh
printf 'LOCK_COMMAND=echo lock-ran >> %s/hook.calls\nUNLOCK_COMMAND="echo unlock-ran >> %s/hook.calls"\n' "$STUB" "$STUB" > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "hooks: lock then unlock, in order" same "$STUB/hook.calls" "lock-ran
unlock-ran"
check "hooks: logged with exit status" count "$RD/lock-guard.log" "finished (exit 0)" 2
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
check "hooks: fifo removed on stop" test ! -e "$RD/lock-guard.hooks"
done_with

fresh
printf 'LOCK_DEVICE_PATTERN=acme\nLOCK_COMMAND=sleep 3; echo lock-ran >> %s/hook.calls\nUNLOCK_COMMAND=echo unlock-ran >> %s/hook.calls\n' "$STUB" "$STUB" > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 1.5
check "slow hook does not delay re-enabling the mouse" has "$STUB/xinput.calls" "^enable 13$"
check "slow hook is still running at that point" test ! -s "$STUB/hook.calls"
sleep 4
check "slow hook: order kept (lock before unlock)" same "$STUB/hook.calls" "lock-ran
unlock-ran"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'HOOK_TIMEOUT=1\nLOCK_COMMAND=sleep 8\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 3.5
check "hook timeout stops a hung command" has "$RD/lock-guard.log" "hook lock finished (exit \(124\|143\))"
check "hung hook did not stop the unlock handling" has "$RD/lock-guard.log" "screen unlocked"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_COMMAND=false\nUNLOCK_COMMAND=echo after-failure >> %s/hook.calls\n' "$STUB" > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "failing hook is logged" has "$RD/lock-guard.log" "hook lock finished (exit 1)"
check "failing hook does not stop the next one" has "$STUB/hook.calls" "after-failure"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'HOOK_TIMEOUT=soon\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "bad HOOK_TIMEOUT is rejected" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'HOOK_TIMEOUT must be'"
printf 'DISABLE_INPUT=yes\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "no hooks configured: no hook fifo" test ! -e "$RD/lock-guard.hooks"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# a hook worker that dies must not take the event loop down with it (Linux /proc needed)
if [ -d /proc/self/fd ] && [ -n "$REALPGREP" ]; then
    fresh
    printf 'LOCK_DEVICE_PATTERN=acme\nLOCK_COMMAND=echo lock-ran >> %s/hook.calls\n' "$STUB" > "$XDG_CONFIG_HOME/lock-guard/config"
    printf '%s\n' "$LOCKSEQ" > "$STUB/dbus.script"
    DBUS_DELAY=3; export DBUS_DELAY
    lg >/dev/null 2>&1 &
    sleep 1
    MAIN=$(cat "$RD/lock-guard.pid")
    KILLED=0
    for c in $("$REALPGREP" -P "$MAIN"); do
        if [ "$(readlink "/proc/$c/fd/0" 2>/dev/null)" = "$RD/lock-guard.hooks" ]; then kill -9 "$c"; KILLED=1; fi
    done
    check "dead hook worker: worker found and killed" test "$KILLED" = 1
    sleep 4
    check "dead hook worker: loop still disables input" has "$STUB/xinput.calls" "^disable 13$"
    check "dead hook worker: loop still handles unlock" has "$RD/lock-guard.log" "screen unlocked"
    kill "$MAIN"; sleep 1
    unset DBUS_DELAY
    done_with
fi

# dimming: LOCK_BRIGHTNESS
DIMSEQ='signal time=1 member=ActiveChanged
   boolean true
signal time=2 member=ActiveChanged
   boolean false'
fresh
printf '%s\n' "$DIMSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: off by default (no brightness call)" test ! -e "$STUB/xrandr.calls"
check "dim: no state file when off" test ! -e "$RD/dim-state"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$DIMSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: dims every connected output in one call" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --brightness 0.2 --output HDMI-A-1-1 --brightness 0.2$"
check "dim: skips disconnected outputs" hasnt "$STUB/xrandr.calls" "DisplayPort-1"
check "dim: restores each output's own original (0.9 kept)" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9$"
check "dim: restore happens after the dim" same "$STUB/xrandr.calls" "--output DisplayPort-0 --brightness 0.2 --output HDMI-A-1-1 --brightness 0.2
--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9"
check "dim: state file removed after restore" test ! -e "$RD/dim-state"
check "dim: logged with the output names" has "$RD/lock-guard.log" "dimmed to 0.2: DisplayPort-0 HDMI-A-1-1"
check "dim: restore logged" has "$RD/lock-guard.log" "brightness restored"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# implausible original (some drivers report 0.0): restored as 1.0, never as a black screen
fresh
sed 's/Brightness: 0.9/Brightness: 0.0/' "$STUB/xrandr.verbose" > "$STUB/v.tmp" && mv "$STUB/v.tmp" "$STUB/xrandr.verbose"
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$DIMSEQ" > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: an original of 0.0 is restored as 1.0" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 1.0$"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.3\nDIM_OUTPUTS=HDMI-A-1-1\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: DIM_OUTPUTS limits the outputs" same "$STUB/xrandr.calls" "--output HDMI-A-1-1 --brightness 0.3"
check "dim: state file holds only the dimmed output" same "$RD/dim-state" "HDMI-A-1-1 0.9"
: > "$STUB/xrandr.calls"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
check "dim: stopping while locked restores brightness" same "$STUB/xrandr.calls" "--output HDMI-A-1-1 --brightness 0.9"
check "dim: state file gone after stop" test ! -e "$RD/dim-state"
done_with

# a restart while the screens are dimmed (crash, kill -9) repairs them; --enable does too
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
mkdir -p "$RD"; chmod 700 "$RD"
printf 'DisplayPort-0 1.0\nHDMI-A-1-1 0.9\n' > "$RD/dim-state"
lg --enable >/dev/null 2>&1
check "dim: --enable restores brightness" same "$STUB/xrandr.calls" "--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9"
check "dim: --enable clears the state file" test ! -e "$RD/dim-state"
rm -f "$STUB/xrandr.calls"
printf 'DisplayPort-0 1.0\nHDMI-A-1-1 0.9\n' > "$RD/dim-state"
printf '' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: starting up restores a leftover dim" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9$"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# a second lock signal while dimmed must not overwrite the saved originals with the dimmed values
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\nsignal time=2 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "dim: duplicate lock signals dim only once" count "$STUB/xrandr.calls" "brightness 0.2" 1
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
for bad in abc 1.5 0.01 -1 0.5.5 .; do
    printf 'LOCK_BRIGHTNESS=%s\n' "$bad" > "$XDG_CONFIG_HOME/lock-guard/config"
    check "dim: LOCK_BRIGHTNESS=$bad is rejected" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'LOCK_BRIGHTNESS must be'"
done
for good in 0.05 0.2 .5 1 1.0 0.25; do
    printf 'LOCK_BRIGHTNESS=%s\n' "$good" > "$XDG_CONFIG_HOME/lock-guard/config"
    check "dim: LOCK_BRIGHTNESS=$good is accepted" sh -c "! $SH $ROOT/lock-guard --enable 2>&1 | grep -q 'LOCK_BRIGHTNESS must be'"
done
done_with

# dim keeper: something else (screensaver fade, driver on wake) puts the brightness back
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "keeper: dimmed once so far" count "$STUB/xrandr.calls" "brightness 0.2" 1
echo "DisplayPort-0 1.0" >> "$STUB/bright.txt"            # something resets one monitor
sleep 2
check "keeper: dims again after a reset" count "$STUB/xrandr.calls" "brightness 0.2" 2
check "keeper: logs what was reset" has "$RD/lock-guard.log" "brightness was reset (DisplayPort-0=1.0) - dimmed again"
sleep 2
check "keeper: does not keep re-dimming a correct screen" count "$STUB/xrandr.calls" "brightness 0.2" 2
printf 'DPMS (Display Power Management Signaling):\n  Standby: 1140    Suspend: 0    Off: 1200\n  DPMS is Enabled\n  Monitor is Off\n' > "$STUB/xset.out"
echo "HDMI-A-1-1 1.0" >> "$STUB/bright.txt"
sleep 2
check "keeper: leaves sleeping monitors alone" count "$STUB/xrandr.calls" "brightness 0.2" 2
printf 'DPMS (Display Power Management Signaling):\n  Standby: 1140    Suspend: 0    Off: 1200\n  DPMS is Enabled\n  Monitor is On\n' > "$STUB/xset.out"
sleep 2
check "keeper: dims as soon as the monitors are on again" count "$STUB/xrandr.calls" "brightness 0.2" 3
kill "$(cat "$RD/lock-guard.pid")"; sleep 1.5
check "keeper: stopping restores and nothing re-dims afterwards" same "$STUB/xrandr.calls" "$(grep 'brightness 0.2' "$STUB/xrandr.calls")
--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9"
done_with

# a screen that never stays dimmed (or reads back wrongly) must not make the keeper spin
fresh
touch "$STUB/no-bright"
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 6
check "keeper: gives up after 3 quick re-dims (1 + 3 calls)" count "$STUB/xrandr.calls" "brightness 0.2" 4
check "keeper: says it is pausing" has "$RD/lock-guard.log" "pausing the check for 30 s"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# unlock: restore wins, and the keeper does not undo it
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\nsignal time=2 member=ActiveChanged\n   boolean false\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 3.5
check "keeper: after unlock the screens stay restored" count "$STUB/xrandr.calls" "brightness 0.2" 1
check "keeper: no keeper state left after unlock" test ! -e "$RD/dim-keeper" -a ! -e "$RD/dim-state" -a ! -e "$RD/dim.lock"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# lock, unlock and lock again quickly: only the newest keeper is valid
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\nsignal time=2 member=ActiveChanged\n   boolean false\nsignal time=3 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2.5
check "keeper: second lock dims again" count "$STUB/xrandr.calls" "brightness 0.2" 2
check "keeper: newest keeper token is current" sh -c "grep -q -- '-2$' $RD/dim-keeper"
sleep 1
# main + event loop + ONE keeper = 3 processes; the minimum of several samples ignores momentary
# forks (command substitutions), so two keepers would show up as 4
MINP=99
for _k in 1 2 3 4 5 6; do
    _n=$("$REALPGREP" -f -c "^([^ ]*/)?(sh|dash|bash|busybox)( [^ ]+)? $ROOT/lock-guard( |$)")
    [ "$_n" -lt "$MINP" ] && MINP=$_n
    sleep 0.15
done
check "keeper: the old keeper exits, only one runs (got $MINP processes)" test "$MINP" = 3
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# a stale dim lock (holder killed) does not wedge dimming
fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
mkdir -p "$RD"; chmod 700 "$RD"; mkdir "$RD/dim.lock"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 14
check "keeper: a stale lock is broken and dimming happens" has "$STUB/xrandr.calls" "brightness 0.2"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# --start / --stop / --restart / --status : lock-guard
fresh
printf 'LOCK_BRIGHTNESS=0.2\nLOCK_DEVICE_PATTERN=acme\n' > "$XDG_CONFIG_HOME/lock-guard/config"
: > "$STUB/dbus.script"
lg --status > "$TMP/st0" 2>&1; RC=$?
check "status: not running" has "$TMP/st0" "lock-guard is not running"
check "status: exit code 3 when not running" test "$RC" = 3
check "status: shows the settings" has "$TMP/st0" "LOCK_BRIGHTNESS=0.2"
check "status: lists the devices it would switch off" has "$TMP/st0" "input devices it would switch off: 13 22 15 14"
check "status: shows current brightness" has "$TMP/st0" "brightness now: DisplayPort-0=1.0 HDMI-A-1-1=0.9"
lg --stop > "$TMP/stp0" 2>&1
check "stop when not running is harmless" has "$TMP/stp0" "not running"
lg --start > "$TMP/s1" 2>&1
check "start: reports the pid" sh -c "grep -q 'lock-guard started (pid [0-9]*)' $TMP/s1"
P1=$(cat "$RD/lock-guard.pid" 2>/dev/null)
check "start: pid file names a live process" kill -0 "$P1"
lg --start > "$TMP/s2" 2>&1
check "start twice: refused, nothing duplicated" has "$TMP/s2" "already running (pid $P1)"
lg --status > "$TMP/st1" 2>&1; RC=$?
check "status: running" has "$TMP/st1" "lock-guard is running (pid $P1)"
check "status: exit code 0 when running" test "$RC" = 0
lg --restart > "$TMP/r1" 2>&1
P2=$(cat "$RD/lock-guard.pid" 2>/dev/null)
check "restart: a new process" test -n "$P2" -a "$P2" != "$P1"
check "restart: the old one is gone" sh -c "! kill -0 $P1 2>/dev/null"
check "restart: stopped then started" sh -c "grep -q 'lock-guard stopped' $TMP/r1 && grep -q 'lock-guard started' $TMP/r1"
: > "$STUB/xinput.calls"
lg --stop > "$TMP/stp1" 2>&1
check "stop: says stopped" has "$TMP/stp1" "lock-guard stopped"
check "stop: process gone" sh -c "! kill -0 $P2 2>/dev/null"
check "stop: pid file removed" test ! -e "$RD/lock-guard.pid"
check "stop: input switched back on" has "$STUB/xinput.calls" "^enable 13$"
lg --restart > "$TMP/r2" 2>&1
check "restart when not running just starts" has "$TMP/r2" "lock-guard started"
lg --stop >/dev/null 2>&1
done_with

# stop must work even when the watcher ignores SIGTERM (falls back to kill -9 and repairs state)
fresh
mkdir -p "$RD"; chmod 700 "$RD"
printf 'trap "" TERM\nwhile :; do sleep 1; done\n' > "$TMP/lock-guard-stuck"
sh "$TMP/lock-guard-stuck" &
STUCK=$!
sleep 0.5
echo "$STUCK" > "$RD/lock-guard.pid"
printf 'DisplayPort-0 1.0\nHDMI-A-1-1 0.9\n' > "$RD/dim-state"
lg --stop > "$TMP/stk" 2>&1
check "stop: a stuck watcher is killed" sh -c "! kill -0 $STUCK 2>/dev/null"
check "stop: says it had to kill it" has "$TMP/stk" "did not stop in 5 s and was killed"
check "stop: repairs brightness after a kill" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9$"
check "stop: repairs input after a kill" has "$STUB/xinput.calls" "^enable 13$"
done_with

# a bad config makes --start fail loudly instead of pretending
fresh
printf 'LOCK_BRIGHTNESS=banana\n' > "$XDG_CONFIG_HOME/lock-guard/config"
lg --start > "$TMP/bad" 2>&1; RC=$?
check "start: bad config is refused" test "$RC" != 0
check "start: says why" has "$TMP/bad" "LOCK_BRIGHTNESS must be"
done_with

# --start / --stop / --restart / --status : randr-fix
fresh
rf --status > "$TMP/rs0" 2>&1; RC=$?
check "randr-fix status: not running (exit 3)" test "$RC" = 3 && has "$TMP/rs0" "randr-fix is not running"
check "randr-fix status: layout reported" has "$TMP/rs0" "layout: as configured"
check "randr-fix status: settings shown" has "$TMP/rs0" "primary DisplayPort-0 1920x1080 @ 144 Hz at 0x0; secondary HDMI-A-1-1 at 1920x0"
rf --start > "$TMP/rs1" 2>&1
check "randr-fix start: reports the pid" sh -c "grep -q 'randr-fix started (pid [0-9]*)' $TMP/rs1"
Q1=$(cat "$RD/randr-fix.pid" 2>/dev/null)
rf --start > "$TMP/rs2" 2>&1
check "randr-fix start twice: refused" has "$TMP/rs2" "already running (pid $Q1)"
rf --restart > "$TMP/rs3" 2>&1
Q2=$(cat "$RD/randr-fix.pid" 2>/dev/null)
check "randr-fix restart: new process, old one gone" sh -c "test -n '$Q2' && test '$Q2' != '$Q1' && ! kill -0 $Q1 2>/dev/null"
rf --stop > "$TMP/rs4" 2>&1
check "randr-fix stop: stopped and cleaned" sh -c "grep -q 'randr-fix stopped' $TMP/rs4 && ! kill -0 $Q2 2>/dev/null && test ! -e $RD/randr-fix.pid && test ! -e $RD/randr-fix.fifo"
rf --stop > "$TMP/rs5" 2>&1
check "randr-fix stop when not running is harmless" has "$TMP/rs5" "not running"
done_with

# config: spaces around keys and values are ignored; unknown keys end up in the log and --status
fresh
printf '  LOCK_BRIGHTNESS = 0.2  \n\tDISABLE_INPUT=no\t\nBOGUS=1\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2
check "config: padded key and value are understood (dims)" has "$STUB/xrandr.calls" "brightness 0.2"
check "config: padded DISABLE_INPUT=no is honoured" test ! -s "$STUB/xinput.calls"
check "config: an unknown key is written to the log" has "$RD/lock-guard.log" "config warnings: unknown key 'BOGUS' ignored"
lg --status > "$TMP/stw" 2>&1
check "config: --status shows the warning" has "$TMP/stw" "config warnings: unknown key 'BOGUS' ignored"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# shorthands and restart-all
fresh
: > "$STUB/dbus.script"
lg -s > "$TMP/o1" 2>&1
check "-s starts lock-guard" has "$TMP/o1" "lock-guard started"
lg -s > "$TMP/o2" 2>&1
check "-s twice: already running" has "$TMP/o2" "already running"
lg -r > "$TMP/o3" 2>&1
check "-r restarts lock-guard" sh -c "grep -q stopped $TMP/o3 && grep -q started $TMP/o3"
lg -S > "$TMP/o4" 2>&1
check "-S stops lock-guard" has "$TMP/o4" "lock-guard stopped"
rf -s > "$TMP/o5" 2>&1
check "randr-fix -s starts" has "$TMP/o5" "randr-fix started"
rf -r > "$TMP/o6" 2>&1
check "randr-fix -r restarts" sh -c "grep -q stopped $TMP/o6 && grep -q started $TMP/o6"
rf -S > "$TMP/o7" 2>&1
check "randr-fix -S stops" has "$TMP/o7" "randr-fix stopped"

lg -R > "$TMP/ra1" 2>&1
check "restart-all (from lock-guard) starts both" sh -c "grep -q 'lock-guard started' $TMP/ra1 && grep -q 'randr-fix started' $TMP/ra1"
LP=$(cat "$RD/lock-guard.pid" 2>/dev/null); RP=$(cat "$RD/randr-fix.pid" 2>/dev/null)
rf -R > "$TMP/ra2" 2>&1
LP2=$(cat "$RD/lock-guard.pid" 2>/dev/null); RP2=$(cat "$RD/randr-fix.pid" 2>/dev/null)
check "restart-all (from randr-fix) replaces lock-guard" test -n "$LP2" -a "$LP2" != "$LP"
check "restart-all (from randr-fix) replaces randr-fix" test -n "$RP2" -a "$RP2" != "$RP"
check "restart-all: the old processes are gone" sh -c "! kill -0 $LP 2>/dev/null && ! kill -0 $RP 2>/dev/null"
check "restart-all: both new ones are alive" sh -c "kill -0 $LP2 && kill -0 $RP2"
check "restart-all: long option works too" sh -c "$SH $ROOT/lock-guard --restart-all >/dev/null 2>&1"
lg -S >/dev/null 2>&1; rf -S >/dev/null 2>&1

mkdir "$TMP/alone"; cp "$ROOT/lock-guard" "$TMP/alone/lock-guard"; chmod +x "$TMP/alone/lock-guard"
$SH "$TMP/alone/lock-guard" --restart-all > "$TMP/ra3" 2>&1; RC=$?
check "restart-all: a missing sibling is reported" has "$TMP/ra3" "randr-fix not found next to"
check "restart-all: a missing sibling makes it fail" test "$RC" != 0
check "restart-all: it still restarted itself" has "$TMP/ra3" "lock-guard started"
$SH "$TMP/alone/lock-guard" --stop >/dev/null 2>&1
done_with

# early undim shortcut (UNDIM_KEY)
UK_SIGNAL='signal time=1 member=ActiveChanged
   boolean true'
RESTORE_CALL="^--output DisplayPort-0 --brightness 1.0 --output HDMI-A-1-1 --brightness 0.9$"

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ mo; kp 56; kr 56; kp 37; kp 50; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: Ctrl+Shift+b restores brightness while locked" has "$STUB/xrandr.calls" "$RESTORE_CALL"
check "undim key: only once (the plain b before it did nothing)" count "$STUB/xrandr.calls" "brightness 1.0" 1
check "undim key: logged" has "$RD/lock-guard.log" "undim key pressed - brightness restored early"
sleep 2
check "undim key: the keeper does not dim it again" count "$STUB/xrandr.calls" "brightness 0.2" 1
check "undim key: the listener has been stopped" listener_gone
check "undim key: no dim/listener state left" test ! -e "$RD/undim-key.pids" -a ! -e "$RD/undim-key.fifo" -a ! -e "$RD/dim-state"
check "undim key: no key information in the log" hasnt "$RD/lock-guard.log" "RawKey\|detail"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 105; kp 62; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: the right-hand Ctrl and Shift work too" has "$STUB/xrandr.calls" "$RESTORE_CALL"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
# b alone; modifiers without b; modifier released before b; b held before the modifiers; unrelated keys
{ kp 56; kr 56; kp 37; kp 50; kr 37; kr 50; kp 37; kr 37; kp 56; kr 56; kp 50; kp 96; kr 96; kr 50; kp 56; kp 37; kp 50; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: wrong orders and partial shortcuts do nothing" test ! -e "$STUB/brightness-restored" -a "$(grep -c 'brightness 1.0' "$STUB/xrandr.calls" 2>/dev/null)" = 0
check "undim key: still dimmed and listening" sh -c "test -f $RD/dim-state && test -f $RD/undim-key.pids"
LP=$(cat "$RD/lock-guard.pid")
kill "$LP"; sleep 1.5
check "undim key: stopping lock-guard stops the listener" listener_gone
check "undim key: stopping lock-guard restored the brightness" has "$STUB/xrandr.calls" "$RESTORE_CALL"
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=37+56\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 37; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: plain keycodes work without key names" has "$STUB/xrandr.calls" "$RESTORE_CALL"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=F12\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 96; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: a single key (F12) works" has "$STUB/xrandr.calls" "$RESTORE_CALL"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Nonexistent\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 37; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 2.5
check "undim key: an unknown key name is explained in the log" has "$RD/lock-guard.log" "cannot use 'Ctrl+Nonexistent' - no key called 'Nonexistent'"
check "undim key: nothing listens when the key cannot be resolved" test ! -e "$STUB/xi2.calls"
check "undim key: dimming itself still works" has "$STUB/xrandr.calls" "brightness 0.2"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf 'signal time=1 member=ActiveChanged\n   boolean true\nsignal time=2 member=ActiveChanged\n   boolean false\n' > "$STUB/dbus.script"
{ kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: unlocking stops the listener" listener_gone
check "undim key: unlocking restores brightness as usual" has "$STUB/xrandr.calls" "$RESTORE_CALL"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'LOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 37; kp 50; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 2.5
check "undim key: off by default - no keyboard listener at all" test ! -e "$STUB/xi2.calls"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# a listener left behind by a killed lock-guard is cleaned up
fresh
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=F12\n' > "$XDG_CONFIG_HOME/lock-guard/config"
mkdir -p "$RD"; chmod 700 "$RD"
sleep 200 & ORPHAN=$!
echo "$ORPHAN $ORPHAN" > "$RD/undim-key.pids"
lg --enable >/dev/null 2>&1
sleep 0.5
check "undim key: a leftover listener is killed by --enable" sh -c "! kill -0 $ORPHAN 2>/dev/null"
check "undim key: and its state is removed" test ! -e "$RD/undim-key.pids"
done_with

# without xmodmap (stub prints nothing) the built-in key table is used
fresh
: > "$STUB/xmodmap.pke"
check "undim key: names resolve without xmodmap (built-in table)" sh -c "printf 'UNDIM_KEY=Ctrl+Shift+b\n' > $XDG_CONFIG_HOME/lock-guard/config; $SH $ROOT/lock-guard --status 2>&1 | grep -q 'UNDIM_KEY=Ctrl+Shift+b -> OK 37,105 50,62 56'"
check "undim key: built-in table has the F keys and Super" sh -c "printf 'UNDIM_KEY=Super+Alt+F9\n' > $XDG_CONFIG_HOME/lock-guard/config; $SH $ROOT/lock-guard --status 2>&1 | grep -q 'UNDIM_KEY=Super+Alt+F9 -> OK 133,134 64,108 75'"
printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
printf '%s\n' "$UK_SIGNAL" > "$STUB/dbus.script"
{ kp 37; kp 50; kp 56; } > "$STUB/xi2.script"
lg >/dev/null 2>&1 &
sleep 3
check "undim key: the shortcut works without xmodmap" has "$STUB/xrandr.calls" "$RESTORE_CALL"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
check "undim key: --status shows how the shortcut resolves" sh -c "printf 'UNDIM_KEY=Ctrl+Shift+b\n' > $XDG_CONFIG_HOME/lock-guard/config; $SH $ROOT/lock-guard --status 2>&1 | grep -q 'UNDIM_KEY=Ctrl+Shift+b -> OK 37,105 50,62 56'"
for bad in 'Ctrl+ +b' 'Ctrl++b' '+b' 'b+' 'Ctrl-b'; do
    printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=%s\n' "$bad" > "$XDG_CONFIG_HOME/lock-guard/config"
    check "undim key: UNDIM_KEY='$bad' is rejected" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'UNDIM_KEY must look like'"
done
for good in 'Ctrl+Shift+b' F12 '37+56' 'Super+Alt+x'; do
    printf 'LOCK_BRIGHTNESS=0.2\nUNDIM_KEY=%s\n' "$good" > "$XDG_CONFIG_HOME/lock-guard/config"
    check "undim key: UNDIM_KEY='$good' is accepted" sh -c "! $SH $ROOT/lock-guard --enable 2>&1 | grep -q 'UNDIM_KEY must look like'"
done
printf 'UNDIM_KEY=Ctrl+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "undim key: warns when LOCK_BRIGHTNESS is missing" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'does nothing without LOCK_BRIGHTNESS'"
done_with

# rescue command, config errors, unknown key warning, symlinked runtime dir
fresh
lg --enable >/dev/null 2>&1
check "--enable switches the mouse on" has "$STUB/xinput.calls" "^enable 13$"
printf 'DISABLE_INPUT=maybe\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "bad DISABLE_INPUT is rejected" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'must be yes or no'"
printf 'NOPE=1\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "unknown key is warned about" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q \"unknown key 'NOPE'\""
rm -rf "$RD"; ln -s /tmp "$RD"
check "symlinked runtime dir is refused" sh -c "$SH $ROOT/lock-guard --enable 2>&1 | grep -q 'symlink'"
done_with

# ============================================================================ randr-fix
fresh
check "randr-fix --version" test "$(rf -V)" = "randr-fix 1.0.0"
rf --detect > "$TMP/detected" 2>/dev/null
check "detect: primary output" has "$TMP/detected" "^PRIMARY_OUTPUT=DisplayPort-0$"
check "detect: primary rate" has "$TMP/detected" "^PRIMARY_RATE=144.00$"
check "detect: secondary output" has "$TMP/detected" "^SECONDARY_OUTPUT=HDMI-A-1-1$"
check "detect: secondary pos" has "$TMP/detected" "^SECONDARY_POS=1920x0$"
check "detect: secondary rate" has "$TMP/detected" "^SECONDARY_RATE=60.00$"
check "detect output is accepted as a config" sh -c "$SH $ROOT/randr-fix -C $TMP/detected --once >/dev/null 2>&1"
done_with

# layout already right: no xrandr; windows put back; icons restored once (cooldown)
fresh
mkdir -p "$RD"; chmod 700 "$RD"
printf '0x02000004 2000 100 900 700 0\n0x02000007 1920 0 1920 1080 1\nnot-an-id 1 2 3 4 0\n0xZZ 1 2 3 4 0\n' > "$RD/window-positions"
echo GOLD > "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml"
echo SCRAMBLED > "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml"
rf --once >/dev/null 2>&1
check "correct layout: xrandr not run" test ! -e "$STUB/xrandr.calls"
check "windows: unmaximise + move + maximise" has "$STUB/wmctrl.calls" "^-i -r 0x02000007 -b add,maximized_vert,maximized_horz$"
check "windows: restored by geometry" has "$STUB/wmctrl.calls" "^-i -r 0x02000004 -e 0,2000,100,900,700$"
check "windows: junk lines in the position file are skipped" test "$(grep -c -e '-e 0,' "$STUB/wmctrl.calls")" = 2
check "icons: golden copied over the scrambled file" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml" GOLD
check "icons: xfdesktop quit then started" same "$STUB/xfd.calls" "quit
start"
rm -f "$STUB/xfd.calls"; echo SCRAMBLED > "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml"
rf --once >/dev/null 2>&1
check "icons: second run inside the cooldown does nothing" test ! -e "$STUB/xfd.calls"
done_with

# primary missing (secondary alone) -> nothing at all happens, no icons onto the secondary
fresh
cat > "$STUB/xrandr.state" <<'EOF'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
DisplayPort-0 disconnected (normal left inverted right x axis y axis)
HDMI-A-1-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 531mm x 299mm
   1920x1080     60.00*+  50.00
EOF
echo GOLD > "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml"
rf --once >/dev/null 2>&1
check "primary missing: xrandr not run" test ! -e "$STUB/xrandr.calls"
check "primary missing: windows untouched" test ! -e "$STUB/wmctrl.calls"
check "primary missing: icons untouched" test ! -e "$STUB/xfd.calls"
check "primary missing: logged" has "$RD/randr-fix.log" "DisplayPort-0 is not connected yet"
done_with

# primary slow: connected but no mode yet, secondary already up -> xrandr is asked to set it,
# but icons are only restored once the primary really is primary at 0x0
fresh
cat > "$STUB/xrandr.state" <<'EOF'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
DisplayPort-0 connected (normal left inverted right x axis y axis) 531mm x 299mm
   1920x1080     60.00 + 144.00
HDMI-A-1-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 531mm x 299mm
   1920x1080     60.00*+
EOF
cp "$STUB/xrandr.state" "$STUB/xrandr.after"      # the primary never comes up
echo GOLD > "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml"
rf --once >/dev/null 2>&1
check "slow primary: xrandr command sent" has "$STUB/xrandr.calls" "--output DisplayPort-0 --primary --mode 1920x1080 --rate 144 --pos 0x0 --output HDMI-A-1-1 --mode 1920x1080 --rate 60 --pos 1920x0"
check "slow primary: icons NOT restored onto the wrong monitor" test ! -e "$STUB/xfd.calls"
check "slow primary: says why" has "$RD/randr-fix.log" "icons NOT restored"
done_with

# secondary late: waits, then goes ahead with the primary alone (command has no secondary)
fresh
cat > "$STUB/xrandr.state" <<'EOF'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
DisplayPort-0 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 531mm x 299mm
   1920x1080     60.00*+ 144.00
HDMI-A-1-1 disconnected (normal left inverted right x axis y axis)
EOF
rf --once >/dev/null 2>&1
check "secondary late: waited" has "$RD/randr-fix.log" "HDMI-A-1-1 is not connected yet - waiting"
check "secondary late: primary-only xrandr" has "$STUB/xrandr.calls" "^--output DisplayPort-0 --primary --mode 1920x1080 --rate 144 --pos 0x0$"
done_with

# monitors asleep: skip; wrong refresh rate: reassert; second run within 10 s: not repeated
fresh
printf 'Monitor is Off\n' > "$STUB/xset.out"
rf --once >/dev/null 2>&1
check "monitors off: nothing runs" test ! -e "$STUB/xrandr.calls"
fresh
sed 's/60.00 + 144.00\*/60.00* + 144.00/' "$STUB/xrandr.state" > "$STUB/x.tmp" && mv "$STUB/x.tmp" "$STUB/xrandr.state"
rf --once >/dev/null 2>&1
check "wrong rate (60 instead of 144): xrandr reasserts" test -s "$STUB/xrandr.calls"
rf --once >/dev/null 2>&1
check "xrandr is not repeated within 10 s" count "$STUB/xrandr.calls" "output" 1
done_with

# golden icon copy: -i, -y, backups, -c, refusal without a primary
fresh
rf -i -y >/dev/null 2>&1 </dev/null
check "-i with no golden yet: refuses when icons file missing" test ! -e "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml"
echo ONE > "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml"
rf -i -y >/dev/null 2>&1 </dev/null
check "-i creates the golden copy" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml" ONE
echo TWO > "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml"
check "-i without -y and without a terminal refuses" sh -c "$SH $ROOT/randr-fix -i </dev/null 2>&1 | grep -q 're-run with -y'"
check "-i refusal leaves golden alone" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml" ONE
sleep 1; rf -i -y >/dev/null 2>&1 </dev/null
check "-i -y replaces the golden copy" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml" TWO
check "-i keeps a timestamped backup" sh -c "ls $XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml.bak-* >/dev/null 2>&1"
check "-i backup holds the old layout" sh -c "cat $XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml.bak-* | grep -q ONE"
rf -c >/dev/null 2>&1
check "-c removes the backups" sh -c "! ls $XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml.bak-* >/dev/null 2>&1"
check "-c keeps the golden copy" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml" TWO
sed 's/connected primary/connected/' "$STUB/xrandr.state" > "$STUB/x.tmp" && mv "$STUB/x.tmp" "$STUB/xrandr.state"
echo THREE > "$XDG_CONFIG_HOME/xfce4/desktop/icons.screen0.yaml"
check "-i refuses when the primary is not up" sh -c "$SH $ROOT/randr-fix -i -y 2>&1 | grep -q 'not saving\|not up as primary'"
check "-i refusal leaves golden alone (2)" same "$XDG_CONFIG_HOME/xfce4/desktop/icons.golden.yaml" TWO
done_with

# watcher: a burst of 5 RandR events -> exactly one reassert; clean shutdown
fresh
printf 'RRScreenChangeNotify event, serial 1\nRRNotify event, x\nRRScreenChangeNotify event, serial 2\nRRScreenChangeNotify event, serial 3\nRRScreenChangeNotify event, serial 4\nRRScreenChangeNotify event, serial 5\n' > "$STUB/xev.script"
sed 's/60.00 + 144.00\*/60.00* + 144.00/' "$STUB/xrandr.state" > "$STUB/x.tmp" && mv "$STUB/x.tmp" "$STUB/xrandr.state"
rf >/dev/null 2>&1 &
sleep 4
check "watcher: five events, one run" count "$RD/randr-fix.log" "ran: xrandr" 1
check "watcher: second instance refused" sh -c "$SH $ROOT/randr-fix 2>&1 | grep -q 'already running'"
kill "$(cat "$RD/randr-fix.pid")"; sleep 1
check "watcher: logs stop" has "$RD/randr-fix.log" "stopped"
check "watcher: cleans pid, fifo and counter" test ! -e "$RD/randr-fix.pid" -a ! -e "$RD/randr-fix.fifo" -a ! -e "$RD/randr-fix.gen"
done_with

# config validation
fresh
printf 'PRIMARY_OUTPUT=\n' > "$XDG_CONFIG_HOME/randr-fix/config"
check "missing PRIMARY_OUTPUT is explained" sh -c "$SH $ROOT/randr-fix --once 2>&1 | grep -q 'PRIMARY_OUTPUT is not set'"
printf 'PRIMARY_OUTPUT=x\nDEBOUNCE=fast\n' > "$XDG_CONFIG_HOME/randr-fix/config"
check "bad DEBOUNCE is rejected" sh -c "$SH $ROOT/randr-fix --once 2>&1 | grep -q 'DEBOUNCE must be'"
done_with

# installer: an upgrade keeps every setting and appends only options the config lacks
# (the installer refuses root, so under root this runs it as user 'nobody' via setpriv)
if [ "$(id -u)" != 0 ] || command -v setpriv >/dev/null 2>&1; then
    IH=$(mktemp -d); mkdir -p "$IH/.config/lock-guard" "$IH/.config/randr-fix"
    printf '# my own notes\nLOCK_DEVICE_PATTERN=acme\nDISABLE_INPUT=no\n# SAVE_WINDOWS=all\n' > "$IH/.config/lock-guard/config"
    printf 'PRIMARY_OUTPUT=x\nPRIMARY_POS=0x0\nDEBOUNCE=7' > "$IH/.config/randr-fix/config"
    chmod -R a+rX "$ROOT"; chmod 755 "$IH"
    [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$IH"
    inst() {
        # shellcheck disable=SC2086   # $SH may be two words, e.g. "busybox sh"
        if [ "$(id -u)" = 0 ]; then
            setpriv --reuid=65534 --regid=65534 --clear-groups env -i HOME="$IH" PATH="$ORIGPATH" $SH "$ROOT/install.sh" --no-autostart --variants all
        else
            env -i HOME="$IH" PATH="$ORIGPATH" $SH "$ROOT/install.sh" --no-autostart --variants all
        fi
    }
    inst > "$IH/out1" 2>&1
    LC=$IH/.config/lock-guard/config; RC=$IH/.config/randr-fix/config
    check "installer: keeps the pattern you set" has "$LC" "^LOCK_DEVICE_PATTERN=acme$"
    check "installer: keeps DISABLE_INPUT=no" has "$LC" "^DISABLE_INPUT=no$"
    check "installer: keeps your comments" has "$LC" "^# my own notes$"
    check "installer: appends the new hook options (commented)" has "$LC" "^# LOCK_COMMAND=$"
    check "installer: does not re-add a key you commented out" count "$LC" "SAVE_WINDOWS=" 1
    check "installer: new options are not active" hasnt "$LC" "^LOCK_COMMAND="
    check "installer: randr-fix keeps DEBOUNCE=7 (no trailing newline case)" has "$RC" "^DEBOUNCE=7$"
    check "installer: randr-fix gets new options" has "$RC" "^# ICON_COOLDOWN=30$"
    cksum "$LC" "$RC" > "$IH/sum1"
    inst > "$IH/out2" 2>&1
    cksum "$LC" "$RC" > "$IH/sum2"
    check "installer: second run changes nothing" same "$IH/sum2" "$(cat "$IH/sum1")"
    check "installer: second run says so" has "$IH/out2" "already lists every option"
    check "installer: merged config loads without warnings" sh -c "env -i HOME=$IH PATH=$ORIGPATH $SH $IH/.local/bin/lock-guard --print-config -C $LC 2>&1 | grep -qv 'ignoring unknown key'"
    rm -rf "$IH"
else
    echo "skipped installer tests (need a non-root user or setpriv)"
fi



# ===================================================== installer: detection, variants, autostart
if [ "$(id -u)" != 0 ] || command -v setpriv >/dev/null 2>&1; then
    IH=$(mktemp -d); chmod 755 "$IH"
    mkscn() {   # mkscn NAME "xsession names" "wayland session names" "commands"
        _sd=$IH/scn/$1; mkdir -p "$_sd/share/xsessions" "$_sd/share/wayland-sessions" "$_sd/bin"
        for _n in $2; do : > "$_sd/share/xsessions/$_n.desktop"; done
        for _n in $3; do : > "$_sd/share/wayland-sessions/$_n.desktop"; done
        for _n in $4; do : > "$_sd/bin/$_n"; chmod +x "$_sd/bin/$_n"; done
    }
    XTOOLS="Xorg xrandr xset xinput xev xprop wmctrl dbus-monitor pgrep awk"
    mkscn debian "oxwm" "" "oxwm $XTOOLS"
    mkscn guix "" "mango" "mango busctl libinput pgrep awk"
    mkscn gentoo "xfce" "mango" "xfce4-session mango $XTOOLS busctl libinput"
    mkscn blank "" "" "awk"
    chmod -R a+rX "$IH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$IH"
    # inst2 SCENARIO INIT [installer args...]  (fresh HOME each time is the caller's job)
    inst2() {
        _sc=$IH/scn/$1; _in=$2; shift 2
        if [ "$(id -u)" = 0 ]; then
            # shellcheck disable=SC2086   # $SH may be two words, e.g. "busybox sh"
            setpriv --reuid=65534 --regid=65534 --clear-groups env -i HOME="$IH/h" PATH="$ORIGPATH" SG_DATA_DIRS="$_sc/share" SG_DETECT_PATH="$_sc/bin" SG_INIT="$_in" $SH "$ROOT/install.sh" "$@"
        else
            # shellcheck disable=SC2086   # $SH may be two words, e.g. "busybox sh"
            env -i HOME="$IH/h" PATH="$ORIGPATH" SG_DATA_DIRS="$_sc/share" SG_DETECT_PATH="$_sc/bin" SG_INIT="$_in" $SH "$ROOT/install.sh" "$@"
        fi
    }
    newhome() { rm -rf "$IH/h"; mkdir -p "$IH/h"; [ "$(id -u)" = 0 ] && chown 65534:65534 "$IH/h"; return 0; }
    LGI=$IH/h/.local/bin/lock-guard
    NBLOCKS=$(grep -c '^#@@ begin' "$ROOT/lock-guard")

    # --- detection of the machines you actually run
    newhome
    inst2 debian systemd --list > "$IH/o" 2>&1
    check "detect debian: init" has "$IH/o" "init system : systemd"
    check "detect debian: X11 with oxwm" has "$IH/o" "X11         : yes.*oxwm"
    check "detect debian: no Wayland" has "$IH/o" "Wayland     : no"
    check "detect debian: keeps x11 and dbus only" has "$IH/o" "Default parts to keep: x11 dbus$"
    inst2 guix shepherd --list > "$IH/o" 2>&1
    check "detect guix: init" has "$IH/o" "init system : shepherd"
    check "detect guix: Wayland with mango" has "$IH/o" "Wayland     : yes.*mango"
    check "detect guix: no X11" has "$IH/o" "X11         : no"
    check "detect guix: keeps wayland and process only" has "$IH/o" "Default parts to keep: wayland process$"
    inst2 gentoo openrc --list > "$IH/o" 2>&1
    check "detect gentoo: init" has "$IH/o" "init system : openrc"
    check "detect gentoo: keeps everything" has "$IH/o" "Default parts to keep: x11 wayland dbus process$"
    inst2 blank unknown --list > "$IH/o" 2>&1
    check "detect: when nothing can be told every part is kept" has "$IH/o" "Default parts to keep: x11 wayland dbus process$"
    check "detect: --list installs nothing" test ! -e "$IH/h/.local"

    # --- debian/oxwm: X11 only
    newhome
    inst2 debian systemd --yes --autostart none > "$IH/o" 2>&1
    check "x11 install: wayland and process blocks are gone" sh -c "! grep -q '^#@@ begin \(wayland\|process\)' $LGI"
    check "x11 install: x11 and dbus blocks stay" sh -c "grep -q '^#@@ begin x11' $LGI && grep -q '^#@@ begin dbus' $LGI"
    check "x11 install: the stamp names the kept parts" has "$LGI" "^# install.sh .*: parts kept: x11 dbus$"
    check "x11 install: result lists what was kept" has "$IH/o" "kept   : x11, dbus"
    check "x11 install: result lists what was pruned" has "$IH/o" "pruned : wayland, process"
    check "x11 install: and why each one is not needed" has "$IH/o" "- wayland: Wayland sessions"
    check "x11 install: valid shell" sh -c "$SH -n $LGI"
    check "x11 install: randr-fix installed" test -x "$IH/h/.local/bin/randr-fix"
    check "x11 install: sibling kept" has "$LGI" "^SIBLING=randr-fix$"
    check "x11 install: status lists the parts" sh -c "env -i HOME=$IH/h PATH=$ORIGPATH $SH $LGI --status | grep -q 'in this copy: x11 dbus'"
    check "x11 install: no autostart written" test ! -e "$IH/h/.config/autostart"

    # --- guix/mango: Wayland only
    newhome
    inst2 guix shepherd --yes --autostart none > "$IH/o" 2>&1
    check "wayland install: x11 and dbus blocks are gone" sh -c "! grep -q '^#@@ begin \(x11\|dbus\)' $LGI"
    check "wayland install: valid shell" sh -c "$SH -n $LGI"
    check "wayland install: randr-fix is not installed" test ! -e "$IH/h/.local/bin/randr-fix"
    check "wayland install: and says why" has "$IH/o" "randr-fix is X11 only: not installed"
    check "wayland install: no randr-fix config" test ! -e "$IH/h/.config/randr-fix"
    check "wayland install: sibling blanked" has "$LGI" "^SIBLING=$"
    check "wayland install: --restart-all works without it" sh -c "env -i HOME=$IH/h PATH=$ORIGPATH XDG_RUNTIME_DIR=$IH/h WAYLAND_DISPLAY=w $SH $LGI --restart-all >/dev/null 2>&1"
    # shellcheck disable=SC2086   # $SH may be two words, e.g. "busybox sh"
    env -i HOME="$IH/h" PATH="$ORIGPATH" XDG_RUNTIME_DIR="$IH/h" WAYLAND_DISPLAY=w $SH "$LGI" --stop >/dev/null 2>&1
    check "wayland install: shepherd users get the snippet" has "$IH/o" "shepherd-service"
    check "wayland install: wayland extras are checked" has "$IH/o" "libinput\|busctl\|Missing tools"
    check "wayland install: the config is written" test -s "$IH/h/.config/lock-guard/config"

    # --- gentoo: both, nothing removed
    newhome
    inst2 gentoo openrc --yes > "$IH/o" 2>&1
    check "mixed install: every block stays" sh -c "test \$(grep -c '^#@@ begin' $LGI) = $NBLOCKS"
    check "mixed install: identical to the source apart from the stamp" sh -c "test \$(diff $LGI $ROOT/lock-guard | grep -c '^[<>]') = 1"
    check "mixed install: result says nothing was pruned" has "$IH/o" "pruned : nothing"
    check "mixed install: both programs" test -x "$IH/h/.local/bin/randr-fix" -a -x "$LGI"
    check "mixed install: xdg autostart for both" sh -c "test -f $IH/h/.config/autostart/lock-guard.desktop -a -f $IH/h/.config/autostart/randr-fix.desktop"
    check "mixed install: window manager hint is printed" has "$IH/o" "do not read ~/.config/autostart"
    check "mixed install: the same install runs in either session" sh -c "env -i HOME=$IH/h PATH=$ORIGPATH WAYLAND_DISPLAY=w $SH $LGI --status | grep -q 'session: wayland'; env -i HOME=$IH/h PATH=$ORIGPATH DISPLAY=:0 $SH $LGI --status | grep -q 'session: x11'"

    # --- choosing
    newhome
    inst2 gentoo openrc --variants all --autostart none > /dev/null 2>&1
    check "variants: all" sh -c "test \$(grep -c '^#@@ begin' $LGI) = $NBLOCKS"
    newhome
    inst2 gentoo openrc --variants x11,dbus --autostart none > /dev/null 2>&1
    check "variants: an explicit list prunes the rest" sh -c "! grep -q '^#@@ begin wayland' $LGI && grep -q '^#@@ begin x11' $LGI"
    newhome
    inst2 gentoo openrc --variants x11 --autostart none > "$IH/o" 2>&1
    check "variants: no lock source is refused" has "$IH/o" "keep at least one of dbus / process"
    inst2 gentoo openrc --variants x11,dbus,bogus --autostart none > "$IH/o" 2>&1
    check "variants: unknown names are refused" has "$IH/o" "unknown part 'bogus'"
    check "variants: refusal installs nothing" test ! -e "$IH/h/.local/bin/lock-guard"
    newhome
    printf '\n' | inst2 debian systemd --answers-from-stdin --autostart none > "$IH/o" 2>&1
    check "prompt: Enter accepts the defaults" has "$LGI" "parts kept: x11 dbus$"
    newhome
    printf '+wayland\n' | inst2 debian systemd --answers-from-stdin --autostart none > "$IH/o" 2>&1
    check "prompt: +name adds a part to the defaults" has "$LGI" "parts kept: x11 wayland dbus$"
    newhome
    printf -- '-process\n' | inst2 gentoo openrc --answers-from-stdin --autostart none > "$IH/o" 2>&1
    check "prompt: -name removes one" has "$LGI" "parts kept: x11 wayland dbus$"
    newhome
    printf 'wayland,process\n' | inst2 debian systemd --answers-from-stdin --autostart none > "$IH/o" 2>&1
    check "prompt: a plain list replaces the defaults" has "$LGI" "parts kept: wayland process$"
    newhome
    printf 'nonsense\nall\n' | inst2 debian systemd --answers-from-stdin --autostart none > "$IH/o" 2>&1
    check "prompt: a bad answer asks again" has "$IH/o" "unknown part 'nonsense'"
    check "prompt: and the next answer is used" has "$LGI" "parts kept: x11 wayland dbus process$"
    newhome
    printf '\nsystemd\n' | inst2 debian systemd --answers-from-stdin > "$IH/o" 2>&1
    check "prompt: autostart method asked after the parts" test -f "$IH/h/.config/systemd/user/lock-guard.service"

    # --- autostart methods
    newhome
    inst2 debian systemd --yes --autostart systemd > "$IH/o" 2>&1
    check "systemd: units written" test -f "$IH/h/.config/systemd/user/lock-guard.service" -a -f "$IH/h/.config/systemd/user/randr-fix.service"
    check "systemd: unit runs the installed script" has "$IH/h/.config/systemd/user/lock-guard.service" "^ExecStart=$IH/h/.local/bin/lock-guard$"
    check "systemd: no xdg entries" test ! -e "$IH/h/.config/autostart"
    check "systemd: tells how to enable" has "$IH/o" "systemctl --user daemon-reload"
    check "systemd: warns about the environment" has "$IH/o" "import-environment"
    newhome
    inst2 gentoo openrc --yes > /dev/null 2>&1
    inst2 gentoo openrc --uninstall > "$IH/o" 2>&1
    check "uninstall: scripts and autostart entries removed" sh -c "test ! -e $LGI -a ! -e $IH/h/.config/autostart/lock-guard.desktop"
    check "uninstall: configs kept" test -f "$IH/h/.config/lock-guard/config"
    rm -rf "$IH"
fi



# ===================================================================== versions and updating
check "versions: lock-guard, randr-fix, install.sh and the VERSION file agree" sh -c "
  v=\$(cat $ROOT/VERSION); test \"\$v\" = \"\$(sed -n 's/^VERSION=//p' $ROOT/lock-guard)\" &&
  test \"\$v\" = \"\$(sed -n 's/^VERSION=//p' $ROOT/randr-fix)\" && test \"\$v\" = \"\$(sed -n 's/^VERSION=//p' $ROOT/install.sh | sed -n 1p)\""
check "versions: install.sh --version" sh -c "$SH $ROOT/install.sh --version | grep -q '^install.sh [0-9]*\.[0-9]*\.[0-9]*$'"

if [ "$(id -u)" != 0 ] || command -v setpriv >/dev/null 2>&1; then
    UH=$(mktemp -d); chmod 755 "$UH"
    mkdir -p "$UH/stub" "$UH/serve" "$UH/none"
    # a stand-in curl: serves $UH/serve/VERSION and $UH/serve/release.tar.gz, logs the addresses
    cat > "$UH/stub/curl" <<'EOF'
#!/bin/sh
out=; url=
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift ;; https://*|http://*) url=$1 ;; esac; shift; done
echo "$url" >> "$SERVE/curl.calls"
[ -f "$SERVE/offline" ] && exit 7
case $url in
  */VERSION) cp "$SERVE/VERSION" "$out" ;;
  *.tar.gz) cp "$SERVE/release.tar.gz" "$out" ;;
  *) exit 22 ;;
esac
EOF
    chmod +x "$UH/stub/curl"
    mkrelease() {   # mkrelease VERSION [dir-name]: a copy of this tree that calls itself VERSION
        _rd=$UH/rel/${2:-lock-guard-$1}; rm -rf "$UH/rel"; mkdir -p "$UH/rel"
        cp -r "$ROOT" "$_rd"; rm -rf "$_rd/.git"
        for _f in lock-guard randr-fix install.sh; do sed "s/^VERSION=[0-9.]*\$/VERSION=$1/" "$_rd/$_f" > "$_rd/$_f.t" && mv "$_rd/$_f.t" "$_rd/$_f"; done
        echo "$1" > "$_rd/VERSION"; chmod +x "$_rd/install.sh" "$_rd/lock-guard" "$_rd/randr-fix"
        tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" . 2>/dev/null
        echo "$1" > "$UH/serve/VERSION"
    }
    chmod -R a+rX "$ROOT"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    uinst() {   # uinst [args...]: run this tree's installer as a normal user with the stand-in curl
        if [ "$(id -u)" = 0 ]; then
            # shellcheck disable=SC2086   # $SH may be two words
            setpriv --reuid=65534 --regid=65534 --clear-groups env -i HOME="$UH/h" PATH="$UH/stub:$ORIGPATH" SERVE="$UH/serve" SG_DETECT_PATH="${UD:-$UH/stub:$ORIGPATH}" SG_INIT=openrc XDG_RUNTIME_DIR="${UR:-}" ${UX:-X=1} $SH "$ROOT/install.sh" "$@"
        else
            # shellcheck disable=SC2086
            env -i HOME="$UH/h" PATH="$UH/stub:$ORIGPATH" SERVE="$UH/serve" SG_DETECT_PATH="${UD:-$UH/stub:$ORIGPATH}" SG_INIT=openrc XDG_RUNTIME_DIR="${UR:-}" ${UX:-X=1} $SH "$ROOT/install.sh" "$@"
        fi
    }
    ULG=$UH/h/.local/bin/lock-guard
    newuh() { rm -rf "$UH/h" "$UH/serve/curl.calls" "$UH/serve/offline"; mkdir -p "$UH/h"; [ "$(id -u)" = 0 ] && chown 65534:65534 "$UH/h"; return 0; }
    cur=$(cat "$ROOT/VERSION")

    newuh
    uinst --yes --variants x11,dbus --autostart none > "$UH/o" 2>&1
    check "update: the install is recorded" sh -c "grep -q '^VARIANTS=x11 dbus$' $UH/h/.config/screen-guard/install.conf && grep -q '^AUTOSTART=none$' $UH/h/.config/screen-guard/install.conf && grep -q '^VERSION=$cur$' $UH/h/.config/screen-guard/install.conf"

    # up to date
    echo "$cur" > "$UH/serve/VERSION"
    uinst --check-update > "$UH/o" 2>&1; rc=$?
    check "check-update: same version means up to date (exit 0)" test "$rc" = 0 -a -n "$(grep 'up to date' "$UH/o")"
    check "check-update: reads the VERSION file over https from GitHub" has "$UH/serve/curl.calls" "^https://raw.githubusercontent.com/toillover1337/lock-guard/main/VERSION$"
    uinst --update --yes > "$UH/o" 2>&1; rc=$?
    check "update: nothing to do when current" test "$rc" = 0 -a -n "$(grep 'up to date' "$UH/o")"
    check "update: and nothing was downloaded" count "$UH/serve/curl.calls" "tar.gz" 0

    # an older version number upstream is not an update
    echo "0.9.0" > "$UH/serve/VERSION"
    uinst --update --yes > "$UH/o" 2>&1
    check "update: an older upstream version is ignored" has "$UH/o" "up to date"

    # a real update
    mkrelease 1.0.1
    chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    uinst --check-update > "$UH/o" 2>&1; rc=$?
    check "check-update: a newer release exits 10" test "$rc" = 10
    check "check-update: says what to run" has "$UH/o" "An update is available: $cur -> 1.0.1"
    check "check-update: points at the release notes" has "$UH/o" "https://github.com/toillover1337/lock-guard/releases/tag/v1.0.1"
    check "check-update: changes nothing" sh -c "$SH $ULG --version | grep -q 'lock-guard $cur'"
    : | uinst --update > "$UH/o" 2>&1; rc=$?
    check "update: without --yes and without a terminal it refuses" test "$rc" != 0 -a -n "$(grep 'add --yes' "$UH/o")"
    printf 'n\n' | uinst --update --answers-from-stdin > "$UH/o" 2>&1
    check "update: answering n leaves the old version" sh -c "$SH $ULG --version | grep -q 'lock-guard $cur'"
    printf 'y\nn\n' | uinst --update --answers-from-stdin > "$UH/o" 2>&1
    check "update: answering y installs the new version" sh -c "$SH $ULG --version | grep -q 'lock-guard 1.0.1'"
    check "update: randr-fix was updated too" sh -c "$SH $UH/h/.local/bin/randr-fix --version | grep -q 'randr-fix 1.0.1'"
    check "update: downloaded the tag archive over https" has "$UH/serve/curl.calls" "^https://github.com/toillover1337/lock-guard/archive/refs/tags/v1.0.1.tar.gz$"
    check "update: the earlier parts choice was repeated (still no wayland)" sh -c "! grep -q '^#@@ begin wayland' $ULG"
    check "update: the record shows the new version" has "$UH/h/.config/screen-guard/install.conf" "^VERSION=1.0.1$"
    check "update: the old scripts are kept for rollback" sh -c "grep -q '^VERSION=$cur\$' $UH/h/.config/screen-guard/previous/lock-guard"
    check "update: the restart question was asked and declined" has "$UH/o" "Restart later with"
    check "update: configs untouched (no config created twice)" sh -c "test -s $UH/h/.config/lock-guard/config"

    # an update asked to restart the running copies does so
    uinst --yes --autostart none > /dev/null 2>&1
    printf 'SESSION=wayland\n' > "$UH/h/.config/lock-guard/config"; [ "$(id -u)" = 0 ] && chown 65534:65534 "$UH/h/.config/lock-guard/config"
    # shellcheck disable=SC2086
    env -i HOME="$UH/h" PATH="$ORIGPATH" XDG_RUNTIME_DIR="$UH/h" $SH "$ULG" --start > /dev/null 2>&1
    mkrelease 1.0.2; chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    UR="$UH/h" uinst --update --yes > "$UH/o" 2>&1
    check "update --yes: restarts the running program on its own" has "$UH/o" "lock-guard started"
    # shellcheck disable=SC2086
    env -i HOME="$UH/h" PATH="$ORIGPATH" XDG_RUNTIME_DIR="$UH/h" $SH "$ULG" --stop > /dev/null 2>&1

    # things that must be refused
    newuh; uinst --yes --autostart none > /dev/null 2>&1
    mkrelease 1.0.3
    sed 's/^VERSION=1.0.3$/VERSION=1.0.0/' "$UH/rel/lock-guard-1.0.3/lock-guard" > "$UH/t" && cp "$UH/t" "$UH/rel/lock-guard-1.0.3/lock-guard"
    tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" .; chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    uinst --update --yes > "$UH/o" 2>&1; rc=$?
    check "refuse: a script whose own version differs from the announced one" test "$rc" != 0 -a -n "$(grep 'does not carry version 1.0.3' "$UH/o")"
    check "refuse: and nothing was installed" sh -c "$SH $ULG --version | grep -q 'lock-guard $cur'"

    mkrelease 1.0.3
    printf 'if then\n' > "$UH/rel/lock-guard-1.0.3/randr-fix"
    sed -i "s/^VERSION=.*//" "$UH/rel/lock-guard-1.0.3/randr-fix"
    tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" .; chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    uinst --update --yes > "$UH/o" 2>&1; rc=$?
    check "refuse: a script that is not valid shell" test "$rc" != 0 -a -n "$(grep 'not valid shell' "$UH/o")"

    mkrelease 1.0.3
    echo 9.9.9 > "$UH/rel/lock-guard-1.0.3/VERSION"
    tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" .; chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
    uinst --update --yes > "$UH/o" 2>&1; rc=$?
    check "refuse: a VERSION file that disagrees" test "$rc" != 0 -a -n "$(grep "says it is version '9.9.9'" "$UH/o")"

    mkrelease 1.0.3
    mkdir -p "$UH/evil"; echo x > "$UH/evil/x"
    tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" . -C "$UH/evil" --transform 's,^x$,../escape,' x 2>/dev/null ||
        tar czf "$UH/serve/release.tar.gz" -C "$UH/rel" .
    # (decided by the tar that the shell under test would run: busybox's own tar strips "../" itself)
    # shellcheck disable=SC2086
    if env -i PATH="$ORIGPATH" $SH -c "tar tzf '$UH/serve/release.tar.gz'" 2>/dev/null | grep -q '\.\./'; then
        chmod -R a+rX "$UH"; [ "$(id -u)" = 0 ] && chown -R 65534:65534 "$UH"
        uinst --update --yes > "$UH/o" 2>&1; rc=$?
        check "refuse: an archive with .. in a path" test "$rc" != 0 -a -n "$(grep 'unsafe paths' "$UH/o")"
    fi
    newuh; uinst --yes --autostart none > /dev/null 2>&1; echo "1.0.3" > "$UH/serve/VERSION"

    printf 'this is not a tarball\n' > "$UH/serve/release.tar.gz"; chmod a+r "$UH/serve/release.tar.gz"
    uinst --update --yes > "$UH/o" 2>&1; rc=$?
    check "refuse: a download that is not an archive" test "$rc" != 0 -a -n "$(grep 'not a valid archive' "$UH/o")"

    echo "1.0.3" > "$UH/serve/VERSION"; : > "$UH/serve/offline"; chmod a+r "$UH/serve/offline"
    uinst --check-update > "$UH/o" 2>&1; rc=$?
    check "offline: check-update fails clearly (exit 1)" test "$rc" = 1 -a -n "$(grep 'could not reach' "$UH/o")"
    rm -f "$UH/serve/offline"

    printf '<html>rate limited</html>\n' > "$UH/serve/VERSION"
    uinst --check-update > "$UH/o" 2>&1; rc=$?
    check "garbage: a VERSION file that is not a version is rejected" test "$rc" = 1 -a -n "$(grep 'could not be read' "$UH/o")"

    echo "1.0.3" > "$UH/serve/VERSION"
    # (skipped where the shell has wget built in, e.g. busybox sh: it would find it whatever PATH says)
    case $SH in *busybox*) NODL_SKIP=1 ;; *) NODL_SKIP=0 ;; esac
    if [ "$NODL_SKIP" = 0 ]; then
        UD="$UH/none" uinst --check-update > "$UH/o" 2>&1; rc=$?
        check "no downloader: says what is needed" test "$rc" = 1 -a -n "$(grep 'need curl, wget or fetch' "$UH/o")"
    fi
    UX=SG_VERSION_URL=http://example.invalid/VERSION uinst --check-update > "$UH/o" 2>&1; rc=$?
    check "http is refused" test "$rc" = 1 -a -n "$(grep 'non-HTTPS' "$UH/o")"
    rm -rf "$UH"
fi


# ================================================================== Wayland session (stubbed)
# libinput prints one line per key event: device, KEYBOARD_KEY, time, KEY_NAME (evdev code) state
lik() { printf 'event3   KEYBOARD_KEY            +1.000s\t%s (%s) %s\n' "$1" "$2" "$3"; }
li_gone() { ! "$REALPGREP" -f "^/bin/sh $TMP/bin/libinput debug-events" >/dev/null 2>&1; }

fresh
cat > "$XDG_CONFIG_HOME/lock-guard/config" <<EOF
SESSION=wayland
LOCK_BRIGHTNESS=0.2
INPUT_OFF_COMMAND=echo off >> $STUB/in.calls
INPUT_ON_COMMAND=echo on >> $STUB/in.calls
LOCK_COMMAND=echo lockhook >> $STUB/hook.calls
EOF
lg >/dev/null 2>&1 &
sleep 1.5
check "wayland: lock detection is the locker process, not D-Bus" has "$RD/lock-guard.log" "watching for a screen locker"
check "wayland: dbus-monitor is not started" test ! -e "$STUB/dbus.args"
check "wayland: not locked while no locker runs" hasnt "$RD/lock-guard.log" "screen locked"
touch "$STUB/locker.running"; sleep 2
check "wayland: a running locker means locked" has "$RD/lock-guard.log" "screen locked"
check "wayland: dimmed through wl-gammarelay-rs" same "$STUB/busctl.calls" 0.2
check "wayland: dim log names the target" has "$RD/lock-guard.log" "dimmed to 0.2: all"
check "wayland: INPUT_OFF_COMMAND ran" has "$STUB/in.calls" "^off$"
check "wayland: no xinput / xrandr used" test ! -e "$STUB/xinput.calls" -a ! -e "$STUB/xrandr.calls"
check "wayland: lock hook ran" has "$STUB/hook.calls" "lockhook"
check "wayland: the X11 keeper is not started" test ! -e "$RD/dim-keeper"
rm -f "$STUB/locker.running"; sleep 2
check "wayland: the locker ending means unlocked" has "$RD/lock-guard.log" "screen unlocked"
check "wayland: brightness put back to what it was" same "$STUB/gamma" 1
check "wayland: INPUT_ON_COMMAND ran" has "$STUB/in.calls" "^on$"
check "wayland: --status names the session" sh -c "$SH $ROOT/lock-guard --status | grep -q 'session: wayland  lock detection: process'"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# automatic session choice
fresh
check "session: WAYLAND_DISPLAY selects wayland" sh -c "env -u XDG_SESSION_TYPE WAYLAND_DISPLAY=wl-1 $SH $ROOT/lock-guard --status | grep -q 'session: wayland'"
check "session: XDG_SESSION_TYPE=x11 wins over a leftover WAYLAND_DISPLAY" sh -c "XDG_SESSION_TYPE=x11 WAYLAND_DISPLAY=wl-1 $SH $ROOT/lock-guard --status | grep -q 'session: x11  lock detection: dbus'"
check "session: nothing set means x11" sh -c "env -u XDG_SESSION_TYPE -u WAYLAND_DISPLAY $SH $ROOT/lock-guard --status | grep -q 'session: x11'"
printf 'SESSION=sway\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "session: a bad SESSION is refused" sh -c "$SH $ROOT/lock-guard --status 2>&1 | grep -q 'SESSION must be'"
printf 'LOCK_DETECT=magic1\n' > "$XDG_CONFIG_HOME/lock-guard/config"
check "session: a bad LOCK_DETECT is refused" sh -c "$SH $ROOT/lock-guard --status 2>&1 | grep -q 'LOCK_DETECT must be'"
done_with

# custom dim commands, and --undim
fresh
cat > "$XDG_CONFIG_HOME/lock-guard/config" <<EOF
SESSION=wayland
LOCK_BRIGHTNESS=0.3
DIM_COMMAND=echo dim \$LEVEL >> $STUB/cmd.calls
UNDIM_COMMAND=echo undim >> $STUB/cmd.calls
EOF
lg >/dev/null 2>&1 &
sleep 1.5; touch "$STUB/locker.running"; sleep 2
check "dim command: gets LEVEL" has "$STUB/cmd.calls" "^dim 0.3$"
check "dim command: wl-gammarelay-rs is not used" test ! -e "$STUB/busctl.calls"
lg --undim
check "--undim: runs UNDIM_COMMAND" has "$STUB/cmd.calls" "^undim$"
check "--undim: logged" has "$RD/lock-guard.log" "undim requested"
check "--undim: dim state removed" test ! -e "$RD/dim-state"
lg --undim
check "--undim: harmless when not dimmed" count "$STUB/cmd.calls" "^undim$" 1
rm -f "$STUB/locker.running"; sleep 2
check "dim command: unlock does not undim twice" count "$STUB/cmd.calls" "^undim$" 1
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# early undim shortcut with libinput (evdev codes: Ctrl 29, Shift 42, b 48)
fresh
printf 'SESSION=wayland\nLOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
{ lik KEY_B 48 pressed; lik KEY_B 48 released; lik KEY_LEFTCTRL 29 pressed; lik KEY_B 48 pressed; lik KEY_B 48 released
  lik KEY_LEFTSHIFT 42 pressed; lik KEY_B 48 pressed; } > "$STUB/li.script"
lg >/dev/null 2>&1 &
sleep 1.5; touch "$STUB/locker.running"; sleep 3
check "wayland key: libinput asked for key codes" has "$STUB/li.calls" "debug-events --show-keycodes"
check "wayland key: ready" has "$RD/lock-guard.log" "undim key ready: Ctrl+Shift+b"
check "wayland key: full shortcut restores brightness" has "$RD/lock-guard.log" "undim key pressed"
check "wayland key: only after the whole shortcut" count "$STUB/busctl.calls" "^1$" 1
check "wayland key: listener stopped" li_gone
check "wayland key: no key data in the log" hasnt "$RD/lock-guard.log" "KEY_\|KEYBOARD"
rm -f "$STUB/locker.running"; sleep 2
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

fresh
printf 'SESSION=wayland\nLOCK_BRIGHTNESS=0.2\nUNDIM_KEY=Ctrl+Shift+b\n' > "$XDG_CONFIG_HOME/lock-guard/config"
touch "$STUB/li.die"
lg >/dev/null 2>&1 &
sleep 1.5; touch "$STUB/locker.running"; sleep 3
check "wayland key: a listener that cannot read the keyboards is explained" has "$RD/lock-guard.log" "ended by itself (libinput needs read access"
check "wayland key: dimming still works" has "$RD/lock-guard.log" "dimmed to 0.2"
rm -f "$STUB/locker.running"; sleep 2
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# both sources at once, and a locker that was already running when lock-guard started
fresh
printf 'SESSION=wayland\nLOCK_DETECT=dbus process\n' > "$XDG_CONFIG_HOME/lock-guard/config"
touch "$STUB/locker.running"
printf 'signal time=1 member=ActiveChanged\n   boolean false\n' > "$STUB/dbus.script"
lg >/dev/null 2>&1 &
sleep 2.5
check "both sources: dbus-monitor started too" test -e "$STUB/dbus.args"
check "both sources: an already running locker counts as locked" has "$RD/lock-guard.log" "screen locked"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
done_with

# randr-fix does nothing in a Wayland session
fresh
printf 'SESSION=wayland\n' >> "$XDG_CONFIG_HOME/randr-fix/config"
check "randr-fix: --once on wayland explains and succeeds" sh -c "$SH $ROOT/randr-fix --once | grep -q 'Wayland session - nothing to do'"
check "randr-fix: --start on wayland starts nothing" sh -c "$SH $ROOT/randr-fix --start | grep -q 'nothing to do'; test ! -e $RD/randr-fix.pid"
check "randr-fix: xrandr is never called" test ! -e "$STUB/xrandr.calls"
check "randr-fix: WAYLAND_DISPLAY alone is enough" sh -c "sed -i '/^SESSION=/d' $XDG_CONFIG_HOME/randr-fix/config; env -u XDG_SESSION_TYPE WAYLAND_DISPLAY=wl-1 $SH $ROOT/randr-fix --once | grep -q 'nothing to do'"
check "randr-fix: x11 forced overrides it" sh -c "printf 'SESSION=x11\n' >> $XDG_CONFIG_HOME/randr-fix/config; WAYLAND_DISPLAY=wl-1 $SH $ROOT/randr-fix --once 2>&1 | grep -q 'nothing to do' && exit 1; exit 0"
done_with

# a copy with the wayland blocks removed still runs on X11, and says so on Wayland
fresh
mkdir "$TMP/pruned"
awk '/^#@@ begin wayland$/ { skip = 1; next } /^#@@ end wayland$/ { skip = 0; next } !skip' "$ROOT/lock-guard" > "$TMP/pruned/lock-guard"
# shellcheck disable=SC2086   # $SH may be two words, e.g. "busybox sh"
check "pruned copy: syntax is valid" $SH -n "$TMP/pruned/lock-guard"
check "pruned copy: status lists what is left" sh -c "$SH $TMP/pruned/lock-guard --status | grep -q 'in this copy: x11 dbus process'"
printf 'signal time=1 member=ActiveChanged\n   boolean true\n' > "$STUB/dbus.script"
$SH "$TMP/pruned/lock-guard" >/dev/null 2>&1 &
sleep 2
check "pruned copy: X11 still works (device disabled)" has "$STUB/xinput.calls" "^disable 13$"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
printf 'SESSION=wayland\nLOCK_BRIGHTNESS=0.2\n' > "$XDG_CONFIG_HOME/lock-guard/config"
$SH "$TMP/pruned/lock-guard" >/dev/null 2>&1 &
sleep 1.5; touch "$STUB/locker.running"; sleep 2
check "pruned copy: the missing backend is logged, nothing crashes" has "$RD/lock-guard.log" "this copy has no wayland support"
check "pruned copy: still running" kill -0 "$(cat "$RD/lock-guard.pid")"
kill "$(cat "$RD/lock-guard.pid")"; sleep 1
rm -f "$STUB/locker.running"
awk '/^#@@ begin (dbus|process)$/ { skip = 1; next } /^#@@ end (dbus|process)$/ { skip = 0; next } !skip' "$ROOT/lock-guard" > "$TMP/pruned/lg2"
check "pruned copy: a lock source that was removed is reported" sh -c "printf 'SESSION=x11\n' > $XDG_CONFIG_HOME/lock-guard/config; $SH $TMP/pruned/lg2 2>&1 | grep -q \"lock detection 'dbus' is not in this copy\""
done_with

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
