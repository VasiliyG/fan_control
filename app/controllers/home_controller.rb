class HomeController < ActionController::Base
  layout 'application'
  DATETIME_FORMAT = '%d.%m.%Y %H:%M'.freeze
  def index
    @temperature_last = Temperature.order(:measure_time).last
  end

  def current_temperature
    @temperature_last = Temperature.order(:measure_time).last
  end
end
