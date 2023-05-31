#!/bin/bash
# Created by MichaIng / micha@dietpi.com / dietpi.com
{
##########################################
# Load DietPi-Globals
##########################################
if [[ -f '/boot/dietpi/func/dietpi-globals' ]]
then
	. /boot/dietpi/func/dietpi-globals
else
	curl -sSf "https://raw.githubusercontent.com/${G_GITOWNER:=MichaIng}/DietPi/${G_GITBRANCH:=master}/dietpi/func/dietpi-globals" -o /tmp/dietpi-globals || exit 1
	# shellcheck disable=SC1091
	. /tmp/dietpi-globals
	G_EXEC_NOHALT=1 G_EXEC rm /tmp/dietpi-globals
	export G_GITOWNER G_GITBRANCH G_HW_ARCH_NAME=$(uname -m)
fi
case $G_HW_ARCH_NAME in
	'armv6l') export G_HW_ARCH=1;;
	'armv7l') export G_HW_ARCH=2;;
	'aarch64') export G_HW_ARCH=3;;
	'x86_64') export G_HW_ARCH=10;;
	'riscv64') export G_HW_ARCH=11;;
	*) G_DIETPI-NOTIFY 1 "Unsupported host system architecture \"$G_HW_ARCH_NAME\" detected, aborting..."; exit 1;;
esac
readonly G_PROGRAM_NAME='DietPi-Software_test_setup'
G_CHECK_ROOT_USER
G_CHECK_ROOTFS_RW
readonly FP_ORIGIN=$PWD # Store origin dir
G_INIT
G_EXEC cd "$FP_ORIGIN" # Process everything in origin dir instead of /tmp/$G_PROGRAM_NAME

##########################################
# Process inputs
##########################################
DISTRO=
ARCH=
SOFTWARE=
RPI=
while (( $# ))
do
	case $1 in
		'-d') shift; DISTRO=$1;;
		'-a') shift; ARCH=$1;;
		'-s') shift; SOFTWARE=$1;;
		'-rpi') shift; RPI=$1;;
		*) G_DIETPI-NOTIFY 1 "Invalid input \"$1\", aborting..."; exit 1;;
	esac
	shift
done
[[ $DISTRO =~ ^('buster'|'bullseye'|'bookworm')$ ]] || { G_DIETPI-NOTIFY 1 "Invalid distro \"$DISTRO\" passed, aborting..."; exit 1; }
case $ARCH in
	'armv6l') image="DietPi_Container-ARMv6-${DISTRO^}" arch=1;;
	'armv7l') image="DietPi_Container-ARMv7-${DISTRO^}" arch=2;;
	'aarch64') image="DietPi_Container-ARMv8-${DISTRO^}" arch=3;;
	'x86_64') image="DietPi_Container-x86_64-${DISTRO^}" arch=10;;
	'riscv64') image="DietPi_Container-RISC-V-Sid" arch=11;;
	*) G_DIETPI-NOTIFY 1 "Invalid architecture \"$ARCH\" passed, aborting..."; exit 1;;
esac
[[ $SOFTWARE =~ ^[0-9\ ]+$ ]] || { G_DIETPI-NOTIFY 1 "Invalid software list \"$SOFTWARE\" passed, aborting..."; exit 1; }
[[ $RPI =~ ^(|'false'|'true')$ ]] || { G_DIETPI-NOTIFY 1 "Invalid RPi flag \"$RPI\" passed, aborting..."; exit 1; }

# Workaround for "Could not execute systemctl:  at /usr/bin/deb-systemd-invoke line 145." during Apache2 DEB postinst in 32-bit ARM Bookworm container: https://lists.ubuntu.com/archives/foundations-bugs/2022-January/467253.html
[[ $SOFTWARE =~ (^| )83( |$) && $DISTRO == 'bookworm' ]] && (( $arch < 3 )) && { echo '[ WARN ] Installing Lighttpd instead of Apache due to a bug in 32-bit ARM containers'; SOFTWARE=$(sed -E 's/(^| )83( |$)/\184\2/g' <<< "$SOFTWARE"); }

