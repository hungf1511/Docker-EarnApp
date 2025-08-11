#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo -e "$@"; }
retry(){ local n="$1" s="$2"; shift 2; local i=1; while true; do "$@" && return 0; (( i>=n )) && return 1; sleep "$s"; ((i++)); done; }
graceful_stop(){ log "\n[signal] Stopping EarnApp..."; earnapp stop || true; exit 0; }
trap graceful_stop SIGTERM SIGINT

log "\n### ### ### ### ###"
log " Starting up ..."
log "### ### ### ### ###\n"

# Chỉ cần 1 biến duy nhất
if [[ -z "${EARNAPP_UUID:-}" ]]; then
  log "\nError: EARNAPP_UUID is missing."
  log "Generate:\n  echo -n \"sdk-node-\" && head -c 1024 /dev/urandom | md5sum | tr -d ' -'\n"
  exit 255
fi

# Fake hệ thống
if [[ -x /custom.sh ]]; then
  log ">>> Applying fake system info"
  /custom.sh || log "[warn] custom.sh returned non-zero"
else
  log "[info] /custom.sh not found; skipping fake."
fi

# Cấu hình UUID
log "\n>>> Setting up /etc/earnapp ..."
mkdir -p /etc/earnapp
printf "%s" "$EARNAPP_UUID" > /etc/earnapp/uuid
touch /etc/earnapp/status
chmod a+wr /etc/earnapp /etc/earnapp/status
log "Found UUID : $EARNAPP_UUID"

# Start EarnApp (tuần tự + retry)
log "\n>>> Starting EarnApp"
retry 3 2 earnapp stop    || log "[warn] earnapp stop failed"
retry 5 2 earnapp start   || { log "[fatal] earnapp start failed"; exit 1; }
retry 5 2 earnapp register || log "[warn] earnapp register failed (maybe already registered)"
retry 5 2 earnapp status  || log "[warn] earnapp status failed"
retry 3 2 earnapp run     || log "[warn] earnapp run failed (service may still be running)"

# In thông tin wrapper (nếu có)
if command -v lsb_release >/dev/null 2>&1; then
  log "\n--- lsb_release ---"; lsb_release || true
fi
if command -v hostnamectl >/dev/null 2>&1; then
  log "\n--- hostnamectl ---"; hostnamectl || true
fi

log "\n### ### ### ### ### ###"
log " Running indefinitely ..."
log "### ### ### ### ### ###"
tail -f /dev/null &
wait %1
