#!/bin/sh
# screen-guard installer (POSIX sh).  Installs lock-guard and randr-fix for the current user.
#   ./install.sh                  detect this machine, show what it found, ask what to install
#   ./install.sh --list           only show what was detected
#   ./install.sh --yes            accept the detected defaults without asking
#   ./install.sh --variants LIST  keep exactly these parts: x11 wayland dbus process ddc (or "all")
#   ./install.sh --autostart M    start at login via: xdg (default), systemd, shepherd, none
#   ./install.sh --prefix DIR     install to DIR/bin instead of ~/.local/bin
#   ./install.sh --no-autostart   same as --autostart none
#   ./install.sh --check-update   ask GitHub whether a newer release exists
#   ./install.sh --update         download the newest release and install it with the same choices
#   ./install.sh --version        print the version
#   ./install.sh --uninstall      remove the scripts and autostart entries (configs are kept)
# Run it as your normal user, not as root.
#
# The programs contain code for several environments.  The installer keeps the parts for what
# you have (default) and removes the rest from the installed copy; the program still picks the
# right part each time it starts, so one install serves an X11 and a Wayland session alike.

VERSION=1.1.0
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-${HOME:-}/.local}
PREFIX_SET=0
AUTOSTART=xdg
AUTOSTART_SET=0
ACTION=install
SCRIPTS="lock-guard randr-fix"
CONFHOME=${XDG_CONFIG_HOME:-${HOME:-}/.config}
ALL_VARIANTS="x11 wayland dbus process ddc"
VARIANTS=auto
YES=0
ASK_STDIN=0
INIT_OVERRIDE=${SG_INIT:-}

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case $1 in
        --prefix) [ $# -ge 2 ] || die "--prefix needs a directory"; PREFIX=$2; PREFIX_SET=1; shift ;;
        --variants) [ $# -ge 2 ] || die "--variants needs a list"; VARIANTS=$2; shift ;;
        --autostart) [ $# -ge 2 ] || die "--autostart needs a method"; AUTOSTART=$2; AUTOSTART_SET=1; shift ;;
        --no-autostart) AUTOSTART=none; AUTOSTART_SET=1 ;;
        --init) [ $# -ge 2 ] || die "--init needs a name"; INIT_OVERRIDE=$2; shift ;;
        --yes|-y) YES=1 ;;
        --list) ACTION=list ;;
        --answers-from-stdin) ASK_STDIN=1 ;;
        --uninstall) ACTION=uninstall ;;
        --check-update) ACTION=checkupdate ;;
        --update) ACTION=update ;;
        -V|--version) echo "install.sh $VERSION"; exit 0 ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done
case $AUTOSTART in xdg|systemd|shepherd|none) ;; *) die "--autostart must be xdg, systemd, shepherd or none" ;; esac

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"
[ -n "${HOME:-}" ] || die "HOME is not set"
BIN=$PREFIX/bin
# .desktop Exec= lines cannot hold spaces or shell characters safely
case $BIN in *[!A-Za-z0-9/._+-]*) die "install path '$BIN' has unusual characters; choose another --prefix" ;; esac
AUTODIR=$CONFHOME/autostart
UNITDIR=$CONFHOME/systemd/user

# ------------------------------------------------------------------------------ updating
# Where new versions come from.  A plain VERSION file on the main branch says what the newest
# release is; the release itself is the GitHub archive of the tag vX.Y.Z.  (SG_* variables
# replace these for testing; the real thing only ever talks HTTPS to GitHub.)
REPO=${SG_REPO:-toillover1337/lock-guard}
VERSION_URL=${SG_VERSION_URL:-https://raw.githubusercontent.com/$REPO/main/VERSION}
ARCHIVE_URL=${SG_ARCHIVE_URL:-https://github.com/$REPO/archive/refs/tags/v%s.tar.gz}
RELEASES_URL=https://github.com/$REPO/releases
RECORD=$CONFHOME/screen-guard/install.conf

# archive_url VERSION: the address of that release (the version was checked to be digits and dots)
archive_url() { printf '%s\n' "$ARCHIVE_URL" | sed "s/%s/$1/"; }

is_version() { case $1 in ''|*[!0-9.]*|.*|*.|*..*) return 1 ;; esac; case $1 in *.*.*) return 0 ;; esac; return 1; }

