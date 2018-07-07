#include "TimerOne.h"
#include <OneWire.h>
#include <DallasTemperature.h>

#define ONE_WIRE_BUS 10
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);
DeviceAddress insideThermometer, outsideThermometer, streetThermometer;

String ext_fan_speed;

int max_temp = 0;
int fan_speed = 0;
int fan_speed_for_write = 0;

const int array_size = 100;
int temp_values[array_size];

int reduce_step = 0;
int reduce_spline = 30;
const int reduce_max = 20;

int fan_pin = 11;

int auto_mode_pin = 2;
int ext_mode_pin = 3;

int ext_mode_steps = 5;
const int ext_max_steps = 5;

float temp_1 = 0.0;
float temp_2 = 0.0;
float temp_3 = 0.0;

void setup() {
  pinMode(auto_mode_pin, OUTPUT);
  pinMode(ext_mode_pin, OUTPUT);
  pinMode(fan_pin, OUTPUT);
  Serial.begin(115200);
  Timer1.initialize(20000000);
  Timer1.attachInterrupt(send_data_to_serial);
  sensors.begin();
  if (!sensors.getAddress(insideThermometer, 0)) Serial.println("Unable to find address for Device 0");
  if (!sensors.getAddress(outsideThermometer, 1)) Serial.println("Unable to find address for Device 1");
  if (!sensors.getAddress(outsideThermometer, 2)) Serial.println("Unable to find address for Device 2");
}

void loop() {
  if (Serial.available()) {
    ext_fan_speed = Serial.readString();
    ext_mode_steps = 0;
  }
  delay(1000);
  temp_1 = sensors.getTempCByIndex(0);
  delay(100);
  temp_2 = sensors.getTempCByIndex(1);
  delay(100);
  temp_3 = sensors.getTempCByIndex(2);
  set_fan_speed();
}

void set_fan_speed() {
  max_temp = (max(max(temp_1, temp_2), temp_3) * 100);

  if (max_temp < (average(temp_values) + reduce_spline) && reduce_step < reduce_max) {
    reduce_step++;
  }
  else {
    memcpy(temp_values, &temp_values[1], sizeof(temp_values) - sizeof(int));
    temp_values[array_size - 1] = map(max_temp, 2300, 3400, 0, 255);
    fan_speed = average(temp_values);
    reduce_step = 0;
  }
  if (ext_mode_steps < ext_max_steps) {
    fan_speed_for_write = ext_fan_speed.toInt();
    show_mode(1);
  }
  else {
    fan_speed_for_write = fan_speed;
    show_mode(0);
  }
  write_fan_speed(fan_speed_for_write);
}

int average (int temp_values[array_size]) {
  float sum = 0;
  for (int index = 0; index < array_size; index++) {
    sum += temp_values[index];
  }
  int average = sum / array_size;
  sum = 0;
  return average;
}

String out_string;
void send_data_to_serial() {
  ext_mode_steps++;

  out_string = "";
  out_string += "[{ 'fan_speed': ";
  out_string += fan_speed_for_write;


  sensors.requestTemperatures();
  out_string += ", 't_1_addr': ";
  out_string += printAddress(insideThermometer);
  out_string += ", 't_1_temp': ";
  out_string += temp_1;
  out_string += ", 't_2_addr': ";
  out_string += printAddress(outsideThermometer);
  out_string += ", 't_2_temp': ";
  out_string += temp_2;
  out_string += ", 't_3_addr': ";
  out_string += printAddress(streetThermometer);
  out_string += ", 't_3_temp': ";
  out_string += temp_3;
  out_string += " }]";
  Serial.println(out_string);
}

void write_fan_speed(int fan_speed_to_write) {
  if (fan_speed_to_write > 255) {
    fan_speed_to_write = 255;
  }
  analogWrite(fan_pin, fan_speed_to_write);
}

void show_mode(int mode) {
  if (mode == 1) {
    digitalWrite(ext_mode_pin, HIGH);
    digitalWrite(auto_mode_pin, LOW);
  }
  else {
    digitalWrite(ext_mode_pin, LOW);
    digitalWrite(auto_mode_pin, HIGH);
  }
}

String sensor_addres;
String printAddress(DeviceAddress deviceAddress)
{
  sensor_addres = "";
  for (uint8_t i = 0; i < 8; i++)
  {
    if (deviceAddress[i] < 16) sensor_addres += "0";
    sensor_addres += deviceAddress[i];
  }
  return sensor_addres;
}