##########################################
# Create service and port lists
##########################################
aSERVICES=() aTCP=() aUDP=() aCOMMANDS=() aDELAY=()
Process_Software()
{
	local i
	for i in "$@"
	do
		case $i in
			'webserver') [[ $SOFTWARE =~ (^| )8[345]( |$) ]] || aSERVICES[84]='lighttpd' aTCP[84]='80';; # Lighttpd as default due to above bug in 32-bit ARM Bookworm containers
			0) aCOMMANDS[i]='ssh -V';;
			1) aCOMMANDS[i]='smbclient -V';;
			2) aSERVICES[i]='fahclient' aTCP[i]='7396';;
			7) aCOMMANDS[i]='ffmpeg -version';;
			9) aCOMMANDS[i]='node -v';;
			16) aSERVICES[i]='microblog-pub' aTCP[i]='8007';;
			17) aCOMMANDS[i]='git -v';;
			28|120) aSERVICES[i]='vncserver' aTCP[i]='5901';;
			29) aSERVICES[i]='xrdp' aTCP[i]='3389';;
			30) aSERVICES[i]='nxserver' aTCP[i]='4000';;
			32) aSERVICES[i]='ympd' aTCP[i]='1337';;
			33) (( $arch == 10 )) && aSERVICES[i]='airsonic' aTCP[i]='8080' aDELAY[i]=30;; # Fails in QEMU-emulated containers, probably due to missing device access
			35) aSERVICES[i]='logitechmediaserver' aTCP[i]='9000';;
			36) aCOMMANDS[i]='squeezelite -t';; # Service listens on random high UDP port and exits if no audio device has been found, which does not exist on GitHub Actions runners, respectively within the containers
			37) aSERVICES[i]='shairport-sync' aTCP[i]='5000';; # AirPlay 2 would be TCP port 7000
			39) aSERVICES[i]='minidlna' aTCP[i]='8200';;
			41) aSERVICES[i]='emby-server' aTCP[i]='8096';;
			42) aSERVICES[i]='plexmediaserver' aTCP[i]='32400';;
			43) aSERVICES[i]='mumble-server' aTCP[i]='64738';;
			44) aSERVICES[i]='transmission-daemon' aTCP[i]='9091';;
			45) aSERVICES[i]='deluged deluge-web' aTCP[i]='8112 58846 6882';;
			46) aSERVICES[i]='qbittorrent' aTCP[i]='1340 6881';;
			49) aSERVICES[i]='gogs' aTCP[i]='3000';;
			50) aSERVICES[i]='syncthing' aTCP[i]='8384';;
			51) aCOMMANDS[i]='/usr/games/opentyrian/opentyrian -h';;
			52) aSERVICES[i]='cuberite' aTCP[i]='1339';;
			53) aSERVICES[i]='mineos' aTCP[i]='8443';;
			58) aSERVICES[i]='tailscale';; # aUDP[i]='????';;
			59) aSERVICES[i]='raspimjpeg';;
			#60) aUDP[i]='53 68';; Cannot be installed in CI since a WiFi interface is required
			#61) aSERVICES[i]='tor' aUDP[i]='9040';; Cannot be installed in CI since a WiFi interface is required
			65) aSERVICES[i]='netdata' aTCP[i]='19999';;
			66) aSERVICES[i]='rpimonitor' aTCP[i]='8888';;
			71) aSERVICES[i]='webiopi' aTCP[i]='8002';;
			73) aSERVICES[i]='fail2ban';;
			74) aSERVICES[i]='influxdb' aTCP[i]='8086 8088';;
			77) aSERVICES[i]='grafana-server' aTCP[i]='3001';;
			80) aSERVICES[i]='ubooquity' aTCP[i]='2038 2039';;
			83) aSERVICES[i]='apache2' aTCP[i]='80';;
			84) aSERVICES[i]='lighttpd' aTCP[i]='80';;
			85) aSERVICES[i]='nginx' aTCP[i]='80';;
			86) aSERVICES[i]='roon-extension-manager';;
			88) aSERVICES[i]='mariadb' aTCP[i]='3306';;
			89) case $DISTRO in 'buster') aSERVICES[i]='php7.3-fpm';; 'bullseye') aSERVICES[i]='php7.4-fpm';; *) aSERVICES[i]='php8.2-fpm';; esac;;
			91) aSERVICES[i]='redis-server' aTCP[i]='6379';;
			#93) aSERVICES[i]='pihole-FTL' aUDP[i]='53';; # Cannot be installed non-interactively
			94) aSERVICES[i]='proftpd' aTCP[i]='21';;
			95) aSERVICES[i]='vsftpd' aTCP[i]='21';;
			96) aSERVICES[i]='smbd' aTCP[i]='139 445';;
			97) aSERVICES[i]='openvpn' aUDP[i]='1194';;
			98) aSERVICES[i]='haproxy' aTCP[i]='80';;
			99) aSERVICES[i]='node_exporter' aTCP[i]='9100';;
			100) aSERVICES[i]='pijuice';; # aTCP[i]='????';;
			104) aSERVICES[i]='dropbear' aTCP[i]='22';;
			105) aSERVICES[i]='ssh' aTCP[i]='22';;
			106) aSERVICES[i]='lidarr' aTCP[i]='8686';;
			107) aSERVICES[i]='rtorrent' aTCP[i]='49164' aUDP[i]='6881';;
			109) aSERVICES[i]='nfs-kernel-server' aTCP[i]='2049';;
			111) aSERVICES[i]='urbackupsrv' aTCP[i]='55414';;
			115) aSERVICES[i]='webmin' aTCP[i]='10000';;
			116) aSERVICES[i]='medusa' aTCP[i]='8081';;
			#117) :;; # ToDo: Implement automated install via /boot/unattended_pivpn.conf
			118) aSERVICES[i]='mopidy' aTCP[i]='6680';;
			121) aSERVICES[i]='roonbridge' aUDP[i]='9003';;
			122) aSERVICES[i]='node-red' aTCP[i]='1880';;
			123) aSERVICES[i]='mosquitto' aTCP[i]='1883';;
			124) aSERVICES[i]='networkaudiod';; # aUDP[i]='????';;
			125) aSERVICES[i]='synapse' aTCP[i]='8008';;
			126) aSERVICES[i]='adguardhome' aUDP[i]='53' aTCP[i]='8083'; [[ ${aSERVICES[182]} ]] && aUDP[i]+=' 5353';; # Unbound uses port 5353 if AdGuard Home is installed
			128) aSERVICES[i]='mpd' aTCP[i]='6600';;
			131) aSERVICES[i]='blynkserver' aTCP[i]='9443';;
			132) aSERVICES[i]='aria2' aTCP[i]='6800';; # aTCP[i]+=' 6881-6999';; # Listens on random port
			133) aSERVICES[i]='yacy' aTCP[i]='8090';;
			135) aSERVICES[i]='icecast2 darkice' aTCP[i]='8000';;
			136) aSERVICES[i]='motioneye' aTCP[i]='8765';;
			137) aSERVICES[i]='mjpg-streamer' aTCP[i]='8082';;
			138) aSERVICES[i]='virtualhere' aTCP[i]='7575';;
			139) aSERVICES[i]='sabnzbd' aTCP[i]='8080';; # ToDo: Solve conflict with Airsonic
			140) aSERVICES[i]='domoticz' aTCP[i]='8124 8424';;
			141) aSERVICES[i]='spotify-connect-web' aTCP[i]='4000';;
			142) aSERVICES[i]='snapd';;
			143) aSERVICES[i]='koel' aTCP[i]='8003';;
			144) aSERVICES[i]='sonarr' aTCP[i]='8989';;
			145) aSERVICES[i]='radarr' aTCP[i]='7878';;
			146) aSERVICES[i]='tautulli' aTCP[i]='8181';;
			147) aSERVICES[i]='jackett' aTCP[i]='9117';;
			148) aSERVICES[i]='mympd' aTCP[i]='1333';;
			149) aSERVICES[i]='nzbget' aTCP[i]='6789';;
			151) aSERVICES[i]='prowlarr' aTCP[i]='9696';;
			152) aSERVICES[i]='avahi-daemon' aUDP[i]='5353';;
			153) aSERVICES[i]='octoprint' aTCP[i]='5001';;
			154) aSERVICES[i]='roonserver';; # Listens on a variety of different port ranges
			155) aSERVICES[i]='htpc-manager' aTCP[i]='8085';;
			157) aSERVICES[i]='home-assistant' aTCP[i]='8123';;
			158) aSERVICES[i]='minio' aTCP[i]='9000';; # ToDo: Solve port conflict with LMS
			161) aSERVICES[i]='bdd' aTCP[i]='80 443';;
			162) aSERVICES[i]='docker';;
			163) aSERVICES[i]='gmediarender';; # DLNA => UPnP high range of ports
			164) aSERVICES[i]='nukkit' aUDP[i]='19132';;
			165) aSERVICES[i]='gitea' aTCP[i]='3000';;
			166) aSERVICES[i]='pi-spc';;
			167) aSERVICES[i]='raspotify';;
			169) aSERVICES[i]='voice-recognizer';;
			#171) aSERVICES[i]='frps frpc' aTCP[i]='7000 7400 7500';; # Cannot be installed non-interactively, ports on chosen type
			#172) aSERVICES[i]='wg-quick@wg0' aUDP[i]='51820';; # cannot be installed non-interactively
			176) aSERVICES[i]='mycroft';;
			177) aSERVICES[i]='firefox-sync' aTCP[i]='5002';;
			178) aSERVICES[i]='jellyfin' aTCP[i]='8097';;
			179) aSERVICES[i]='komga' aTCP[i]='2037';;
			180) aSERVICES[i]='bazarr' aTCP[i]='6767';;
			181) aSERVICES[i]='papermc' aTCP[i]='25565';;
			182) aSERVICES[i]='unbound' aUDP[i]='53'; [[ ${aSERVICES[126]} ]] && aUDP[i]+=' 5353';; # Uses port 5353 if Pi-hole or AdGuard Home is installed, but those do listen on port 53 instead
			183) aSERVICES[i]='vaultwarden' aTCP[i]='8001';;
			#184) aSERVICES[i]='tor' aTCP[i]='443 9051';; # Cannot be installed non-interactively, ports can be chosen and depend on chosen relay type
			185) aSERVICES[i]='docker' aTCP[i]='9002';;
			186) aSERVICES[i]='ipfs' aTCP[i]='5003 8087';;
			187) aSERVICES[i]='cups' aTCP[i]='631';;
			191) aSERVICES[i]='snapserver' aTCP[i]='1780';;
			#192) aSERVICES[i]='snapclient';; # cannot be installed non-interactively
			194) aSERVICES[i]='postgresql';;
			196) aCOMMANDS[i]='java -version';;
			198) aSERVICES[i]='filebrowser' aTCP[i]='8084';;
			199) aSERVICES[i]='spotifyd';; # aTCP[i]='4079';; ???
			200) aSERVICES[i]='dietpi-dashboard' aTCP[i]='5252';;
			201) aSERVICES[i]='zerotier-one' aTCP[i]='9993';;
			202) aCOMMANDS[i]='rclone -h';;
			203) aSERVICES[i]='readarr' aTCP[i]='8787';;
			204) aSERVICES[i]='navidrome' aTCP[i]='4533';;
			206) aSERVICES[i]='openhab' aTCP[i]='8444';;
			209) aCOMMANDS[i]='restic version';;
			*) :;;
		esac
	done
}
for i in $SOFTWARE
do
	case $i in
		205) Process_Software webserver;;
		27|56|63|64|107|132) Process_Software 89 webserver;; # 93 (Pi-hole) cannot be installed non-interactively
		38|40|48|54|55|57|59|90|160) Process_Software 88 89 webserver;;
		47|114|168) Process_Software 88 89 91 webserver;;
		8|33) Process_Software 196;;
		32|148|119) Process_Software 128;;
		129) Process_Software 88 89 128 webserver;;
		49|165) Process_Software 88;;
		#61) Process_Software 60;; # Cannot be installed in CI
		125) Process_Software 194;;
		*) :;;
	esac
	Process_Software "$i"
