class HomeController < ActionController::Base
  layout 'application'
  def index
    @temperature_last = Temperature.order(:measure_time).last
    @temperatures = Temperature.order(:measure_time).where('( id % 2 ) = 0').last(1_500)
    @labels = @temperatures.map{ |s| s.measure_time.strftime('%d-%m-%Y %H:%M') }.to_json
  end
end
