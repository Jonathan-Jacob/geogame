class AssetGalleryController < ApplicationController
  def index
    name_column = I18n.locale.to_sym == :en ? :name_en : :name_de
    @countries = Country.order(name_column)
  end
end