done

##########################################
# Dependencies
##########################################
apackages=('7zip' 'parted' 'fdisk' 'systemd-container')
(( $G_HW_ARCH == $arch || ( $G_HW_ARCH < 10 && $G_HW_ARCH > $arch ) )) || apackages+=('qemu-user-static' 'binfmt-support')
G_AG_CHECK_INSTALL_PREREQ "${apackages[@]}"

##########################################
# Prepare container
##########################################
# Download
G_EXEC curl -sSfO "https://dietpi.com/downloads/images/$image.7z"
G_EXEC 7zz e "$image.7z" "$image.img"
G_EXEC rm "$image.7z"
G_EXEC truncate -s 3G "$image.img"

# Loop device
FP_LOOP=$(losetup -f)
G_EXEC losetup "$FP_LOOP" "$image.img"
G_EXEC partprobe "$FP_LOOP"
G_EXEC partx -u "$FP_LOOP"
G_EXEC_OUTPUT=1 G_EXEC e2fsck -fp "${FP_LOOP}p1"
G_EXEC_OUTPUT=1 G_EXEC eval "sfdisk -fN1 '$FP_LOOP' <<< ',+'"
G_EXEC partprobe "$FP_LOOP"
G_EXEC partx -u "$FP_LOOP"
G_EXEC_OUTPUT=1 G_EXEC resize2fs "${FP_LOOP}p1"
G_EXEC_OUTPUT=1 G_EXEC e2fsck -fp "${FP_LOOP}p1"
G_EXEC mkdir rootfs
G_EXEC mount "${FP_LOOP}p1" rootfs

