#!/bin/sh
# Run with sudo after quitting Caffeine. Removes only this fork's helper.
set -eu
if [ "$(/usr/bin/id -u)" != 0 ]; then
    echo 'Run this script with sudo after quitting Caffeine.' >&2
    exit 1
fi
label=net.ziyad.caffeine.lid-helper
state='/Library/Application Support/CaffeineLid'
/bin/launchctl bootout "system/$label" 2>/dev/null || true
# The daemon normally restores on exit. Also recover a prior hard crash.
if [ -f "$state/owned" ]; then
    /usr/bin/pmset -a disablesleep 0
    /bin/rm -f "$state/owned"
fi
/bin/rm -f "/Library/LaunchDaemons/$label.plist" "/Library/PrivilegedHelperTools/$label.sh"
/bin/rm -f "$state/status" "$state/owner" "$state/version" "$state/request/lease"
if [ -d "$state/request" ]; then /bin/rmdir "$state/request"; fi
if [ -d "$state" ]; then /bin/rmdir "$state"; fi
echo 'Caffeine lid helper removed.'
