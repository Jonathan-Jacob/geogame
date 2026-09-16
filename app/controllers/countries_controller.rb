class CountriesController < ApplicationController
  def index
    countries = Country.order(:sporcle_name)
    render json: countries.map { |c|
      { id: c.id, iso2: c.iso2, name: c.display_name(I18n.locale) }
    }
  end
end