# vercmp A B: prints -1, 0 or 1 (numeric, dot by dot)
vercmp() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, A, "."); nb = split(b, B, "."); n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            x = A[i] + 0; y = B[i] + 0
            if (x < y) { print -1; exit }
            if (x > y) { print 1; exit }
        }
        print 0 }'
}

# download URL FILE: HTTPS only, with curl, wget or the BSD fetch tool
download() {
    case $1 in https://*) ;; *) echo "refusing a non-HTTPS address: $1" >&2; return 1 ;; esac
    if has_cmd curl; then curl -fsSL --proto '=https' --max-time 60 -o "$2" "$1"
    elif has_cmd wget; then wget -q -T 60 -O "$2" "$1"
    elif has_cmd fetch; then fetch -q -T 60 -o "$2" "$1"
    else echo "need curl, wget or fetch to look for updates" >&2; return 1; fi
}

record_get() { [ -r "$RECORD" ] && sed -n "s/^$1=//p" "$RECORD" | sed -n 1p; }

record_write() {
    mkdir -p "$CONFHOME/screen-guard" 2>/dev/null || return 0
    {
        echo "# written by install.sh; used by --update to repeat your choices"
        echo "VERSION=$VERSION"
        echo "VARIANTS=$KEEP"
        echo "AUTOSTART=$AUTOSTART"
        echo "PREFIX=$PREFIX"
    } > "$RECORD.new" 2>/dev/null && mv -f "$RECORD.new" "$RECORD"
    return 0
}

installed_version() {
    [ -x "$BIN/lock-guard" ] || return 1
    _iv=$("$BIN/lock-guard" --version 2>/dev/null | sed -n 's/^lock-guard //p')
    is_version "$_iv" || return 1
    echo "$_iv"
}

latest_version() {
    _lt=$(mktemp "${TMPDIR:-/tmp}/sg-version.XXXXXX") || return 1
    if ! download "$VERSION_URL" "$_lt"; then rm -f "$_lt"; echo "could not reach $VERSION_URL" >&2; return 1; fi
    _lv=$(sed -n 1p "$_lt" | tr -d ' \r'); rm -f "$_lt"
    if ! is_version "$_lv"; then echo "the newest version number could not be read (got '$_lv')" >&2; return 1; fi
    echo "$_lv"
}

# do_check_update: exit 0 = up to date, 10 = an update exists, 1 = could not tell
do_check_update() {
    _cur=$(installed_version) || _cur=
    echo "installer in this folder : $VERSION"
    echo "installed ($BIN)         : ${_cur:-not installed}"
    _new=$(latest_version) || return 1
    echo "newest release           : $_new"
    _base=${_cur:-$VERSION}
    if [ "$(vercmp "$_new" "$_base")" = 1 ]; then
        echo "An update is available: $_base -> $_new   (run: ./install.sh --update)"
        echo "Release notes: $RELEASES_URL/tag/v$_new"
        return 10
    fi
    echo "You are up to date."
    return 0
}

