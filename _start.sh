#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo -e "$@"; }
retry() { # retry <attempts> <sleep> -- <cmd...>
  local n="$1" s="$2"; shift 2
  local i=1
  while true; do
    if "$@"; then return 0; fi
    if (( i >= n )); then return 1; fi
    sleep "$s"; ((i++))
  done
}

graceful_stop() {
  log "\n[signal] Stopping EarnApp..."
  earnapp stop || true
  exit 0
}
trap graceful_stop SIGTERM SIGINT

log "\n### ### ### ### ###"
log " Starting up ..."
log "### ### ### ### ###\n"

# 0) Kiểm tra UUID
if [[ -z "${EARNAPP_UUID:-}" ]]; then
  log "\nError: EARNAPP_UUID is missing or empty."
  log "Generate one:"
  log "  echo -n \"sdk-node-\" && head -c 1024 /dev/urandom | md5sum | tr -d ' -'\n"
  exit 255
fi

# 1) Fake system info (tùy chọn)
#    Bật nếu bạn đã COPY custom.sh vào image
if [[ -x /custom.sh ]]; then
  log ">>> Applying fake system info (custom.sh)"
  /custom.sh || log "[warn] custom.sh returned non-zero, continuing..."
else
  log "[info] /custom.sh not found or not executable; skipping fake step."
fi

# 2) Chuẩn bị thư mục & UUID
log "\n>>> Setting up /etc/earnapp ..."
mkdir -p /etc/earnapp
printf "%s" "$EARNAPP_UUID" > /etc/earnapp/uuid
touch /etc/earnapp/status
chmod a+wr /etc/earnapp /etc/earnapp/status
log "Found UUID : $EARNAPP_UUID"

# 3) Start tuần tự (không chạy nền) + retry cho chắc
log "\n>>> Starting EarnApp service"
retry 3 2 earnapp stop   || log "[warn] earnapp stop failed (ignoring)"
retry 5 2 earnapp start  || { log "[fatal] earnapp start failed"; exit 1; }
retry 5 2 earnapp register || log "[warn] earnapp register failed (maybe already registered)"
retry 5 2 earnapp status || log "[warn] earnapp status failed"
# run là tiến trình nền nội bộ của earnapp; script vẫn giữ container sống bằng tail
retry 3 2 earnapp run    || log "[warn] earnapp run failed (service may still be running)"

# 4) In thông tin nhanh (nếu có fake)
if command -v lsb_release >/dev/null 2>&1; then
  log "\n--- lsb_release ---"
  lsb_release || true
fi
if command -v hostnamectl >/dev/null 2>&1; then
  log "\n--- hostnamectl ---"
  hostnamectl || true
fi

log "\n### ### ### ### ### ###"
log " Running indefinitely ..."
log "### ### ### ### ### ###"
# Giữ container sống, và phản ứng SIGTERM để dừng earnapp
tail -f /dev/null &
wait %1
