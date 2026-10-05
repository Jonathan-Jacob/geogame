class AssetGalleryController < ApplicationController
  def index
    @countries = Country.ordered_by_display_name
  end
end
