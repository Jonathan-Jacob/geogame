class CountriesController < ApplicationController
  def index
    if params[:edition].in?(Region::EDITIONS)
      regions = Region.for_edition(params[:edition]).order(:name_en)
      render json: regions.map { |r|
        { id: r.id, code: r.code, name: r.display_name(I18n.locale) }
      }
      return
    end

    countries = Country.order(:sporcle_name)
    render json: countries.map { |c|
      { id: c.id, iso2: c.iso2, name: c.display_name(I18n.locale) }
    }
  end
end
