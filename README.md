# Simple fan speed control
I made a script in 10 minutes, to control the speed of the fan.

To start script use command:
 
~~~
nohup ruby fan_control.rb --trace > nohup_fan_control.log 2>&1 &
~~~

It made `fan_control.log` file in same directory, and will write work information there

For autostart script add this to you root cron:

~~~
*/5 *	* * *	root	/path_to_script/fan_control/start_fan_control_script.sh
~~~