do_update() {
    _cur=$(installed_version) || _cur=
    _new=$(latest_version) || return 1
    _base=${_cur:-$VERSION}
    echo "installed: ${_cur:-not installed}   this folder: $VERSION   newest release: $_new"
    if [ "$(vercmp "$_new" "$_base")" != 1 ]; then echo "You are up to date."; return 0; fi
    echo "Update $_base -> $_new"
    echo "  from : $(archive_url "$_new")"
    echo "  notes: $RELEASES_URL/tag/v$_new"
    if [ "$YES" = 0 ]; then
        if interactive; then
            ask "Download and install it? [y/N] "
            case $ANSWER in y|Y|yes|YES) ;; *) echo "Not updated."; return 0 ;; esac
        else
            echo "Not interactive: add --yes to update without asking."; return 1
        fi
    fi
    _wd=$(mktemp -d "${TMPDIR:-/tmp}/sg-update.XXXXXX") || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '$_wd'" EXIT INT TERM HUP
    download "$(archive_url "$_new")" "$_wd/release.tar.gz" || { echo "download failed" >&2; return 1; }
    # nothing outside the working folder: no absolute paths, no ".." parts
    if ! tar tzf "$_wd/release.tar.gz" > "$_wd/list" 2>/dev/null; then echo "the download is not a valid archive" >&2; return 1; fi
    if grep -q '^/\|\(^\|/\)\.\.\(/\|$\)' "$_wd/list"; then echo "the archive has unsafe paths; not installing" >&2; return 1; fi
    mkdir "$_wd/x"
    tar xzf "$_wd/release.tar.gz" -C "$_wd/x" 2>/dev/null || { echo "could not unpack the download" >&2; return 1; }
    _top=$(find "$_wd/x" -mindepth 1 -maxdepth 1 -type d | sed -n 1p)
    [ -n "$_top" ] && [ -f "$_top/install.sh" ] && [ -f "$_top/lock-guard" ] && [ -f "$_top/randr-fix" ] && [ -f "$_top/VERSION" ] ||
        { echo "the download does not look like a screen-guard release; not installing" >&2; return 1; }
    for _f in install.sh lock-guard randr-fix; do
        sh -n "$_top/$_f" 2>/dev/null || { echo "$_f in the download is not valid shell; not installing" >&2; return 1; }
    done
    _got=$(sed -n 1p "$_top/VERSION" | tr -d ' \r')
    [ "$_got" = "$_new" ] || { echo "the download says it is version '$_got', not $_new; not installing" >&2; return 1; }
    for _f in install.sh lock-guard randr-fix; do
        [ "$(sed -n 's/^VERSION=//p' "$_top/$_f" | sed -n 1p)" = "$_new" ] ||
            { echo "$_f in the download does not carry version $_new; not installing" >&2; return 1; }
    done
    # keep the old scripts so an update can be undone by copying them back
    _prev=$CONFHOME/screen-guard/previous
    if [ -n "$_cur" ]; then
        mkdir -p "$_prev" && for _f in lock-guard randr-fix; do [ -f "$BIN/$_f" ] && cp "$BIN/$_f" "$_prev/$_f"; done
        echo "previous version ($_cur) kept in $_prev"
    fi
    # repeat the choices made at the first install (command-line options win)
    set --
    if [ "$VARIANTS" = auto ]; then _v=$(record_get VARIANTS); [ -n "$_v" ] && VARIANTS=$_v; fi
    if [ "$AUTOSTART_SET" = 0 ]; then _a=$(record_get AUTOSTART); [ -n "$_a" ] && { AUTOSTART=$_a; AUTOSTART_SET=1; }; fi
    if [ "$PREFIX_SET" = 0 ]; then _p=$(record_get PREFIX); [ -n "$_p" ] && PREFIX=$_p; fi
    [ "$VARIANTS" = auto ] || set -- "$@" --variants "$VARIANTS"
    [ "$AUTOSTART_SET" = 0 ] || set -- "$@" --autostart "$AUTOSTART"
    set -- "$@" --prefix "$PREFIX" --yes
    [ -n "$INIT_OVERRIDE" ] && set -- "$@" --init "$INIT_OVERRIDE"
    if [ -z "$(record_get VARIANTS)" ] && [ "$VARIANTS" = auto ]; then
        echo "(no record of an earlier install: detecting this machine again)"
    fi
    echo
    sh "$_top/install.sh" "$@" || { echo "the new installer failed; the old version is in $_prev" >&2; return 1; }
    echo
    echo "Updated to $_new."
    if [ -x "$BIN/lock-guard" ]; then
        _rs=y
        if [ "$YES" = 0 ] && interactive; then ask "Restart the running programs now? [Y/n] "; _rs=${ANSWER:-y}; fi
        case $_rs in n|N|no|NO) echo "Restart later with: $BIN/lock-guard --restart-all" ;; *) "$BIN/lock-guard" --restart-all ;; esac
    fi
    return 0
}

# ----------------------------------------------------------------------------- detection
# has_cmd NAME: is it installed?  (SG_DETECT_PATH replaces PATH for the lookup; used by the tests)
has_cmd() {
    _hp=$PATH; PATH=${SG_DETECT_PATH:-$PATH}
    command -v "$1" >/dev/null 2>&1; _hr=$?
    PATH=$_hp
    return "$_hr"
}

