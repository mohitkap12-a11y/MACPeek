#!/usr/bin/env bash
# Captures REAL macOS command output so MacPeek's parsers can be written and verified against what
# your Mac actually prints (never against output guessed from memory).
#
# Usage:  scripts/capture-fixtures.sh
# Output: ./macpeek-fixtures/*.txt  and a single combined ./macpeek-fixtures.txt you can attach.
#
# Privacy: this runs read-only commands on YOUR machine and saves the output locally. Nothing is uploaded.
#  - It NEVER captures your real environment variables or other processes' command lines (those routinely
#    contain tokens/API keys). Environment and command-line samples come from throwaway test processes
#    with fake values; the process list uses command names only.
#  - Serial numbers, UUIDs, MAC addresses, your username and hostname are masked.
# Network/Wi-Fi/DNS output still contains IP addresses and nearby network names: skim the result before sharing.
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
# Runs a command but kills it after $1 seconds (macOS has no `timeout`), so a command that streams
# forever or hangs can never block the script. Job control (`set -m`) puts the command in its own process
# group, and the whole group is killed on timeout, so the children of a `bash -c 'a | b'` pipeline cannot
# survive and keep the capture pipe open. The watchdog's output goes to /dev/null so it never holds that pipe.
run_limited() {
  local secs="$1"; shift
  set -m
  "$@" </dev/null &
  local pid=$!
  set +m
  ( sleep "$secs"; kill -TERM -- "-$pid" 2>/dev/null; sleep 1; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watchdog=$!
  wait "$pid" 2>/dev/null; local rc=$?
  pkill -P "$watchdog" 2>/dev/null
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  return $rc
}
cap() {
  local name="$1"; shift
  echo "capturing $name ..."
  { echo "\$ $*"; run_limited 20 "$@" 2>&1; echo "[exit status: $?]"; } | mask | head -c 400000 > "$OUT/$name.txt"
}
capsh() { # capsh NAME 'shell pipeline'
  local name="$1" cmd="$2"
  echo "capturing $name ..."
  { echo "\$ $cmd"; run_limited 20 bash -c "$cmd" 2>&1; echo "[exit status: $?]"; } | mask | head -c 400000 > "$OUT/$name.txt"
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
# (`pmset -g assertionslog` streams forever, so it is deliberately not captured)
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
capsh dig_sample 'dig apple.com A +time=2 +tries=1; echo ---; dig @192.0.2.1 apple.com A +time=1 +tries=1'

# ProcessPeek / EnvPeek / DiskPeek
# Process list: command NAMES only (comm), never arguments or environments of your real processes.
cap ps_sample ps -axo pid,ppid,uid,user,state,lstart,etime,%cpu,rss,comm
# Command-line and environment SHAPE, from a throwaway process we start with fake values.
capsh ps_args_env_demo 'env -i FAKE_VAR=fake_value OTHER_VAR=other PATH=/usr/bin:/bin /bin/sleep 20 & p=$!; sleep 0.3; echo "--- ps -o args"; ps -o pid,ppid,uid,user,state,lstart,args -p $p; echo "--- ps eww"; ps eww -p $p; kill $p 2>/dev/null; wait $p 2>/dev/null'
# env/launchctl SHAPE only: names with values dropped, plus PATH (a list of directories).
capsh env_names 'env | sed -E "s/=.*$/=<value>/" | sort'
cap launchctl_path launchctl getenv PATH
capsh path_value 'echo "$PATH"'
capsh top_sample 'top -l 1 -n 15 -stats pid,command,cpu,mem,state'

# FileLockPeek: hold a temp file open and ask lsof about it (field output, same format PortPeek parses)
tmp="$(mktemp -t macpeek-lock)"
( exec 9<>"$tmp"; capsh lsof_file "lsof -F pcLfaltn -- '$tmp'"; ) 2>/dev/null
rm -f "$tmp"

# PortPeek reference (live listeners on this Mac; compare with the committed fixtures)
capsh lsof_listen 'lsof -nP +c 0 -iTCP -sTCP:LISTEN -iUDP -FpcLftPnT | head -n 400'

# GPUPeek: GPUs and their clients (property list), and a short powermetrics-free check that IOReport exists.
cap ioreg_gpu ioreg -r -d 2 -c IOAccelerator -a -w0
capsh ioreport_present 'ls -l /usr/lib/libIOReport.dylib 2>&1; sysctl hw.optional.arm64'

# ContainerPeek: only the tools you have installed; container names and images appear in the output.
for tool in docker podman limactl colima tart prlctl; do
  for dir in /opt/homebrew/bin /usr/local/bin; do
    [ -x "$dir/$tool" ] && echo "found $dir/$tool"
  done
done > "$OUT/container_tools.txt" 2>&1
command -v docker >/dev/null && { cap docker_ps docker ps --all --no-trunc --format '{{json .}}'; cap docker_stats docker stats --no-stream --no-trunc --format '{{json .}}'; cap docker_context docker context show; }
command -v podman >/dev/null && { cap podman_ps podman ps --all --format json; cap podman_stats podman stats --no-stream --format json; }
command -v limactl >/dev/null && cap limactl_list limactl list --json
command -v colima >/dev/null && cap colima_list colima list --json
command -v tart >/dev/null && cap tart_list tart list --format json
command -v prlctl >/dev/null && cap prlctl_list prlctl list --all --json

# ModelPeek: runner process NAMES only, and the runners' own local APIs (model names only).
capsh model_runner_names "ps -axo pid=,ppid=,comm= | grep -Ei 'ollama|lm studio|lmstudio|llama|mlx' | grep -v grep"
capsh ollama_ps 'curl -s --max-time 2 http://127.0.0.1:11434/api/ps'
capsh lmstudio_models 'curl -s --max-time 2 http://127.0.0.1:1234/api/v0/models'

# NetPeek extras / DNSPeek overrides / USBPeek Bluetooth / ProcessPeek launchd
cap scutil_proxy scutil --proxy
cap scutil_nc scutil --nc list
capsh tailscale_status '(/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json || tailscale status --json) 2>&1 | head -c 20000'
capsh wifi_preferred 'networksetup -listpreferredwirelessnetworks "$(networksetup -listallhardwareports | awk "/Wi-Fi/{getline; print \$2}")"'
cap etc_hosts cat /etc/hosts
capsh etc_resolver 'for f in /etc/resolver/*; do echo "== $f"; cat "$f"; done'
cap bluetooth system_profiler SPBluetoothDataType -json
capsh launchctl_list 'launchctl list | head -n 80'

{
  echo "MacPeek fixtures captured $(date -u +%FT%TZ)"
  for f in "$OUT"/*.txt; do
    echo; echo "=================== $(basename "$f") ==================="; cat "$f"
  done
} > "$OUT.txt"
echo
echo "Done. Review $OUT/ then attach $OUT.txt (or the whole folder zipped)."
du -sh "$OUT" "$OUT.txt"
