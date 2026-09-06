#!/bin/sh
# Installed root-owned by Caffeine after a one-time macOS administrator prompt.
# launchd runs this fixed script. Client input is data, never executable code.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
owner_uid=$1
case "$owner_uid" in ''|*[!0-9]*) exit 2 ;; esac
state='/Library/Application Support/CaffeineLid'
lease="$state/request/lease"
umask 022
changed=0
nonce=''
set_status() {
    # Clients must never observe a truncated/partially written status.
    printf '%s' "$1" > "$state/status.next"
    /bin/mv -f "$state/status.next" "$state/status"
}
restore() {
    if [ "$changed" = 1 ] || [ -f "$state/owned" ]; then
        until /usr/bin/pmset -a disablesleep 0; do /bin/sleep 2; done
        rm -f "$state/owned"
    fi
    changed=0
}
cleanup() {
    trap '' HUP INT TERM
    restore
    set_status offline
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
# A durable ownership marker allows recovery after the helper is killed or the
# machine restarts. Never restore a power override that this helper didn't own.
restore
printf '%s' "$owner_uid" > "$state/owner"
printf '2' > "$state/version"
set_status idle
phase=idle
last_nonce=''
while :; do
    value=''
    if [ -f "$lease" ] && [ ! -L "$lease" ]; then
        # Bounded read: a client cannot make the root process load a huge file.
        value=$(/bin/dd if="$lease" bs=128 count=1 2>/dev/null) || value=''
    fi
    kind=${value%%:*}
    rest=${value#*:}
    pid=${rest%%:*}
    incoming_nonce=${rest#*:}
    valid=1
    case "$kind" in pending|locked) ;; *) valid=0 ;; esac
    case "$pid" in ''|*[!0-9]*) valid=0 ;; esac
    case "$incoming_nonce" in ''|*[!A-Fa-f0-9-]*) valid=0 ;; esac
    [ "${#incoming_nonce}" = 36 ] || valid=0
    # Sample the lease before the clock. A concurrent atomic renewal can cross
    # a second boundary; reading date first falsely rejects it as future-dated.
    modified=$(/usr/bin/stat -f %m "$lease" 2>/dev/null) || modified=0
    now=$(/bin/date +%s)
    if [ "$((now - modified))" -gt 10 ] || [ "$modified" -gt "$now" ]; then valid=0; fi
    if [ "$valid" = 1 ]; then
        user=$(/bin/ps -p "$pid" -o uid= | /usr/bin/tr -d ' ') || user=''
        [ "$user" = "$owner_uid" ] || valid=0
    fi
    if [ "$phase" != idle ]; then
        identity_now=$(/bin/ps -p "$session_pid" -o lstart=) || identity_now=''
        if [ "$valid" = 0 ] || [ "$incoming_nonce" != "$nonce" ] ||
           [ "$pid" != "$session_pid" ] || [ "$identity_now" != "$identity" ] ||
           { [ "$phase" = active ] && [ "$kind" != locked ]; } ||
           { [ "$phase" = ready ] && [ "$((now - started))" -gt 30 ]; }; then
            restore
            phase=idle
            set_status idle
        fi
    fi
    if [ "$phase" = idle ] && [ "$valid" = 1 ] &&
       [ "$kind" = pending ] && [ "$incoming_nonce" != "$last_nonce" ]; then
        nonce=$incoming_nonce
        last_nonce=$nonce
        original=$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" {print $2}') || original=''
        if [ "$original" = 0 ]; then
            session_pid=$pid
            identity=$(/bin/ps -p "$pid" -o lstart=) || identity=''
            started=$now
            phase=ready
            set_status "ready:$nonce"
        else
            set_status "conflict:$nonce"
        fi
    elif [ "$phase" = ready ] && [ "$valid" = 1 ] && [ "$kind" = locked ]; then
        # Recheck after the lock handshake: another app may have changed the
        # global setting while the client was preparing its lock screen.
        before=$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" {print $2}') || before=''
        if [ "$before" != 0 ]; then
            phase=idle
            set_status "conflict:$nonce"
            /bin/sleep 1
            continue
        fi
        # Ownership is recorded BEFORE changing power, for crash recovery.
        printf '1' > "$state/owned"
        changed=1
        current=''
        if /usr/bin/pmset -a disablesleep 1; then
            current=$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" {print $2}') || current=''
        fi
        if [ "$current" = 1 ]; then
            phase=active
            set_status "active:$nonce"
        else
            restore
            phase=idle
            set_status "failed:$nonce"
        fi
    fi
    /bin/sleep 1
done
