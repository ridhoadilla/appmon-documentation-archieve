OS_TYPE=`uname`
DT_SHUTDOWN_WAIT=60

. "${DT_HOME}/init.d/functions.sh"

DT_BINARY_WITH_PATH="${DT_HOME}"/agent/lib64/${DT_BINARY}

if [ "$(get_kernel_bitness)" != "64" ] ; then
  DT_BINARY_WITH_PATH="${DT_HOME}"/agent/lib/${DT_BINARY}
fi

if [ ! -x "${DT_BINARY_WITH_PATH}" ]; then
  DT_BINARY_WITH_PATH="${DT_HOME}"/agent/lib/${DT_BINARY}
fi

if [ ! -x "${DT_BINARY_WITH_PATH}" ]; then
  echo "File not found or not executable: ${DT_BINARY_WITH_PATH}"
  exit 1
fi

resetpids() {
    PROCESSPID=`ps -eo pid,args | grep -- ${DT_BINARY} | grep -v 'outerlauncher' | grep -v grep | grep -- ${DT_HOME} | grep -- "${DT_OPTARGS}" | awk '{{print $1}}'`
}

resetpids

startagent() {
	if [ -z "${PROCESSPID}" ]; then
		if [ -z "${DT_RUNASUSER}" ]; then
			nohup "${DT_BINARY_WITH_PATH}" ${DT_OPTARGS} >/dev/null 2>&1 &
		else
			if [ "$OS_TYPE" = 'SunOS' ]; then
				su "${DT_RUNASUSER}" -c "nohup ${DT_BINARY_WITH_PATH} ${DT_OPTARGS} >/dev/null 2>&1 &"
			else
				su -c "nohup ${DT_BINARY_WITH_PATH} ${DT_OPTARGS} >/dev/null 2>&1 &" "${DT_RUNASUSER}"
			fi
		fi
	else
		echo "Process already started:"
		ps -ef | grep ${DT_BINARY} | grep ${PROCESSPID}
	fi
}

stopagent() {
    if [ -n "${PROCESSPID}" ]; then
		echo "Terminating Dynatrace $DT_PRODUCT process ${PROCESSPID}"
		kill -15 ${PROCESSPID}
		COUNT=0;
			while [ `ps -A -o pid | grep -c ${PROCESSPID}` -gt 0 ] && [ "${COUNT}" -lt "${DT_SHUTDOWN_WAIT}" ] # `ps --pid ${PROCESSPID} | grep -c ${PROCESSPID}` -ne 0]
			do
				echo "Waiting for Dynatrace $DT_PRODUCT (${PROCESSPID}) to finish shutdown";
				sleep 1
				COUNT=`expr ${COUNT} + 1`
			done

			if [ "${COUNT}" -gt "${DT_SHUTDOWN_WAIT}" ]; then
				echo "Killing Dynatrace ${DT_PRODUCT} (${PROCESSPID}) because the shutdown lasted longer than ${DT_SHUTDOWN_WAIT} seconds"
				kill -9 ${PROCESSPID}
			fi
    fi
}

agentstatus() {
    if [ -n "${PROCESSPID}" ]; then
      echo "Dynatrace $DT_PRODUCT daemon is running:"
      ps -ef | grep ${DT_BINARY} | grep ${PROCESSPID}
      return 0
    else
      echo "Dynatrace ${DT_PRODUCT} daemon not running."
      return 3
    fi
}

case "$1" in
'start')
    startagent
    ;;
'stop')
    stopagent
    ;;
'restart')
	stopagent
	resetpids
	startagent
	;;
'force-reload')
	stopagent
	resetpids
	startagent
	;;
'status')
	agentstatus
    exit $?
    ;;
*)
    echo "usage: $0 {start|stop|restart|force-reload|status}"
    ;;
esac
