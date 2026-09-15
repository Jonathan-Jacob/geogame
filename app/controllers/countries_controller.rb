class CountriesController < ApplicationController
  def index
    mode = params[:mode].in?(%w[shape flag]) ? params[:mode] : "shape"
    level = params[:level].in?(%w[easy medium hard mixed]) ? params[:level] : "mixed"

    countries = Country.for_mode_level(mode, level).order(:sporcle_name)
    render json: countries.map { |c|
      { id: c.id, iso2: c.iso2, name: c.display_name(I18n.locale) }
    }
  end
end