# Force ARMv6 arch on Raspbian
(( $arch == 1 )) && G_EXEC sed -i '/# Start DietPi-Software/iG_EXEC sed -i -e '\''/^G_HW_ARCH=/cG_HW_ARCH=1'\'' -e '\''/^G_HW_ARCH_NAME=/cG_HW_ARCH_NAME=armv6l'\'' /boot/dietpi/.hw_model' rootfs/boot/dietpi/dietpi-login

# Force RPi on ARM systems if requested
if [[ $RPI == 'true' ]] && (( $arch < 10 ))
then
	case $arch in
		1) model=1;;
		2) model=2;;
		3) model=4;;
		*) G_DIETPI-NOTIFY 1 "Invalid architecture $ARCH beginning with \"a\" but not being one of the known/accepted ARM architectures. This should never happen!"; exit 1;;
	esac
	G_EXEC sed -i "/# Start DietPi-Software/iG_EXEC sed -i -e '/^G_HW_MODEL=/cG_HW_MODEL=$model' -e '/^G_HW_MODEL_NAME=/cG_HW_MODEL_NAME=\"RPi $model ($ARCH)\"' /boot/dietpi/.hw_model; > /boot/config.txt; > /boot/cmdline.txt" rootfs/boot/dietpi/dietpi-login
	G_EXEC curl -sSf 'https://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-archive-keyring/raspberrypi-archive-keyring_2021.1.1+rpt1_all.deb' -o keyring.deb
	G_EXEC dpkg --root=rootfs -i keyring.deb
	G_EXEC rm keyring.deb
