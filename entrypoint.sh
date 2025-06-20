#!/bin/bash

echo "### ### ### ### ###"
echo " Starting up ... "
echo "### ### ### ### ###"
echo " "

echo "🔧 Running hardware spoof..."
/custom_hardware_generate.sh || echo "Hardware spoof failed, continue anyway"

echo "### Selecting hardware profile ###"
SELECTED_PROFILE=$(find /hardware_profiles -mindepth 1 -maxdepth 1 -type d | shuf -n 1)
mkdir -p /runtime_profile
cp -r $SELECTED_PROFILE/* /runtime_profile/

echo "Loaded hardware profile: $SELECTED_PROFILE"
echo "$GETINFO"
echo " "
echo "📦 Installing EarnApp SDK..."
echo "yes" | wget -qO- https://brightdata.com/static/earnapp/install.sh | bash

# 3️⃣ In ra UUID sau khi cài
UUID=$(cat /etc/earnapp/uuid)
echo "✅ EarnApp UUID: $UUID"
echo "✅ Registration link: https://earnapp.com/r/$UUID"

# 4️⃣ Giữ container sống để backend SDK tiếp tục daemon chạy ngầm
echo "🎯 Container is running, EarnApp SDK handled by system"
tail -f /dev/null
