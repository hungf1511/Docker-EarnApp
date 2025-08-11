#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

FAKE_DIR="/etc/fake-sysinfo"
BIN_SAFE="/usr/local/bin"
mkdir -p "$FAKE_DIR" "$BIN_SAFE"

# ========== Helpers ==========
rand_hex(){ od -An -N"${1:-16}" -tx1 /dev/urandom | tr -d ' \n'; }
rand_alnum_upper(){ LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c "${1:-7}"; }
rand_int(){ local min=$1 max=$2 range=$((max-min+1)); local v=$((0x$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n'))); echo $(( (v%range)+min )); }
persist(){ local f="$1"; shift; [[ -s "$f" ]] || "$@" >"$f"; cat "$f"; }

# ========== Stable fake values (random once) ==========
HOSTNAME=$(persist "${FAKE_DIR}/hostname.txt" bash -c "printf 'DESKTOP-%s' \"\$(rand_alnum_upper 7)\"")
MACHINE_ID=$(persist "${FAKE_DIR}/machine_id.txt" bash -c "rand_hex 16")
BOOT_ID=$(bash -c "rand_hex 16")  # boot-id có thể đổi theo lần khởi động

VENDORS=(Acer Apple Asus Dell HP Lenovo MSI Samsung Sony LG Microsoft Alienware Razer Huawei IBM Intel Panasonic Fujitsu Toshiba Gigabyte EVGA Zotac Google)
PREF=(INS PAV THK ZEN OMN ASP LEG VOS XPS PRD ROG STR ENV TUF VIO GRM)
SUF=(LX GX TX VX FX NX ZX HX DX CX)
VENDOR=$(persist "${FAKE_DIR}/vendor.txt" bash -c "echo ${VENDORS[$(rand_int 0 $((${#VENDORS[@]}-1)))]}")
MODEL=$(persist "${FAKE_DIR}/model.txt" bash -c "echo ${PREF[$(rand_int 0 $((${#PREF[@]}-1)))]}-$(( $(rand_int 10000 99999) ))-${SUF[$(rand_int 0 $((${#SUF[@]}-1)))]}$(( $(rand_int 10 99) ))")
FW_VER=$(persist "${FAKE_DIR}/fw_ver.txt" bash -c 'printf "%d.%02d.%d-%d" "$(rand_int 1 9)" "$(rand_int 0 99)" "$(rand_int 0 9)" "$(rand_int 0 9)"')
FW_DATE=$(persist "${FAKE_DIR}/fw_date.txt" bash -c '
  start=$(date -d "2010-01-01" +%s); end=$(date -d "2020-12-31" +%s)
  r=$(rand_int "$start" "$end"); date -u -d "@$r" "+%a %Y-%m-%d"
')

KERNEL="$(uname -r)"; [[ "$KERNEL" == *-generic ]] || KERNEL="${KERNEL}-generic"

# ========== OS identity (khớp Ubuntu 24.04) ==========
OS_REL_CONTENT=$(cat <<'EOF'
NAME="Ubuntu"
VERSION="24.04 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04 LTS"
VERSION_ID="24.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble
EOF
)
printf "%s\n" "$OS_REL_CONTENT" > /etc/os-release
mkdir -p /usr/lib
printf "%s\n" "$OS_REL_CONTENT" > /usr/lib/os-release

# ========== Wrappers: hostnamectl / lsb_release ==========
cat >"${BIN_SAFE}/hostnamectl" <<EOF
#!/usr/bin/env bash
cat <<OUT
 Static hostname: ${HOSTNAME}
       Icon name: computer-desktop
         Chassis: desktop
      Machine ID: ${MACHINE_ID}
         Boot ID: ${BOOT_ID}
  Operating System: Ubuntu 24.04 LTS
            Kernel: ${KERNEL}
      Architecture: x86-64
  Hardware Vendor: ${VENDOR}
    Hardware Model: ${MODEL}
Firmware Version: ${FW_VER}
   Firmware Date: ${FW_DATE}
OUT
EOF
chmod +x "${BIN_SAFE}/hostnamectl"

cat >"${BIN_SAFE}/lsb_release" <<'EOF'
#!/usr/bin/env bash
cat <<OUT
No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 24.04 LTS
Release:        24.04
Codename:       noble
OUT
EOF
chmod +x "${BIN_SAFE}/lsb_release"

# ========== Fake DMI (bind nếu kernel/privilege cho phép) ==========
DMI_PATH="/sys/class/dmi/id"
if [[ -d "$DMI_PATH" && -w "$DMI_PATH" ]]; then
  mkdir -p /tmp/fake-dmi
  echo "$VENDOR" > /tmp/fake-dmi/sys_vendor
  echo "$MODEL" > /tmp/fake-dmi/product_name
  echo "1234567890" > /tmp/fake-dmi/product_serial
  echo "BIOS-${FW_VER}" > /tmp/fake-dmi/bios_version
  echo "$FW_DATE" > /tmp/fake-dmi/bios_date
  mount --bind /tmp/fake-dmi "$DMI_PATH" || true
fi

# ========== Fake MAC (nếu có quyền NET_ADMIN; nếu không thì skip) ==========
IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -n "${IFACE:-}" ]]; then
  NEW_MAC=$(printf "02:%02x:%02x:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
  ip link set dev "$IFACE" address "$NEW_MAC" 2>/dev/null || true
fi

# ========== Đồng bộ machine-id ==========
echo "$MACHINE_ID" > /etc/machine-id

# ========== Log ==========
echo "[fake-sysinfo] Applied."
echo " Hostname     : $HOSTNAME"
echo " Vendor/Model : $VENDOR / $MODEL"
echo " Firmware     : $FW_VER ($FW_DATE)"
echo " Kernel       : $KERNEL"
if [[ -n "${IFACE:-}" ]]; then
  ip -o link show "$IFACE" | awk -F 'link/ether ' '{print " MAC         : " $2}' | cut -d' ' -f1
fi
