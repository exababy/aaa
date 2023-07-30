#!/usr/bin/env bash

# Variables
user="steam"
IP="0.0.0.0"
PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
CUSTOM_FILES="${CUSTOM_FOLDER:-custom_files}"
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	DISTRO_OS=$NAME
	DISTRO_VERSION=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
	# linuxbase.org
	DISTRO_OS=$(lsb_release -si)
	DISTRO_VERSION=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	DISTRO_OS=$DISTRIB_ID
	DISTRO_VERSION=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	DISTRO_OS=Debian
	DISTRO_VERSION=$(cat /etc/debian_version)
else
	# Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
	DISTRO_OS=$(uname -s)
	DISTRO_VERSION=$(uname -r)
fi

# Download latest stop script
curl --silent --output "stop.sh" "https://raw.githubusercontent.com/kus/csgo-modded-server/master/stop.sh" && chmod +x stop.sh

# Check distrib
if ! command -v apt-get &> /dev/null; then
	echo "ERROR: OS distribution not supported... $DISTRO_OS $DISTRO_VERSION"
	exit 1
fi

# Check root
if [ "$EUID" -ne 0 ]; then
	echo "ERROR: Please run this script as root..."
	exit 1
fi

if [ -z "$PUBLIC_IP" ]; then
	echo "ERROR: Cannot retrieve your public IP address..."
	exit 1
fi

echo "Updating Operating System..."
apt update -y -q && apt upgrade -y -q >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Updating Operating System..."
	exit 1
fi

echo "Adding i386 architecture..."
dpkg --add-architecture i386 >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Cannot add i386 architecture..."
	exit 1
fi
cd /home/${user}/csgo/csgo/warmod/ && python3 -m http.server 80 </dev/null &>/dev/null &

cd /home/${user}

if [ "${DISTRO_OS}" == "Ubuntu" ]; then
	if [ "${DISTRO_VERSION}" == "22.04" ]; then
		# https://forums.alliedmods.net/showthread.php?t=336183
		rm /home/${user}/csgo/bin/libgcc_s.so.1
	fi
fi

echo "Downloading mod files..."
wget --quiet https://github.com/kus/csgo-modded-server/archive/master.zip
unzip -o -qq master.zip
cp -rlf csgo-modded-server-master/csgo/ /home/${user}/csgo/
cp -R csgo-modded-server-master/custom_files/ /home/${user}/csgo/custom_files/
cp -R csgo-modded-server-master/custom_files_example/ /home/${user}/csgo/custom_files_example/
rm -r csgo-modded-server-master master.zip

echo "Dynamically writing /home/$user/csgo/csgo/cfg/secrets.cfg"
if [ ! -z "$RCON_PASSWORD" ]; then
	echo "rcon_password						\"$RCON_PASSWORD\"" > /home/${user}/csgo/csgo/cfg/secrets.cfg
fi
if [ ! -z "$STEAM_ACCOUNT" ]; then
	echo "sv_setsteamaccount					\"$STEAM_ACCOUNT\"			// Required for online https://steamcommunity.com/dev/managegameservers" >> /home/${user}/csgo/csgo/cfg/secrets.cfg
fi
if [ ! -z "$SERVER_PASSWORD" ]; then
	echo "sv_password							\"$SERVER_PASSWORD\"" >> /home/${user}/csgo/csgo/cfg/secrets.cfg
fi
echo "" >> /home/${user}/csgo/csgo/cfg/secrets.cfg
echo "echo \"secrets.cfg executed\"" >> /home/${user}/csgo/csgo/cfg/secrets.cfg

echo "Merging in custom files from ${CUSTOM_FILES}"
cp -RT /home/${user}/csgo/${CUSTOM_FILES}/ /home/${user}/csgo/csgo/

chown -R ${user}:${user} /home/${user}/csgo

cd /home/${user}/csgo

echo "Starting server on $PUBLIC_IP:$PORT"
./srcds_run \
    -console \
    -usercon \
    -autoupdate \
    -game csgo \
    -tickrate $TICKRATE \
    -port $PORT \
    +map de_dust2 \
    -maxplayers_override $MAXPLAYERS \
    -authkey $API_KEY
    +ip $IP \
    +game_type 0 \
    +game_mode 0 \
    +mapgroup mg_active
