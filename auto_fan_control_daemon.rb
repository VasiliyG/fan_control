require 'active_record'
require 'pp'
require 'serialport'
require 'yaml'

TEMP_SENSORS_PIN = 2
IN_TEMP = '000009e91fbe'.freeze
TEMP_ARRAY = (200..350).to_a.map { |i| i.to_f / 10 }
FAN_SPEED_ARRAY = (20..255).to_a
MAX_ERRORS_COUNT = 5
CORRECT_FAN_SPEED_ARRAY = (0..35).to_a
CORRECT_TEMP_ARRAY = (150..300).to_a.map { |i| i.to_f / 10 }
MAX_FAN_SPEED = FAN_SPEED_ARRAY.last
MAX_CORRECT_FAN_SPEED = CORRECT_FAN_SPEED_ARRAY.last

ActiveRecord::Base.establish_connection(
  adapter:  'postgresql',
  host:     'localhost',
  database: 'temperature',
  username: 'temperature',
  password: 'temperature'
)

ActiveRecord::Schema.define do
  unless table_exists?(:temperatures)
    create_table :temperatures do |t|
      t.datetime :measure_time
      t.float :out_temp
      t.float :in_temp
      t.integer :fan_speed, limit: 7
    end
  end

  unless index_exists?('temperatures', ['measure_time'], name: 'temperatures_measure_time')
    add_index 'temperatures', ['measure_time'], name: 'temperatures_measure_time'
  end

  unless index_exists?('temperatures', ['out_temp'], name: 'temperatures_out_temp')
    add_index 'temperatures', ['out_temp'], name: 'temperatures_out_temp'
  end

  unless index_exists?('temperatures', ['in_temp'], name: 'temperatures_in_temp')
    add_index 'temperatures', ['in_temp'], name: 'temperatures_in_temp'
  end

  unless index_exists?('temperatures', ['fan_speed'], name: 'temperatures_fan_speed')
    add_index 'temperatures', ['fan_speed'], name: 'temperatures_fan_speed'
  end

  unless column_exists?(:temperatures, :street_temp)
    add_column :temperatures, :street_temp, :float
  end

  unless index_exists?('temperatures', ['street_temp'], name: 'temperatures_street_temp')
    add_index 'temperatures', ['street_temp'], name: 'temperatures_street_temp'
  end
end

class Temperature < ActiveRecord::Base

end

class FanControl

  def initialize
    baud_rate = 115200
    parity = SerialPort::NONE
    @fan_control=nil
    @port=nil
  end

  def open(port)
    @fan_control = SerialPort.new(port, @baud_rate)
  end


  def shutdown(reason)

    return if @fan_control == nil
    return if reason == :int

    printf("\nshutting down serial (%s)\n", reason)

    @fan_control.flush()
    printf("done\n")
  end

  def read
    @fan_control.readline
  end

  def write(fan_speed)
    @fan_control.write(fan_speed)
  end

  def flush
    @fan_control.flush
  end
end

class AverageFanSpeed
  ARRAY_SIZE = 450
  GROW_SPEED = 150
  AVERAGE_GROW_SPEED = 60
  attr_reader :fan_speed_array

  def initialize(init_fan_speed = 0)
    @fan_speed_array = [init_fan_speed] * ARRAY_SIZE
  end

  def average_fan_speed(fan_speed)
    preview_average_fan_speed = calc_average_fan_speed
    write_fan_speed_to_array(fan_speed)

    if fan_speed.zero? || fan_speed > preview_average_fan_speed
      fan_speed
    else
      calc_average_fan_speed
    end
  end

  private

  def write_fan_speed_to_array(fan_speed)
    grow_speed = if fan_speed > @fan_speed_array.last && fan_speed > calc_average_fan_speed
                   GROW_SPEED
                 elsif fan_speed > calc_average_fan_speed
                   AVERAGE_GROW_SPEED
                 else
                   1
                 end
    grow_speed.times { push_fan_speed_to_array(fan_speed) }
  end

  def push_fan_speed_to_array(fan_speed)
    @fan_speed_array = @fan_speed_array.drop(1).push(fan_speed)
  end

  def calc_average_fan_speed
    @fan_speed_array.instance_eval { reduce(:+) / size.to_f }
  end
end

def fan_speed_array(temp)
  FAN_SPEED_ARRAY[(FAN_SPEED_ARRAY.size * (TEMP_ARRAY.index(temp.round(1)).to_f / TEMP_ARRAY.size)).round]
end

def correct_for_out_temp(out_temp)
  CORRECT_FAN_SPEED_ARRAY[(CORRECT_FAN_SPEED_ARRAY.size * (CORRECT_TEMP_ARRAY.index(out_temp.round(1)).to_f / CORRECT_TEMP_ARRAY.size)).round]
end

errors_count = 0
average_speed_class = AverageFanSpeed.new(0)

while true
  begin
    fan_control = Timeout::timeout(10) do
      ports = Dir.glob("/dev/ttyUSB*")
      if ports.size != 1
        printf("did not found right /dev/ttyUSB* serial")
        exit(1)
      end

      system("stty -F #{ports.first} 115200 -parenb -parodd cs8 -hupcl -cstopb cread clocal -crtscts -iuclc -ixany -imaxbel -iutf8 -opost -olcuc -ocrnl -onlcr -onocr -onlret -ofill -ofdel nl0 cr0 tab0 bs0 vt0 ff0 -isig -icanon -iexten -echo -echoe -echok -echonl -noflsh -xcase -tostop -echoprt -echoctl -echoke")
      fan_control = FanControl.new()
      fan_control.open(ports[0])
      fan_control
    end

    need_save_temp = true
    loop do
      begin
        Timeout::timeout(50) do

          data_from_serial = YAML.load(fan_control.read.gsub("\r", '').gsub("\n", ''))

          fan_speed_to_save = data_from_serial.first['fan_speed']
          in_temp = data_from_serial.first['t_1_temp']
          out_temp = data_from_serial.first['t_2_temp']

          if need_save_temp
            Temperature.create(measure_time: Time.at(Time.now.to_i + 25_200),
                               in_temp: in_temp,
                               out_temp: out_temp,
                               fan_speed: fan_speed_to_save)
            need_save_temp = false
          else
            need_save_temp = true
          end

          fan_speed = if in_temp > TEMP_ARRAY.first && in_temp <= TEMP_ARRAY.last
                        fan_speed_array(in_temp)
                      elsif in_temp > TEMP_ARRAY.last
                        MAX_FAN_SPEED
                      end

          if fan_speed.positive?
            correct_fan_speed = if out_temp > CORRECT_TEMP_ARRAY.first && out_temp <= CORRECT_TEMP_ARRAY.last
                                  correct_for_out_temp(out_temp)
                                elsif out_temp > CORRECT_TEMP_ARRAY.last
                                  MAX_CORRECT_FAN_SPEED
                                else
                                  0
                                end
            fan_speed += correct_fan_speed
            fan_speed = MAX_FAN_SPEED if fan_speed > MAX_FAN_SPEED
          end

          fan_control.write(average_speed_class.average_fan_speed(fan_speed).to_i)
          sleep 4
        end
      rescue
        break
      end
    end
  rescue Exception => error
    log_file = File.open('auto_fan_control.log', 'ab')
    log_file << "We have get error: #{error}; Sleep 5 second and try connect again"
    log_file << "\n"
    log_file.close
    errors_count += 1
    sleep 5
    if errors_count > MAX_ERRORS_COUNT
      break
    else
      next
    end
  end
end