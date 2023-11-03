#!/bin/bash

#proxy_ip=
#proxy_port=
CONF_READER_PROXY="${WORK_DIR}/c_proxy.conf"

function test_proxy() {
	timeout 15 curl -I -x http://127.0.0.1:1081 https://google.com &>/dev/null
	[[ $? = 0 ]] || return -1
}

function setproxy() {
	[[ -e $CONF_READER_PROXY ]] || return

	test_proxy
	[[ $? = 0 ]] || return

	source $CONF_READER_PROXY
	export http_proxy="http://${proxy_ip}:${proxy_port}"
	export https_proxy="http://${proxy_ip}:${proxy_port}"
}

function unsetproxy() {
	[[ -e $CONF_READER_PROXY ]] || return

	unset http_proxy
	unset https_proxy
}

