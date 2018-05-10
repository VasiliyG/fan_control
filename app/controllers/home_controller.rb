class HomeController < ActionController::Base
  def index
    @temperature_last = Temperature.order(:measure_time).last
  end
end
