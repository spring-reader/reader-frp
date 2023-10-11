#!/bin/bash

WORK_DIR=`cd $(dirname $0); pwd;`

TIMEOUT_DAYS=$((1 * 24 * 60 * 60))  # 1days
MAIN_SELF=$$
CLIENT_CONF="${WORK_DIR}/c_client.conf"

trap 'kill $RESTART_SELF_PID $READER_PID' EXIT SIGKILL


restart_self()
{
	trap 'kill $SLEEP_PID' EXIT SIGKILL
	sleep $TIMEOUT_DAYS &
	SLEEP_PID="$! "

	wait
	kill $MAIN_SELF
}

# pushd $WORK_DIR
# git checkout .
# git reset --hard HEAD^
# git config pull.rebase false
# git pull
# popd

restart_self &
RESTART_SELF_PID="$! "

if [[ -e $CLIENT_CONF ]]; then
	bash ${WORK_DIR}/reader_frp.sh $(cat $CLIENT_CONF)  &
	READER_PID=$!
else
	bash ${WORK_DIR}/reader_frp.sh -s -p "$@"  &
	READER_PID=$!
fi

wait $READER_PID

