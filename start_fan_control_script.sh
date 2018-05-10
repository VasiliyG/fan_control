#!/usr/bin/env bash
MAX_PROC_COUNT=2

numproc="$(ps ux | grep fan_control.rb | awk '$2 !~ /^[|\\]/ { ++n } END { print n }')"
echo $numproc
if [ $numproc -lt $MAX_PROC_COUNT ]
then
 nohup ruby /home/vasivik/fan_control/fan_control.rb --trace > /home/vasivik/fan_control/nohup_fan_control.log 2>&1 &
fi
