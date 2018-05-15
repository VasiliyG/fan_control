#!/usr/bin/env bash
source /home/vasivik/.rvm/environments/ruby-2.3.7
MAX_PROC_COUNT=2

numproc="$(ps ux | grep fan_control_daemon.rb | awk '$2 !~ /^[|\\]/ { ++n } END { print n }')"
echo $numproc
if [ $numproc -lt $MAX_PROC_COUNT ]
then
 nohup ruby /home/vasivik/fan_control/fan_control_daemon.rb --trace > /home/vasivik/fan_control/nohup_fan_control.log 2>&1 &
fi
