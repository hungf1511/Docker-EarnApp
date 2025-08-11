#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

FAKE_DIR="/etc/fake-sysinfo"
BIN_SAFE="/usr/local/bin"
mkdir -p "$FAKE_DIR" "$BIN_SAFE"

# === Helper ===
rand_hex(){ od -An -N"${1:-16}" -tx1 /dev/urandom | tr -d ' \n'; }
rand_alnum_upper(){ LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c "${1:-7}"; }
rand_int(){ local min=$1 max=$2 range=$((max-min+1)); local v=$((0x$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n'))); echo $(( (v%range)+min )); }
persist(){ local f="$1"; shift; [[ -s "$f" ]] || "$@" >"$f"; cat "$f"; }

# === Generate stable fake info ===
HOSTNAME=$(persist "${FAKE_DIR}/hostname.txt" bash -c "printf 'DESKTOP-%s' \"\$(rand_alnum_upper 7)\"")
MACHINE_ID=$(persist "${FAKE_DIR}/machine_id.txt" bash -c "rand_hex 16")
BOOT_ID=$(bash -c "rand_hex 16")

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

KERNEL="$(uname -r)"
[[ "$KERNEL" == *-generic ]] || KERNEL="${KERNEL}-generic"

# === Fake /etc/os-release & /usr/lib/os-release ===
OS_REL_CONTENT=$(cat <<EOF
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
echo "$OS_REL_CONTENT" > /etc/os-release
mkdir -p /usr/lib
echo "$OS_REL_CONTENT" > /usr/lib/os-release

# === Fake hostnamectl & lsb_release ===
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

cat >"${BIN_SAFE}/lsb_release" <<EOF
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

# === Fake /sys/class/dmi/id/* ===
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

# === Fake MAC address ===
IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -n "$IFACE" ]]; then
  NEW_MAC=$(printf "02:%02x:%02x:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
  ip link set dev "$IFACE" address "$NEW_MAC" || true
fi

# === Fake machine-id ===
echo "$MACHINE_ID" > /etc/machine-id

# === Build LD_PRELOAD lib for /proc fake ===
cat > /tmp/fakeproc.c <<'C_SRC'
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>

static const char *FAKE_CPUINFO =
"processor\t: 0\n"
"vendor_id\t: GenuineIntel\n"
"cpu family\t: 6\n"
"model\t\t: 158\n"
"model name\t: Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz\n"
"stepping\t: 10\n"
"microcode\t: 0xde\n"
"cpu MHz\t\t: 3600.000\n"
"cache size\t: 12288 KB\n"
"physical id\t: 0\n"
"siblings\t: 8\n"
"core id\t\t: 0\n"
"cpu cores\t: 8\n"
"apicid\t\t: 0\n"
"initial apicid\t: 0\n"
"fpu\t\t: yes\n"
"fpu_exception\t: yes\n"
"cpuid level\t: 22\n"
"wp\t\t: yes\n"
"flags\t\t: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr\n"
"\n";

static const char *FAKE_MEMINFO =
"MemTotal:       32777280 kB\n"
"MemFree:        16438200 kB\n"
"MemAvailable:   24593240 kB\n"
"Buffers:         123456 kB\n"
"Cached:         1234567 kB\n"
"\n";

typedef ssize_t (*orig_read_t)(int, void*, size_t);
typedef FILE* (*orig_fopen_t)(const char*, const char*);

ssize_t read(int fd, void *buf, size_t count) {
    static orig_read_t orig_read = NULL;
    if (!orig_read) orig_read = (orig_read_t)dlsym(RTLD_NEXT, "read");

    char path[256];
    snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    char target[256];
    ssize_t len = readlink(path, target, sizeof(target)-1);
    if (len > 0) {
        target[len] = '\0';
        if (strcmp(target, "/proc/cpuinfo") == 0) {
            size_t l = strlen(FAKE_CPUINFO);
            if (count < l) l = count;
            memcpy(buf, FAKE_CPUINFO, l);
            return l;
        }
        if (strcmp(target, "/proc/meminfo") == 0) {
            size_t l = strlen(FAKE_MEMINFO);
            if (count < l) l = count;
            memcpy(buf, FAKE_MEMINFO, l);
            return l;
        }
    }
    return orig_read(fd, buf, count);
}

FILE* fopen(const char *pathname, const char *mode) {
    static orig_fopen_t orig_fopen = NULL;
    if (!orig_fopen) orig_fopen = (orig_fopen_t)dlsym(RTLD_NEXT, "fopen");

    if (strcmp(pathname, "/proc/cpuinfo") == 0) {
        FILE *memstream = fmemopen((void*)FAKE_CPUINFO, strlen(FAKE_CPUINFO), "r");
        return memstream;
    }
    if (strcmp(pathname, "/proc/meminfo") == 0) {
        FILE *memstream = fmemopen((void*)FAKE_MEMINFO, strlen(FAKE_MEMINFO), "r");
        return memstream;
    }
    return orig_fopen(pathname, mode);
}
C_SRC

gcc -shared -fPIC -o /usr/local/lib/fakeproc.so /tmp/fakeproc.c -ldl

# Export LD_PRELOAD globally
if ! grep -q "fakeproc.so" /etc/ld.so.preload 2>/dev/null; then
    echo "/usr/local/lib/fakeproc.so" >> /etc/ld.so.preload
fi

# === Diagnostics ===
echo "[fake-sysinfo] Applied all layers."
echo " Hostname      : $HOSTNAME"
echo " Vendor/Model  : $VENDOR / $MODEL"
echo " Firmware      : $FW_VER ($FW_DATE)"
echo " Kernel        : $KERNEL"
echo " MAC           : $(ip link show "$IFACE" | awk '/ether/ {print $2; exit}')"
