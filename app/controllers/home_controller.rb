class HomeController < ApplicationController
  def index
    session[:quiz_restart] = true unless prefetch_request?
    @special = params[:view] == "special"
  end
end
