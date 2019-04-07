#!/bin/sh

# Copyright (c) 2016, prpl Foundation
#
# Permission to use, copy, modify, and/or distribute this software for any purpose with or without
# fee is hereby granted, provided that the above copyright notice and this permission notice appear
# in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE
# INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
# FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
# ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# Author: Binyuan Sun <binyuan.sun@outlook.com>

SCRIPT=$0
LOCKFILE=/tmp/wifi_schedule2.lock
LOGFILE=/tmp/log/wifi_schedule2.log
LOGGING=0 #default is off
PACKAGE=wifi_schedule2
GLOBAL=${PACKAGE}.@global[0]
NETWORK=$2

_log()
{
    if [ ${LOGGING} -eq 1 ]; then
        local ts=$(date)
        echo "$ts $@" >> ${LOGFILE}
    fi
}

_exit()
{
    local rc=$1
    lock -u ${LOCKFILE}
    exit ${rc}
}

_cron_restart()
{
    /etc/init.d/cron restart > /dev/null
}

_add_cron_script()
{
    (crontab -l ; echo "$1") | sort | uniq | crontab -
    _cron_restart
}

_rm_cron_script()
{
    crontab -l | grep -v "$1" |  sort | uniq | crontab -
    _cron_restart
}

_get_uci_value_raw()
{
    local value
    value=$(uci get $1 2> /dev/null)
    local rc=$?
    echo ${value}
    return ${rc}
}

_get_uci_value()
{
    local value
    value=$(_get_uci_value_raw $1)
    local rc=$?
    if [ ${rc} -ne 0 ]; then
        _log "Could not determine UCI value $1"
        return 1
    fi
    echo ${value}
}

_format_dow_list()
{
    local dow=$1
    local flist=""
    local day
    for day in ${dow}
    do
        if [ ! -z ${flist} ]; then
            flist="${flist},"
        fi
        flist="${flist}${day:0:3}"
    done
    echo ${flist}
}


_enable_wifi_schedule()
{
    local entry=$1
    local starttime
    local stoptime
    starttime=$(_get_uci_value ${PACKAGE}.${entry}.starttime) || _exit 1
    stoptime=$(_get_uci_value ${PACKAGE}.${entry}.stoptime) || _exit 1

    local dow
    dow=$(_get_uci_value_raw ${PACKAGE}.${entry}.daysofweek) || _exit 1 
    
    local network
    network=$(_get_uci_value_raw ${PACKAGE}.${entry}.network) || _exit 1 

    local check_network
    check_network=$(_get_uci_value_raw "wireless.${network}") || _exit 1


    local fdow=$(_format_dow_list "$dow")
    local forcewifidown
    forcewifidown=$(_get_uci_value ${PACKAGE}.${entry}.forcewifidown)
    local stopmode="stop"

    local stop_cron_entry="$(echo ${stoptime} | awk -F':' '{print $2, $1}') * * ${fdow} ${SCRIPT} ${stopmode} ${network}" # ${entry}"
    _add_cron_script "${stop_cron_entry}"

    if [[ $starttime != $stoptime ]]                             
    then                                                         
        local start_cron_entry="$(echo ${starttime} | awk -F':' '{print $2, $1}') * * ${fdow} ${SCRIPT} start ${network}" # ${entry}"
        _add_cron_script "${start_cron_entry}"
    fi

    return 0
}

_create_cron_entries()
{
    local entries=$(uci show ${PACKAGE} 2> /dev/null | awk -F'.' '{print $2}' | grep -v '=' | grep -v '@global\[0\]' | uniq | sort)
    local _entry
    for entry in ${entries}
    do 
        local status
        status=$(_get_uci_value ${PACKAGE}.${entry}.enabled) || _exit 1
        if [ ${status} -eq 1 ]
        then
            _enable_wifi_schedule ${entry}
        fi
    done
}

check_cron_status()
{
    local global_enabled
    global_enabled=$(_get_uci_value ${GLOBAL}.enabled) || _exit 1
    _rm_cron_script "${SCRIPT}"
    if [ ${global_enabled} -eq 1 ]; then
        _create_cron_entries
    fi
}

disable_wifi()
{
    uci set "wireless.${NETWORK}.disabled=1"
    uci commit wireless
    /bin/ubus call network reload >/dev/null 2>/dev/null
}

soft_disable_wifi()
{

    _log "Disabling wifi."
    disable_wifi

}

enable_wifi()
{
    uci set "wireless.${NETWORK}.disabled=0"
    uci commit wireless
    /bin/ubus call network reload >/dev/null 2>/dev/null

}

usage()
{
    echo ""
    echo "$0 cron|start|stop|help"
    echo ""
    echo "    UCI Config File: /etc/config/${PACKAGE}"
    echo ""
    echo "    cron: Create cronjob entries."
    echo "    start: Start wifi."
    echo "    stop: Stop wifi gracefully, i.e. check if there are stations associated and if so keep retrying."
    echo "    help: This description."
    echo ""
}

###############################################################################
# MAIN
###############################################################################
LOGGING=$(_get_uci_value ${GLOBAL}.logging) || _exit 1
_log ${SCRIPT} $1 $2
lock ${LOCKFILE}

case "$1" in
    cron) check_cron_status ;;
    start) enable_wifi ;;
    stop) soft_disable_wifi ;;
    help|--help|-h|*) usage ;;
esac

_exit 0
