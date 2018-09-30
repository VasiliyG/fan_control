#!/bin/bash
source /home/vasivik/.rvm/environments/ruby-2.3.7
MAX_PROC_UPTIME=7200 # in seconds!
MAX_PROC_COUNT=2

pids="$(ps -ef | awk '/fan_control\/auto_fan_control_daemon.rb/ {print $2}')"
echo $pids

for pid in $pids
do
 
    hz=$(getconf CLK_TCK)
    uptime=$(awk '{print $1}' < /proc/uptime)
    starttime=$(awk '{print $22}' < /proc/$pid/stat)
    proc_uptime=$(( ${uptime%.*} - $starttime / $hz ))

    if [ $proc_uptime -gt $MAX_PROC_UPTIME ]
    then
	 kill -9 $pid
    fi
done

numproc="$(ps ux | grep auto_fan_control_daemon.rb | awk '$2 !~ /^[|\\]/ { ++n } END { print n }')"

if [ $numproc -lt $MAX_PROC_COUNT ]
then
 nohup ruby /home/vasivik/fan_control/auto_fan_control_daemon.rb --trace > /home/vasivik/fan_control/nohup_fan_control.log 2>&1 &
fi