fi

# Workaround invalid TERM on login
# shellcheck disable=SC2016
G_EXEC eval 'echo '\''infocmp "$TERM" > /dev/null 2>&1 || { echo "[ INFO ] Unsupported TERM=\"$TERM\", switching to TERM=\"dumb\""; export TERM=dumb; }'\'' > rootfs/etc/bashrc.d/00-dietpi-ci.sh'

# Enable automated setup
G_CONFIG_INJECT 'AUTO_SETUP_AUTOMATED=' 'AUTO_SETUP_AUTOMATED=1' rootfs/boot/dietpi.txt

# Workaround for failing IPv4 network connectivity check as GitHub Actions runners do not receive external ICMP echo replies.
G_CONFIG_INJECT 'CONFIG_CHECK_CONNECTION_IP=' 'CONFIG_CHECK_CONNECTION_IP=127.0.0.1' rootfs/boot/dietpi.txt

# Apply Git branch
G_CONFIG_INJECT 'DEV_GITBRANCH=' "DEV_GITBRANCH=$G_GITBRANCH" rootfs/boot/dietpi.txt
G_CONFIG_INJECT 'DEV_GITOWNER=' "DEV_GITOWNER=$G_GITOWNER" rootfs/boot/dietpi.txt

# Avoid DietPi-Survey uploads to not mess with the statistics
G_EXEC rm rootfs/root/.ssh/known_hosts

