class HomeController < ApplicationController
  def index
    session[:quiz_restart] = true
    @special = params[:view] == "special"
  end
end
