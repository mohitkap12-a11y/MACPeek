#!/usr/bin/env bash
# Captures REAL macOS command output so MacPeek's parsers can be written and verified against what
# your Mac actually prints (never against output guessed from memory).
#
# Usage:  scripts/capture-fixtures.sh
# Output: ./macpeek-fixtures/*.txt  and a single combined ./macpeek-fixtures.txt you can attach.
#
# Privacy: this runs read-only commands on YOUR machine and saves the output locally. Serial numbers,
# UUIDs, MAC addresses, SSIDs-in-logs, your username and hostname are masked below, but please skim the
# result before sharing it. Nothing is uploaded by this script.
set -uo pipefail
OUT="macpeek-fixtures"
rm -rf "$OUT" "$OUT.txt"; mkdir -p "$OUT"

mask() {
  sed -E \
    -e 's/("?(serial_number|serial_num|Serial Number|serial number|IOPlatformSerialNumber|USB Serial Number|kUSBSerialNumberString|SerialNumber|serialNumber|spusb_serial)"?[ =:]+"?)[^",<[:space:]]+/\1<redacted>/g' \
    -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' \
    -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g' \
    -e "s/${USER}/<user>/g" \
    -e "s/$(scutil --get LocalHostName 2>/dev/null || echo __nohost__)/<host>/g"
}

# cap NAME COMMAND...   (runs the command, masks it, saves to $OUT/NAME.txt; never fails the script)
cap() {
  local name="$1"; shift
  echo "capturing $name ..."
  { echo "\$ $*"; "$@" 2>&1; echo "[exit status: $?]"; } | mask | head -c 400000 > "$OUT/$name.txt"
}
capsh() { # capsh NAME 'shell pipeline'
  local name="$1" cmd="$2"
  echo "capturing $name ..."
  { echo "\$ $cmd"; bash -c "$cmd" 2>&1; echo "[exit status: $?]"; } | mask | head -c 400000 > "$OUT/$name.txt"
}

cap sw_vers sw_vers
cap uname uname -a
cap hw_model sysctl hw.model hw.machine hw.memsize

# DisplayPeek
cap display_profiler_json system_profiler SPDisplaysDataType -json
cap display_profiler_text system_profiler SPDisplaysDataType

# USBPeek
cap usb_profiler_json system_profiler SPUSBDataType -json
cap usb_profiler_text system_profiler SPUSBDataType
cap thunderbolt_profiler_json system_profiler SPThunderboltDataType -json
capsh ioreg_usb 'ioreg -p IOUSB -l -w0 | head -n 600'

# BatteryPeek
cap battery_profiler_json system_profiler SPPowerDataType -json
cap pmset_batt pmset -g batt
cap pmset_ps pmset -g ps
capsh ioreg_battery 'ioreg -r -c AppleSmartBattery -w0'

# SleepPeek
cap pmset_assertions pmset -g assertions
cap pmset_assertions_detail pmset -g assertionslog
capsh pmset_log_wake "pmset -g log | grep -E ' (Wake|DarkWake|Sleep|Entering|Waking) ' | tail -n 150"
cap pmset_everything pmset -g

# NetPeek / DNSPeek
cap scutil_dns scutil --dns
cap scutil_nwi scutil --nwi
cap networksetup_ports networksetup -listallhardwareports
capsh networksetup_wifi 'networksetup -getinfo Wi-Fi'
cap route_default route -n get default
cap netstat_routes netstat -rn -f inet
cap ifconfig ifconfig
cap wifi_profiler_json system_profiler SPAirPortDataType -json
cap network_profiler_json system_profiler SPNetworkDataType -json
cap ping_gateway_3 ping -c 3 -t 5 1.1.1.1
capsh dns_lookup 'dscacheutil -q host -a name apple.com'

# ProcessPeek / EnvPeek / DiskPeek
cap ps_sample ps -axo pid,ppid,uid,user,state,lstart,etime,%cpu,rss,command
cap ps_self ps -o pid,ppid,uid,user,state,lstart,command -p $$
capsh ps_env_self 'ps eww -p $$ | head -c 6000'
cap launchctl_path launchctl getenv PATH
cap env_sample env
capsh top_sample 'top -l 1 -n 15 -stats pid,command,cpu,mem,state'

# FileLockPeek: hold a temp file open and ask lsof about it (field output, same format PortPeek parses)
tmp="$(mktemp -t macpeek-lock)"
( exec 9<>"$tmp"; capsh lsof_file "lsof -F pcLftn -- '$tmp'"; ) 2>/dev/null
rm -f "$tmp"

# PortPeek reference (live listeners on this Mac; compare with the committed fixtures)
capsh lsof_listen 'lsof -nP +c 0 -iTCP -sTCP:LISTEN -iUDP -FpcLftPnT | head -n 400'

{
  echo "MacPeek fixtures captured $(date -u +%FT%TZ)"
  for f in "$OUT"/*.txt; do
    echo; echo "=================== $(basename "$f") ==================="; cat "$f"
  done
} > "$OUT.txt"
echo
echo "Done. Review $OUT/ then attach $OUT.txt (or the whole folder zipped)."
du -sh "$OUT" "$OUT.txt"
