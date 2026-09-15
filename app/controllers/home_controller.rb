class HomeController < ApplicationController
  def index
    session[:quiz_restart] = true
  end
end
