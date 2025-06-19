#!/bin/bash

##### This is run during Docker image build stage #####

##### Generate multiple hardware profiles #####
NUM_PROFILES=100
PROFILE_DIR="/hardware_profiles"

mkdir -p $PROFILE_DIR

for i in $(seq 1 $NUM_PROFILES)
  do
    profile_path="$PROFILE_DIR/profile_$i"
    mkdir -p $profile_path/sys/class/dmi/id

    hostname="DESKTOP-$(tr -dc 'A-Z0-9' </dev/urandom | head -c 7)"
    machine_id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    boot_id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

    vendors=("Acer" "Apple" "Asus" "Dell" "HP" "Lenovo" "MSI" "Samsung" "Sony" "LG" "Microsoft" "Alienware" "Razer" "Huawei" "IBM" "Intel" "Panasonic" "Fujitsu" "Toshiba" "Gigabyte" "EVGA" "Zotac" "Google")
    vendor=${vendors[$RANDOM % ${#vendors[@]}]}

    prefixes=("INS" "PAV" "THK" "ZEN" "OMN" "ASP" "LEG" "VOS" "XPS" "PRD" "ROG" "STR" "ENV" "TUF" "VIO" "GRM")
    prefix=${prefixes[$RANDOM % ${#prefixes[@]}]}
    model_number=$(shuf -i 10000-99999 -n 1)
    suffixes=("LX" "GX" "TX" "VX" "FX" "NX" "ZX" "HX" "DX" "CX")
    suffix=${suffixes[$RANDOM % ${#suffixes[@]}]}
    version=$(shuf -i 10-99 -n 1)
    model="$prefix-$model_number-$suffix$version"

    major=$((RANDOM % 9 + 1))
    minor=$(printf "%02d" $((RANDOM % 100)))
    patch=$((RANDOM % 10))
    build=$((RANDOM % 10))
    firmware_version="${major}.${minor}.${patch}-${build}"

    start_date="2010-01-01"
    end_date="2020-12-31"
    start_sec=$(date -d "$start_date" +%s)
    end_sec=$(date -d "$end_date" +%s)
    rand_sec=$(shuf -i ${start_sec}-${end_sec} -n 1)
    firmware_date=$(date -d "@$rand_sec" "+%Y-%m-%d")

    echo "$vendor" > $profile_path/sys/class/dmi/id/sys_vendor
    echo "$model" > $profile_path/sys/class/dmi/id/product_name
    echo "$firmware_version" > $profile_path/sys/class/dmi/id/bios_version
    echo "$firmware_date" > $profile_path/sys/class/dmi/id/bios_date

    echo "$hostname" > $profile_path/hostname
    echo "$machine_id" > $profile_path/machine_id
    echo "$boot_id" > $profile_path/boot_id
  done

##### Create override commands #####

cat << 'EOF' > /usr/bin/lsb_release
#!/bin/bash
echo "No LSB modules are available.
Distributor ID: Ubuntu
Description:    Ubuntu 24.04 LTS
Release:        24.04
Codename:       noble"
EOF
chmod +x /usr/bin/lsb_release

cat << 'EOF' > /usr/bin/hostnamectl
#!/bin/bash
if [ -f /runtime_profile/hostname ]; then
  hostname=$(cat /runtime_profile/hostname)
  machine_id=$(cat /runtime_profile/machine_id)
  boot_id=$(cat /runtime_profile/boot_id)
  vendor=$(cat /runtime_profile/sys/class/dmi/id/sys_vendor)
  model=$(cat /runtime_profile/sys/class/dmi/id/product_name)
  firmware_version=$(cat /runtime_profile/sys/class/dmi/id/bios_version)
  firmware_date=$(cat /runtime_profile/sys/class/dmi/id/bios_date)
else
  hostname="UNKNOWN"
  machine_id="UNKNOWN"
  boot_id="UNKNOWN"
  vendor="UNKNOWN"
  model="UNKNOWN"
  firmware_version="UNKNOWN"
  firmware_date="UNKNOWN"
fi
echo " Static hostname: ${hostname}
       Icon name: computer
         Chassis: desktop
      Machine ID: ${machine_id}
         Boot ID: ${boot_id}
  Virtualization: none
Operating System: Ubuntu 24.04 LTS
          Kernel: Linux 6.15.0-00-generic
    Architecture: x86-64
 Hardware Vendor: ${vendor}
  Hardware Model: ${model}
Firmware Version: ${firmware_version}
   Firmware Date: ${firmware_date}"
EOF
chmod +x /usr/bin/hostnamectl

##### Create runtime entrypoint for container #####

cat << 'EOF' > /docker-entrypoint.sh
#!/bin/bash

set -e

# Randomly select hardware profile at container startup
SELECTED_PROFILE=$(find /hardware_profiles -mindepth 1 -maxdepth 1 -type d | shuf -n 1)
mkdir -p /runtime_profile
cp -r $SELECTED_PROFILE/* /runtime_profile/

echo "Loaded hardware profile: $SELECTED_PROFILE"

# Existing startup logic:

if [[ -z "$EARNAPP_UUID" ]]; then
    echo "Error: EARNAPP_UUID is missing or empty."
    echo "Generate one with:"
    echo 'echo -n "sdk-node-" && head -c 1024 /dev/urandom | md5sum | tr -d " -"'
    exit 255
fi

echo "### Running custom.sh if exists ###"
if [ -f "/custom.sh" ]; then
    chmod +x /custom.sh
    bash /custom.sh
fi

mkdir -p /etc/earnapp
chmod -R a+rwx /etc/earnapp
chmod -R a+rwx /usr/bin/earnapp
echo "$EARNAPP_UUID" > /etc/earnapp/uuid

echo "Starting EarnApp service..."
echo | md5sum /usr/bin/earnapp
sleep 3
/usr/bin/earnapp stop
sleep 3
/usr/bin/earnapp start
sleep 3
/usr/bin/earnapp status
sleep 3
/usr/bin/earnapp register

echo "Container running indefinitely..."
tail -f /dev/null
EOF
chmod +x /docker-entrypoint.sh