# Directories that may hold xsessions/ and wayland-sessions/ (Guix keeps them under the profile).
data_dirs() {
    if [ -n "${SG_DATA_DIRS:-}" ]; then printf '%s\n' "$SG_DATA_DIRS" | tr ':' '\n'; return; fi
    printf '%s\n' "${XDG_DATA_DIRS:-}" | tr ':' '\n'
    printf '%s\n' /usr/local/share /usr/share /run/current-system/profile/share \
        "$HOME/.guix-profile/share" "$HOME/.guix-home/profile/share" "$HOME/.local/share"
}

# session_names KIND: names of the session files (xsessions or wayland-sessions), one per line
session_names() {
    data_dirs | while read -r _d; do
        [ -n "$_d" ] || continue
        for _f in "$_d/$1"/*.desktop; do
            [ -f "$_f" ] || continue
            _n=${_f##*/}; echo "${_n%.desktop}"
        done
    done | sort -u
}

# found_cmds "a b c": the ones that are installed
found_cmds() {
    _fc=
    for _c in $1; do has_cmd "$_c" && _fc="$_fc $_c"; done
    echo "${_fc# }"
}

join() { tr '\n' ' ' | sed 's/ *$//; s/ /, /g'; }

detect_env() {
    # init system
    if [ -n "$INIT_OVERRIDE" ]; then
        INIT=$INIT_OVERRIDE
    elif [ -d /run/systemd/system ]; then
        INIT=systemd
    else
        INIT=$(cat /proc/1/comm 2>/dev/null) || INIT=
        case $INIT in
            shepherd|*shepherd*) INIT=shepherd ;;
            runit|s6-svscan|dinit|openrc-init) ;;
            *) if [ -d /run/openrc ] || [ -x /sbin/openrc ]; then INIT=openrc; else INIT=${INIT:-unknown}; fi ;;
        esac
    fi
    # X11
    XSESS=$(session_names xsessions | join)
    XBINS=$(found_cmds "Xorg startx xinit xfce4-session oxwm i3 openbox bspwm awesome dwm herbstluftwm qtile icewm fluxbox")
    X11_FOUND=0
    if [ -n "$XSESS" ] || [ -n "$XBINS" ]; then X11_FOUND=1; fi
    # Wayland
    WSESS=$(session_names wayland-sessions | join)
    WBINS=$(found_cmds "sway Hyprland labwc river niri wayfire mango mangowc mangowm dwl weston cage")
    WL_FOUND=0
    if [ -n "$WSESS" ] || [ -n "$WBINS" ]; then WL_FOUND=1; fi
    # the session this script runs in counts too
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then WL_FOUND=1; elif [ -n "${DISPLAY:-}" ]; then X11_FOUND=1; fi
    HAVE_DBUSMON=0; has_cmd dbus-monitor && HAVE_DBUSMON=1
    HAVE_DDCUTIL=0; has_cmd ddcutil && HAVE_DDCUTIL=1
}

yesno() { if [ "$1" = 1 ]; then echo yes; else echo no; fi; }

show_env() {
    echo "Detected on this machine:"
    echo "  init system : $INIT"
    _x=$(yesno "$X11_FOUND"); _w=$(yesno "$WL_FOUND")
    echo "  X11         : $_x${XBINS:+ - $(printf '%s' "$XBINS" | sed 's/ /, /g')}${XSESS:+; sessions: $XSESS}"
    echo "  Wayland     : $_w${WBINS:+ - $(printf '%s' "$WBINS" | sed 's/ /, /g')}${WSESS:+; sessions: $WSESS}"
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then echo "  this login  : Wayland ($WAYLAND_DISPLAY)"
    elif [ -n "${DISPLAY:-}" ]; then echo "  this login  : X11 ($DISPLAY)"
    else echo "  this login  : no graphical session (fine: running from a text console or ssh)"; fi
}

