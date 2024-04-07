#!/bin/bash

WORK_DIR=`cd $(dirname $0); pwd;`

TIMEOUT_DAYS=$((1 * 24 * 60 * 60))  # 1days
MAIN_SELF=$$
CLIENT_CONF="${WORK_DIR}/client.conf"

trap 'kill $RESTART_SELF_PID $READER_PID' EXIT SIGKILL

reclaim_sleep_pid()
{
	local pid
	ps -aux | grep -w $TIMEOUT_DAYS | grep -v grep | awk '{print $2}' | while read line; do
		kill $line
	done
}

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

#reclaim_sleep_pid
#restart_self &
#RESTART_SELF_PID="$! "
#
if [[ -e $CLIENT_CONF ]]; then
	bash ${WORK_DIR}/reader_frp.sh $(cat $CLIENT_CONF)  &
	READER_PID=$!
else
	bash ${WORK_DIR}/reader_frp.sh -s -p "$@"  &
	READER_PID=$!
fi

wait $READER_PID

