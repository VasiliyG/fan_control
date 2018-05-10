require 'dino'
require 'active_record'

TEMP_SENSORS_PIN = 2
IN_TEMP = '000009e91fbe'.freeze
TEMP_ARRAY = (220 .. 310).to_a.map { |i| i.to_f / 10 }
FAN_SPEED_ARRAY = (100 .. 255).to_a

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
      t.float  :out_temp
      t.float  :in_temp
      t.integer  :fan_speed,   limit: 7
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

def fan_speed_array(temp)
  FAN_SPEED_ARRAY[(FAN_SPEED_ARRAY.size * (TEMP_ARRAY.index(temp.round(1)).to_f / TEMP_ARRAY.size)).round]
end

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
          ds18b20s.map do |sensor|
            read_data = sensor.read
            if IN_TEMP == sensor.serial_number
              if read_data[:celsius] > TEMP_ARRAY.first && read_data[:celsius] <= TEMP_ARRAY.last
                fan_speed = fan_speed_array(read_data[:celsius])
              end
              if read_data[:celsius] > TEMP_ARRAY.last
                fan_speed = 255
              end
              in_temp = read_data[:celsius]
            else
              out_temp = read_data[:celsius]
            end
            led.color = [fan_speed, 0, 0]
          end
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
    sleep 5
    next
  end
end