# default_variants: what to keep.  Parts for what is installed; everything if nothing can be told.
default_variants() {
    _dv=
    if [ "$X11_FOUND" = 0 ] && [ "$WL_FOUND" = 0 ]; then echo "$ALL_VARIANTS"; return; fi
    [ "$X11_FOUND" = 1 ] && _dv="$_dv x11"
    [ "$WL_FOUND" = 1 ] && _dv="$_dv wayland"
    [ "$HAVE_DBUSMON" = 1 ] && _dv="$_dv dbus"
    if [ "$WL_FOUND" = 1 ] || [ "$HAVE_DBUSMON" = 0 ]; then _dv="$_dv process"; fi
    [ "$HAVE_DDCUTIL" = 1 ] && _dv="$_dv ddc"
    echo "${_dv# }"
}

why_variant() {
    case $1 in
        x11) echo "X11 sessions: xrandr / xinput / wmctrl" ;;
        wayland) echo "Wayland sessions: wl-gammarelay-rs / libinput / your own commands" ;;
        dbus) echo "lock noticed over D-Bus (Xfce, GNOME, KDE ...)" ;;
        process) echo "lock noticed by its locker process (swaylock, gtklock ...)" ;;
        ddc) echo "lower the monitors' real backlight over DDC/CI (needs ddcutil)" ;;
    esac
}

# ask PROMPT: read an answer into ANSWER (empty = take the default).  Without a terminal (or with
# --yes) nothing is asked.
ask() {
    ANSWER=
    [ "$YES" = 1 ] && return 0
    if [ "$ASK_STDIN" = 1 ]; then printf '%s' "$1"; read -r ANSWER || ANSWER=; return 0; fi
    if [ -t 0 ]; then
        printf '%s' "$1"; read -r ANSWER || ANSWER=
    elif ( : < /dev/tty ) 2>/dev/null; then
        printf '%s' "$1"; read -r ANSWER < /dev/tty || ANSWER=
    fi
    return 0
}

interactive() { [ "$YES" = 0 ] && { [ "$ASK_STDIN" = 1 ] || [ -t 0 ] || ( : < /dev/tty ) 2>/dev/null; }; }

# parse_variants LIST DEFAULT: print the final list, or fail
parse_variants() {
    _list=$(printf '%s' "$1" | tr ',' ' ')
    case $_list in
        all) echo "$ALL_VARIANTS"; return 0 ;;
        none) return 1 ;;
    esac
    _rel=1
    for _t in $_list; do case $_t in +*|-*) ;; *) _rel=0 ;; esac; done
    if [ "$_rel" = 1 ] && [ -n "$_list" ]; then _cur=" $2 "; else _cur=" "; fi
    for _t in $_list; do
        case $_t in
            +*) _n=${_t#+}; _op=add ;;
            -*) _n=${_t#-}; _op=del ;;
            *) _n=$_t; _op=add ;;
        esac
        case " $ALL_VARIANTS " in *" $_n "*) ;; *) echo "unknown part '$_n' (choose from: $ALL_VARIANTS)" >&2; return 1 ;; esac
        if [ "$_op" = add ]; then
            case "$_cur" in *" $_n "*) ;; *) _cur="$_cur$_n " ;; esac
        else
            _cur=$(printf '%s' "$_cur" | sed "s/ $_n / /")
        fi
    done
    _out=
    for _v in $ALL_VARIANTS; do case "$_cur" in *" $_v "*) _out="$_out $_v" ;; esac; done
    echo "${_out# }"
}

check_variants() {
    case " $1 " in *" x11 "*|*" wayland "*) ;; *) echo "keep at least one of x11 / wayland" >&2; return 1 ;; esac
    case " $1 " in *" dbus "*|*" process "*) ;; *) echo "keep at least one of dbus / process (otherwise a lock cannot be noticed)" >&2; return 1 ;; esac
    return 0
}