# Apply software IDs to install
for i in $SOFTWARE; do G_CONFIG_INJECT "AUTO_SETUP_INSTALL_SOFTWARE_ID=$i" "AUTO_SETUP_INSTALL_SOFTWARE_ID=$i" rootfs/boot/dietpi.txt; done

# Workaround for "Could not execute systemctl:  at /usr/bin/deb-systemd-invoke line 145." during Apache2 DEB postinst in 32-bit ARM Bookworm container: https://lists.ubuntu.com/archives/foundations-bugs/2022-January/467253.html
G_CONFIG_INJECT 'AUTO_SETUP_WEB_SERVER_INDEX=' 'AUTO_SETUP_WEB_SERVER_INDEX=-2' rootfs/boot/dietpi.txt

# Workaround for failing Redis as of PrivateUsers=true leading to "Failed to set up user namespacing"
G_EXEC mkdir rootfs/etc/systemd/system/redis-server.service.d
G_EXEC eval 'echo -e '\''[Service]\nPrivateUsers=0'\'' > rootfs/etc/systemd/system/redis-server.service.d/dietpi-container.conf'

# Workarounds for failing MariaDB install on Buster within GitHub Actions runner (both cannot be replicated on my test systems with and without QEMU):
# - mysqld does not have write access if our symlink is in place, even that directory permissions are correct.
# - Type=notify leads to a service start timeout while mysqld has actually fully started.
if [[ $DISTRO == 'buster' ]]
then
	G_EXEC sed -i '/# Start DietPi-Software/a\sed -i -e '\''s|rm -Rf /var/lib/mysql|rm -Rf /mnd/dietpi_userdata/mysql|'\'' -e '\''s|ln -s /mnt/dietpi_userdata/mysql /var/lib/mysql|ln -s /var/lib/mysql /mnt/dietpi_userdata/mysql|'\'' /boot/dietpi/dietpi-software' rootfs/boot/dietpi/dietpi-login
	G_EXEC mkdir rootfs/etc/systemd/system/mariadb.service.d
	G_EXEC eval 'echo -e '\''[Service]\nType=exec'\'' > rootfs/etc/systemd/system/mariadb.service.d/dietpi-container.conf'
fi

# Workaround for failing 32-bit ARM Rust builds on ext4 in QEMU emulated container on 64-bit host: https://github.com/rust-lang/cargo/issues/9545
(( $arch < 3 && $G_HW_ARCH > 9 )) && G_EXEC eval 'echo -e '\''tmpfs /mnt/dietpi_userdata tmpfs size=3G,noatime,lazytime\ntmpfs /root tmpfs size=3G,noatime,lazytime'\'' >> rootfs/etc/fstab'

