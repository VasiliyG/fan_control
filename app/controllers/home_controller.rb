class HomeController < ActionController::Base
  layout 'application'
  DATETIME_FORMAT = '%d.%m.%Y %H:%M'.freeze
  def index
    params[:datetime_from] = nil if params[:datetime_from].blank?
    params[:datetime_to] = nil if params[:datetime_to].blank?
    params[:datetime_from] ||= (Time.now - 24.hours).strftime(DATETIME_FORMAT)
    params[:datetime_to] ||= Time.now.strftime(DATETIME_FORMAT)
    datetime_from = Time.strptime(params[:datetime_from], DATETIME_FORMAT) + 7.hours
    datetime_to = Time.strptime(params[:datetime_to], DATETIME_FORMAT) + 7.hours
    @temperature_last = Temperature.order(:measure_time).last
    scope = Temperature.order(:measure_time)
    scope.where!(measure_time: datetime_from..datetime_to)
    scope.where!('( id % 2 ) = 0') if params[:only_even_ids] == 'on'
    @temperatures = scope
    @labels = @temperatures.map{ |s| (s.measure_time.in_time_zone).strftime('%d-%m-%Y %H:%M') }.to_json
  end

  def current_temperature
    @temperature_last = Temperature.order(:measure_time).last
  end
end
