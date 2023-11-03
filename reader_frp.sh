#!/bin/bash
#
set -x

WORK_DIR=`cd $(dirname $0); pwd;`

FRP_MODE=
SERVER_PORT=
SERVER_ADDR=
SERVER_DOMAIN=

S_C_PORT=51786
S_C_SSH_PORT=51788
TOKEN="da3538607a7c4344b07dd5940de87c0e"

INI_SERVER="${WORK_DIR}/c_server.toml"
INI_CLIENT="${WORK_DIR}/c_client.toml"


source ${WORK_DIR}/proxy.sh
setproxy

FRP_PID=
FRP_STATIC_VERSION="0.52.3"

# locale-gen en_US.UTF-8
# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8
#
trap 'kill $FRP_PID' EXIT SIGKILL

case $(arch) in
	x86_64)
		JAVA_TAR="jdk-20_linux-x64_bin.tar.gz"
		JQ_NAME=jq-linux-amd64
		FRP_ARCH="linux_amd64"
		;;
	arm64|aarch64)
		JAVA_TAR="jdk-20_linux-aarch64_bin.tar.gz"
		JQ_NAME=jq-linux-arm64
		FRP_ARCH="linux_arm64"
		;;
	*)
		exit -1
		;;
esac

install_jq() {
	jq -h &> /dev/null
	if [[ $? == 0 ]] ; then
		return
	fi

	if [[ ! -e $JQ_NAME ]]; then
		wget https://github.com/jqlang/jq/releases/download/jq-1.7/$JQ_NAME &> /dev/null
		[[ $? != 0 ]] && (rm -f $JQ_NAME; exit 222)
		chmod +x ./$JQ_NAME
		[[ -e jq ]] && rm -f jq
		ln -s $JQ_NAME jq
	fi

	export PATH=.:${WORK_DIR}:$PATH
}

adapt_frpc_ini() {
	local file_ini=$1

	if [[ -e $file_ini ]]; then
		sed -i "/serverAddr/c\serverAddr = \"${SERVER_ADDR}\""  $file_ini
		sed -i "/serverPort /c\serverPort = ${S_C_PORT}" $file_ini

		sed -i "/auth.token/c\auth.token= \"${TOKEN}\"" $file_ini

		sed -i "/remotePort/c\remotePort = ${S_C_SSH_PORT}" $file_ini
		sed -i "0,/customDomains.*$/s//customDomains = [\"${SERVER_DOMAIN}\"]/" $file_ini
	else
		echo "serverAddr = \"${SERVER_ADDR}\""  	> $file_ini
		echo "serverPort = ${S_C_PORT}" 	>> $file_ini
		echo 'loginFailExit = true' 		>> $file_ini
		echo 'auth.method = "token"'		>> $file_ini
		echo "auth.token = \"${TOKEN}\"" 	>> $file_ini
		echo ""			 		>> $file_ini

		echo '[[proxies]]'  			>> $file_ini
		echo 'name = "ssh"'		>> $file_ini
		echo 'type = "tcp"'		>> $file_ini
		echo 'localIP = "127.0.0.1"'	>> $file_ini
		echo 'localPort = 22'		>> $file_ini
		echo "remotePort = ${S_C_SSH_PORT}" >> $file_ini
		echo ""			 		>> $file_ini

		echo '[[proxies]]'  			>> $file_ini
		echo 'name = "http_reader"'		>> $file_ini
		echo 'type = "http"'			>> $file_ini
		echo 'localIP = "127.0.0.1"'		>> $file_ini
		echo 'localPort = 8080'		>> $file_ini
		echo "customDomains = [\"${SERVER_DOMAIN}\"]"	>> $file_ini
	fi
}

adapt_frps_ini() {
	local file_ini=$1

	# sed -i "/bind_port/c\bind_port = ${S_C_PORT}" $file_ini
	# sed -i '/vhost_http_port/c\vhost_http_port = ${SERVER_PORT}' $file_ini
	# sed -i '/token/d' $file_ini
	echo "bindPort = ${S_C_PORT}"  		> $file_ini
	[[ -n "$FRP_HTTPS" ]] || echo "vhostHTTPPort = ${SERVER_PORT}" 	>> $file_ini
	[[ -n "$FRP_HTTPS" ]] && echo "vhostHTTPSPort = ${SERVER_PORT}" >> $file_ini
	echo 'auth.method = "token"'		>> $file_ini
	echo "auth.token = \"${TOKEN}\"" 	>> $file_ini
}