# Workaround for Node.js on ARMv6
(( $arch == 1 )) && G_EXEC sed -i '/# Start DietPi-Software/a\sed -i '\''/G_EXEC chmod +x node-install.sh/a\\sed -i "/^ARCH=/c\\ARCH=armv6l" node-install.sh'\'' /boot/dietpi/dietpi-software' rootfs/boot/dietpi/dietpi-login

# Check for service status, ports and commands
# shellcheck disable=SC2016
# - Start all services
G_EXEC sed -i '/# Start DietPi-Software/a\sed -i '\''/# Custom 1st run script/a\\for i in "${aSTART_SERVICES[@]}"; do G_EXEC_NOHALT=1 G_EXEC systemctl start "$i"; done'\'' /boot/dietpi/dietpi-software' rootfs/boot/dietpi/dietpi-login
delay=10
for i in "${aDELAY[@]}"; do (( $i > $delay )) && delay=$i; done
G_EXEC eval "echo -e '#!/bin/dash\nexit_code=0; /boot/dietpi/dietpi-services start || exit_code=1; sleep $delay' > rootfs/boot/Automation_Custom_Script.sh"
# - Loop through software IDs to test
printf '%s\n' "${!aSERVICES[@]}" "${!aTCP[@]}" "${!aUDP[@]}" "${!aCOMMANDS[@]}" | sort -u | while read -r i
do
	# Check whether ID really got installed, to skip software unsupported on hardware or distro
	cat << _EOF_ >> rootfs/boot/Automation_Custom_Script.sh
if grep -q '^aSOFTWARE_INSTALL_STATE\[$i\]=2$' /boot/dietpi/.installed
then
_EOF_
	# Check service status
	[[ ${aSERVICES[i]} ]] && for j in ${aSERVICES[i]}; do cat << _EOF_ >> rootfs/boot/Automation_Custom_Script.sh
echo -n '\e[33m[ INFO ] Checking $j service status:\e[0m '
systemctl is-active '$j' || { journalctl -u '$j'; exit_code=1; }
_EOF_
	done
	# Check TCP ports
	[[ ${aTCP[i]} ]] && for j in ${aTCP[i]}; do cat << _EOF_ >> rootfs/boot/Automation_Custom_Script.sh
echo '\e[33m[ INFO ] Checking TCP port $j status:\e[0m'
ss -tlpn | grep ':${j}[[:blank:]]' || exit_code=1
_EOF_
	done
	# Check UDP ports
	[[ ${aUDP[i]} ]] && for j in ${aUDP[i]}; do cat << _EOF_ >> rootfs/boot/Automation_Custom_Script.sh
echo '\e[33m[ INFO ] Checking UDP port $j status:\e[0m'
ss -ulpn | grep ':${j}[[:blank:]]' || exit_code=1
_EOF_
	done
	# Check commands
	[[ ${aCOMMANDS[i]} ]] && cat << _EOF_ >> rootfs/boot/Automation_Custom_Script.sh
echo '\e[33m[ INFO ] Testing command ${aCOMMANDS[i]}:\e[0m'
${aCOMMANDS[i]} || exit_code=1
_EOF_
	G_EXEC eval 'echo fi >> rootfs/boot/Automation_Custom_Script.sh'
done

# Success flag and shutdown
# shellcheck disable=SC2016
G_EXEC eval 'echo '\''[ $exit_code = 0 ] && > /success || { journalctl -n 25; ss -tlpn; df -h; free -h; poweroff; }; poweroff'\'' >> rootfs/boot/Automation_Custom_Script.sh'

# Shutdown as well on failure
G_EXEC sed -i 's|Prompt_on_Failure$|{ journalctl -n 25; ss -tlpn; df -h; free -h; poweroff; }|' rootfs/boot/dietpi/dietpi-login

##########################################
# Boot container
##########################################
systemd-nspawn -bD rootfs
[[ -f 'rootfs/success' ]] || { journalctl -n 25; df -h; free -h; exit 1; }
}