choose_variants() {
    _def=$(default_variants)
    if [ "$VARIANTS" != auto ]; then
        KEEP=$(parse_variants "$VARIANTS" "$_def") || die "bad --variants"
        check_variants "$KEEP" || die "bad --variants"
        return 0
    fi
    echo
    echo "Parts of the program (the installed copy keeps the ones marked 'keep'):"
    for _v in $ALL_VARIANTS; do
        case " $_def " in *" $_v "*) _m="keep " ;; *) _m="prune" ;; esac
        printf '  %-8s %s  %s\n' "$_v" "$_m" "$(why_variant "$_v")"
    done
    KEEP=$_def
    if interactive; then
        while :; do
            ask "Press Enter to accept, or list the parts to keep (e.g. x11,dbus, or +wayland / -process, or all): "
            [ -n "$ANSWER" ] || break
            if _k=$(parse_variants "$ANSWER" "$_def") && check_variants "$_k"; then KEEP=$_k; break; fi
        done
    else
        echo "(not interactive: using the defaults; --variants LIST chooses)"
    fi
}

# --------------------------------------------------------------------------------- install
# prune_copy SRC DEST: copy SRC to DEST without the blocks of parts that are not in $KEEP
prune_copy() {
    awk -v keep=" $KEEP " -v stamp="# install.sh $(date +%Y-%m-%d): parts kept: $KEEP" '
        NR == 1 { print; print stamp; next }
        /^#@@ begin / { if (index(keep, " " $3 " ") == 0) { skip = 1; next } }
        /^#@@ end /   { if (skip) { skip = 0; next } }
        !skip { print }' "$1" > "$2" || return 1
    sh -n "$2" 2>/dev/null
}

