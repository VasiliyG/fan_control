require 'dino'
require 'active_record'

TEMP_SENSORS_PIN = 2
IN_TEMP = '000009e91fbe'.freeze
TEMP_ARRAY = (240..410).to_a.map { |i| i.to_f / 10 }
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
end

class Temperature < ActiveRecord::Base

end

class AverageFanSpeed
  ARRAY_SIZE = 300
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
    grow_speed = if fan_speed > @fan_speed_array.last
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
    board, bus, led, ds18b20s = Timeout::timeout(50) do
      board = Dino::Board.new(Dino::TxRx::Serial.new)
      bus = Dino::Components::OneWire::Bus.new(pin: TEMP_SENSORS_PIN, board: board)
      led = Dino::Components::RGBLed.new(pins: {red: 11, green: 10, blue: 9}, board: board)
      log_file = File.open('fan_control.log', 'ab')
      if bus.parasite_power
        log_file << "Parasite power detected...\n"
      end

      if bus.device_present
        log_file << "Devices present on bus...\n"
      else
        log_file << "No devices present on bus... Quitting...\n"
        return
      end

      bus.search
      count = bus.found_devices.count
      log_file << "Found #{count} device#{'s' if count > 1} on the bus:\n"
      log_file << bus.found_devices.inspect
      log_file << "\n"

      ds18b20s = []
      bus.found_devices.each do |d|
        if d[:class] == Dino::Components::OneWire::DS18B20
          ds18b20s << d[:class].new(bus: bus, address: d[:address])
        end
      end
      log_file.close
      [board, bus, led, ds18b20s]
    end
    # Read the temp from each sensor in a simple loop.
    loop do
      begin
        Timeout::timeout(50) do
          in_temp = 0
          out_temp = 0
          fan_speed = 0
          ds18b20s.reverse.map do |sensor|
            read_data = sensor.read
            if IN_TEMP == sensor.serial_number
              if read_data[:celsius] > TEMP_ARRAY.first && read_data[:celsius] <= TEMP_ARRAY.last
                fan_speed = fan_speed_array(read_data[:celsius])
              end
              if read_data[:celsius] > TEMP_ARRAY.last
                fan_speed = MAX_FAN_SPEED
              end
              in_temp = read_data[:celsius]
            else
              if fan_speed.positive?
                correct_fan_speed = if read_data[:celsius] > CORRECT_TEMP_ARRAY.first && read_data[:celsius] <= CORRECT_TEMP_ARRAY.last
                                      correct_for_out_temp(read_data[:celsius])
                                    elsif read_data[:celsius] > CORRECT_TEMP_ARRAY.last
                                      MAX_CORRECT_FAN_SPEED
                                    else
                                      0
                                    end
                fan_speed += correct_fan_speed
                fan_speed = MAX_FAN_SPEED if fan_speed > MAX_FAN_SPEED
              end
              out_temp = read_data[:celsius]
            end
          end
          led.color = [average_speed_class.average_fan_speed(fan_speed).to_i, 0, 0]
          Temperature.create(measure_time: Time.at(Time.now.to_i + 25_200), in_temp: in_temp, out_temp: out_temp, fan_speed: fan_speed)
          sleep 15
        end
      rescue
        break
      end
    end
  rescue Exception => error
    log_file = File.open('fan_control.log', 'ab')
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