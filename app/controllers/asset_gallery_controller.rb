class AssetGalleryController < ApplicationController
  def index
    @special = params[:view] == "special"
    if @special
      @region_groups = Region::EDITIONS.map do |edition|
        regions = Region.for_edition(edition).sort_by { |region| Country.collating_key(region.display_name) }
        [ edition, regions ]
      end
    else
      @countries = Country.ordered_by_display_name
    end
  end
end