frp_get_latest() {

	install_jq

	local file_name=$(basename frp*${FRP_ARCH})
	# declare -r file_name
	local tag2=$(wget -qO- -t1 -T2 "https://api.github.com/repos/fatedier/frp/releases/latest" | grep "tag_name" | head -n 1 | awk -F "v" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
	([[ $? != 0 ]] || [[ -z "$tag2" ]]) && echo "WARN: tag2 get failed!" && return -1

	[[ "${file_name}" =~ "${tag2}" ]] && return 0

	local tag1=$(wget -qO- -t1 -T2 "https://api.github.com/repos/fatedier/frp/releases/latest" | jq -r '.tag_name')
	local new_tar="frp_${tag2}_${FRP_ARCH}.tar.gz"
	wget https://github.com/fatedier/frp/releases/download/${tag1}/$new_tar &> /dev/null
	[[ $? != 0 ]] && (rm -f $new_tar; echo "WARN: wget failed." ) && return -1

	[[ "${file_name}" != "frp*${FRP_ARCH}" ]] &&  rm -rf ${file_name}*

	tar -xf $new_tar || (rm -rf frp*${FRP_ARCH}; echo "WARN: frp get latest failed.") && return -1
}

frp_get_static() {
	local file_name=$(basename frp*${FRP_ARCH})
	[[ "${file_name}" =~ "${FRP_STATIC_VERSION}" ]] && return 0

	[[ -e $file_name ]] && rm -rf ${file_name}*

	local static_ver="frp_${FRP_STATIC_VERSION}_${FRP_ARCH}.tar.gz"
	wget https://github.com/fatedier/frp/releases/download/v${FRP_STATIC_VERSION}/$static_ver
	[[ $? != 0 ]] && (rm -f $static_ver; echo "WARN: wget failed.") && return -1
	tar -xf $static_ver || (rm -rf frp*${FRP_ARCH}; echo "WARN: tar extract files failed.") && return -1
}

frp_download() {
	[[ $FRP_UPDATE_LATEST == 1 ]] && frp_get_latest
	[[ -e $(basename frp*${FRP_ARCH}) ]] || frp_get_static
	if [[ ! -e $(basename frp*${FRP_ARCH}) ]]; then
		echo "ERR: frp get failed."
		exit 255
	fi
}

run_frp() {

	frp_download

	local file_name=$(basename frp*${FRP_ARCH})
	local frp_dir="${WORK_DIR}/${file_name}"
	[[ -d $frp_dir ]] || exit 255

	local file_ini=
	local frp_app=
	if [[ $FRP_MODE = "server" ]]; then
		file_ini=$INI_SERVER
		adapt_frps_ini "$file_ini"
		frp_app="${frp_dir}/frps"
		chmod +x $frp_app
	else
		file_ini=$INI_CLIENT
		adapt_frpc_ini "$file_ini"
		frp_app="${frp_dir}/frpc"
		chmod +x $frp_app
	fi

	unsetproxy
	$frp_app -c $file_ini &
	FRP_PID=$!

	wait
	exit 255
}

get_server_ip() {

	[[ -z "$SERVER_DOMAIN" ]] && [[ -z "$SERVER_ADDR" ]] && exit 255

	[[ -n "$SERVER_DOMAIN" ]] && [[ -z "$SERVER_ADDR" ]] && SERVER_ADDR=$SERVER_DOMAIN

	return

	if [[ -n "$SERVER_DOMAIN" ]] && [[ -z "$SERVER_ADDR" ]]; then
		# SERVER_ADDR=$(ping -c 2 $SERVER_DOMAIN | head -2 | tail -1 | awk '{print $5}' | sed 's/[(:)]//g')
		SERVER_ADDR=$(ping -c 1 $SERVER_DOMAIN | head -1 | awk '{print $3}' | sed 's/[(:)]//g')
	fi

	if [[ -z "$SERVER_ADDR" ]] || [[ "$SERVER_ADDR" =~ "$SERVER_DOMAIN" ]]; then
		exit 255
	fi
}

show_help() {
  echo "usage: $0 [OPTION]..."
  echo
  echo
  echo 'OPTION:'
  echo '    -s                        Server mode'
  echo '    -p                        Server host port, for server mode.'
  echo '    -c                        Client mode'
  echo '    -i                        Server ip address, for client mode.'
  echo '    -d                        Server domain, for client mode.'
  echo '    -u                        Frp app update latest.'
  exit 0

}

while getopts ":scup:i:d:" opt; do #不打印错误信息, -a -c需要参数 -b 不需要传参
	case $opt in
		s)
			FRP_MODE="server"
			;;
		c)
			FRP_MODE="client"
			;;
		u)
			FRP_UPDATE_LATEST=1
			;;
		p)
			SERVER_PORT="$OPTARG"
			;;
		i)
			SERVER_ADDR="$OPTARG"
			SERVER_ADDR=$(echo $SERVER_ADDR | sed "s/\"//g")
			;;
		d)
			SERVER_DOMAIN="$OPTARG"
			SERVER_DOMAIN=$(echo $SERVER_DOMAIN | sed "s/\"//g")
			;;
		:)
			echo "Option -$OPTARG requires an argument."
			exit 1
			;;
		?)
			show_help
			;;
	esac
done

if [[ -z $FRP_MODE ]]; then
	show_help
	exit -1
fi

[[ "$FRP_MODE" = "client" ]] && get_server_ip

cd $WORK_DIR

run_frp

# wait