merge_config() {
    _tpl=$("$BIN/$1" --print-config 2>/dev/null) || { echo "kept existing $2"; return 0; }
    _add=$(printf '%s\n' "$_tpl" | awk -v ex="$2" -v stamp="$(date +%Y-%m-%d)" '
        function flush(   i, miss) {
            miss = 0
            for (i = 1; i <= nk; i++) if (!(kname[i] in have)) miss = 1
            if (miss) {
                print ""
                if (!started) {
                    print "# --- added by install.sh on " stamp ": new options (defaults apply; uncomment to change) ---"
                    print ""
                    started = 1
                }
                for (i = 1; i <= nc; i++) print cline[i]
                for (i = 1; i <= nk; i++) if (!(kname[i] in have)) print "# " kline[i]
            }
            nc = 0; nk = 0
        }
        BEGIN {
            while ((getline l < ex) > 0)
                if (l ~ /^#? ?[A-Z][A-Z_]*=/) { sub(/^#? ?/, "", l); sub(/=.*/, "", l); have[l] = 1 }
        }
        /^[ \t]*$/ { flush(); next }
        /^[A-Z][A-Z_]*=/ { k = $0; sub(/=.*/, "", k); nk++; kname[nk] = k; kline[nk] = $0; next }
        { nc++; cline[nc] = $0 }
        END { flush() }')
    if [ -z "$_add" ]; then
        echo "kept existing $2 (it already lists every option)"
        return 0
    fi
    if ! { cp -p "$2" "$2.new" && printf '%s\n' "$_add" >> "$2.new" && mv -f "$2.new" "$2"; }; then
        rm -f "$2.new"
        die "could not update $2"
    fi
    _names=$(printf '%s\n' "$_add" | sed -n 's/^# \([A-Z][A-Z_]*\)=.*/\1/p' | tr '\n' ' ')
    echo "kept your settings in $2 and appended new options: $_names"
}

write_autostart_xdg() {
    mkdir -p "$AUTODIR" || die "cannot create $AUTODIR"
    for s in $INSTALLED; do
        case $s in
            lock-guard) c="Switch off chosen input devices, dim and run hooks while the screen is locked" ;;
            randr-fix) c="Reassert monitor layout, windows and desktop icons after RandR changes" ;;
        esac
        cat > "$AUTODIR/$s.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$s
Comment=$c
Exec=$BIN/$s
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
        echo "wrote $AUTODIR/$s.desktop"
    done
    # entries from an earlier, differently named install would start a second copy
    old=$(grep -l 'randr-fix\.sh\|lock-guard\.sh' "$AUTODIR"/*.desktop 2>/dev/null)
    if [ -n "$old" ]; then
        echo
        echo "NOTE: these autostart entries still start the old *.sh scripts; remove them:"
        printf '  %s\n' "$old"
    fi
}

write_autostart_systemd() {
    mkdir -p "$UNITDIR" || die "cannot create $UNITDIR"
    for s in $INSTALLED; do
        cat > "$UNITDIR/$s.service" <<EOF
[Unit]
Description=screen-guard: $s
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$BIN/$s
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
        echo "wrote $UNITDIR/$s.service"
    done
    _units=
    for s in $INSTALLED; do _units="$_units $s.service"; done
    echo "Enable with:  systemctl --user daemon-reload && systemctl --user enable --now${_units}"
    echo "NOTE: the service needs DISPLAY / WAYLAND_DISPLAY in the user manager's environment. Desktop"
    echo "  environments import them; with a bare window manager add, to its startup:"
    echo "    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE DBUS_SESSION_BUS_ADDRESS"
}

print_shepherd() {
    echo
    echo "Shepherd (Guix) has no file the installer can safely write. A user service for Guix Home"
    echo "(untested, adapt to your configuration; the service needs the session's environment, so"
    echo "starting from the compositor's own startup commands is simpler):"
    for s in $INSTALLED; do
        cat <<EOF
  (shepherd-service
    (provision '($s))
    (start #~(make-forkexec-constructor (list "$BIN/$s")))
    (stop #~(make-kill-destructor)))
EOF
    done
}

print_wm_hint() {
    echo
    echo "Window managers and compositors that do not read ~/.config/autostart (oxwm, mangowm, most"
    echo "tiling setups) need the line added to their own startup commands:"
    for s in $INSTALLED; do echo "    $BIN/$s --start"; done
}

if [ "$ACTION" = uninstall ]; then
    for s in $SCRIPTS; do
        rm -f "$BIN/$s" "$AUTODIR/$s.desktop"
        if [ -f "$UNITDIR/$s.service" ]; then
            if has_cmd systemctl; then systemctl --user disable --now "$s.service" >/dev/null 2>&1; fi
            rm -f "$UNITDIR/$s.service"
        fi
        echo "removed $s"
    done
    echo "Config files in $CONFHOME/{lock-guard,randr-fix} were kept."
    echo "Running copies keep running until you log out; stop them with: pkill -f lock-guard; pkill -f randr-fix"
    exit 0
fi

case $ACTION in
    checkupdate) do_check_update; exit $? ;;
    update) do_update; exit $? ;;
esac

detect_env
show_env
[ "$ACTION" = list ] && { echo; echo "Default parts to keep: $(default_variants)"; exit 0; }

for s in $SCRIPTS; do [ -f "$HERE/$s" ] || die "$HERE/$s not found - run install.sh from the unpacked folder"; done

choose_variants

PRUNED=
for _v in $ALL_VARIANTS; do case " $KEEP " in *" $_v "*) ;; *) PRUNED="$PRUNED $_v" ;; esac; done
echo
echo "Result:"
echo "  kept   : $(printf '%s' "$KEEP" | sed 's/ /, /g')"
if [ -n "$PRUNED" ]; then
    echo "  pruned : $(printf '%s' "${PRUNED# }" | sed 's/ /, /g')  (removed from the installed copy)"
    for _v in $PRUNED; do echo "           - $_v: $(why_variant "$_v")"; done
else
    echo "  pruned : nothing (this copy has every part)"
fi

# randr-fix works on X11 only; without the x11 part it is not installed at all
INSTALLED=lock-guard
case " $KEEP " in *" x11 "*) INSTALLED="lock-guard randr-fix" ;; esac

if [ "$AUTOSTART_SET" = 0 ] && interactive; then
    ask "Start at login via [xdg] (xdg = ~/.config/autostart; or systemd, shepherd, none): "
    if [ -n "$ANSWER" ]; then
        case $ANSWER in xdg|systemd|shepherd|none) AUTOSTART=$ANSWER ;; *) echo "unknown method '$ANSWER'; using xdg" ;; esac
    fi
fi

echo
mkdir -p "$BIN" || die "cannot create $BIN"
for s in $INSTALLED; do
    if [ "$s" = lock-guard ]; then
        prune_copy "$HERE/$s" "$BIN/$s.new" || { rm -f "$BIN/$s.new"; die "could not build $s with parts: $KEEP"; }
        case " $INSTALLED " in *" randr-fix "*) ;; *) sed 's/^SIBLING=randr-fix$/SIBLING=/' "$BIN/$s.new" > "$BIN/$s.new2" && mv -f "$BIN/$s.new2" "$BIN/$s.new" ;; esac
    else
        cp "$HERE/$s" "$BIN/$s.new" || die "could not install $s"
    fi
    if ! { chmod 755 "$BIN/$s.new" && mv -f "$BIN/$s.new" "$BIN/$s"; }; then
        rm -f "$BIN/$s.new"
        die "could not install $s"
    fi
    echo "installed $BIN/$s"
done
case " $INSTALLED " in
    *" randr-fix "*) ;;
    *) echo "randr-fix is X11 only: not installed."
       [ -e "$BIN/randr-fix" ] && echo "  (an older $BIN/randr-fix is still there; remove it if you do not want it)" ;;
esac

# configs: an existing one is kept as it is; options added by newer versions are appended
for s in $INSTALLED; do
    d=$CONFHOME/$s
    mkdir -p "$d" || die "cannot create $d"
    if [ -e "$d/config" ]; then
        merge_config "$s" "$d/config"
        continue
    fi
    if [ "$s" = randr-fix ] && [ -n "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && "$BIN/$s" --detect > "$d/config.new" 2>/dev/null; then
        mv -f "$d/config.new" "$d/config"
        echo "wrote $d/config from the monitors connected now - check it"
    else
        rm -f "$d/config.new"
        "$BIN/$s" --print-config > "$d/config" || die "could not write $d/config"
        echo "wrote $d/config (edit it before first use)"
        if [ "$s" = randr-fix ]; then
            echo "  monitors are detected only when installing from an X11 session; log in to X11 and run:"
            echo "    $BIN/randr-fix --detect > $d/config"
        fi
    fi
done

case $AUTOSTART in
    xdg) write_autostart_xdg; print_wm_hint ;;
    systemd) write_autostart_systemd ;;
    shepherd) print_shepherd; print_wm_hint ;;
    none) ;;
esac
[ "$INIT" = shepherd ] && [ "$AUTOSTART" != shepherd ] && print_shepherd

record_write

echo
miss=
case " $KEEP " in *" x11 "*) for c in awk xrandr xset xinput xev xprop wmctrl; do has_cmd "$c" || miss="$miss $c"; done ;; esac
case " $KEEP " in *" dbus "*) has_cmd dbus-monitor || miss="$miss dbus-monitor" ;; esac
case " $KEEP " in *" process "*) has_cmd pgrep || miss="$miss pgrep" ;; esac
case " $KEEP " in *" ddc "*) has_cmd ddcutil || miss="$miss ddcutil" ;; esac
has_cmd awk || miss="$miss awk"
[ -z "$miss" ] || echo "Missing tools:$miss  (see README.md for the package names)"
case " $KEEP " in
    *" wayland "*)
        has_cmd busctl || echo "Wayland dimming: busctl not found (wl-gammarelay-rs needs it; or set DIM_COMMAND / UNDIM_COMMAND)"
        has_cmd libinput || echo "Wayland UNDIM_KEY: libinput not found (package libinput-tools / libinput-utils; also needs the 'input' group)" ;;
esac
case " $KEEP " in
    *" ddc "*)
        if has_cmd ddcutil; then
            case " $(id -nG 2>/dev/null) " in *" i2c "*) ;; *) echo "Backlight: you are not in the 'i2c' group, which ddcutil usually needs (log in again after adding yourself)." ;; esac
            [ -e /dev/i2c-0 ] || [ -n "$(ls /dev/i2c-* 2>/dev/null)" ] || echo "Backlight: no /dev/i2c-* devices yet - load the i2c-dev kernel module (modprobe i2c-dev)."
        fi ;;
esac
case :${PATH:-}: in *:"$BIN":*) ;; *) echo "Note: $BIN is not in your PATH." ;; esac
echo "Start now (or log out and in):"
for s in $INSTALLED; do echo "  $BIN/$s --start"; done
echo "Already running? Restart them to use this version:"
echo "  $BIN/lock-guard --restart-all"
case " $INSTALLED " in *" randr-fix "*) echo "With the icons where you want them, save that layout: randr-fix --icon-update" ;; esac
