namespace :shapes do
  desc "Download Natural Earth GeoJSON and build per-country SVGs into app/assets/images/shapes"
  task build: :environment do
    require "json"
    require "open-uri"
    require "set"
    require "yaml"

    src = ENV.fetch("GEOJSON_URL", "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson")
    high_detail_src = ENV.fetch(
      "GEOJSON_HIGH_DETAIL_URL",
      "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson"
    )
    vendor_path = Rails.root.join("vendor/geo/ne_50m_admin_0_countries.geojson")
    high_detail_path = Rails.root.join("vendor/geo/ne_10m_admin_0_countries.geojson")
    out_dir = Rails.root.join("app/assets/images/shapes")
    FileUtils.mkdir_p(vendor_path.dirname)
    FileUtils.mkdir_p(out_dir)

    download = lambda do |url, path, label|
      return if path.exist?

      puts "Downloading #{label} #{url} ..."
      URI.open(url) do |remote|
        File.binwrite(path, remote.read)
      end
    end
    download.call(src, vendor_path, "50m")
    download.call(high_detail_src, high_detail_path, "10m")

    territory_cfg = YAML.load_file(Rails.root.join("config/shape_territories.yml"))
    mainland_only = Set.new((territory_cfg["mainland_only"] || []).map(&:to_s))
    proximity_only = Set.new((territory_cfg["proximity_only"] || []).map(&:to_s))
    keep_cluster = Set.new((territory_cfg["keep_cluster"] || []).map(&:to_s))
    defaults = territory_cfg["default"] || {}
    CLUSTER_GAP_DEG = defaults.fetch("cluster_gap_deg", 10.0)
    MAINLAND_GAP_DEG = defaults.fetch("mainland_gap_deg", 4.0)
    SIGNIFICANT_AREA_RATIO = defaults.fetch("significant_area_ratio", 0.10)
    proximity_gap_deg = (territory_cfg["proximity_gap_deg"] || {}).transform_keys(&:to_s)
    exclude_centroid_in = (territory_cfg["exclude_centroid_in"] || {}).transform_keys(&:to_s)
    exclude_centroid_in.transform_values! do |boxes|
      Array(boxes).map { |box| Array(box).map(&:to_f) }
    end

    geo = JSON.parse(File.read(vendor_path))
    geo_high_detail = JSON.parse(File.read(high_detail_path))
    iso3_to_iso2 = {}
    iso2_to_iso3 = {}
    Country.find_each do |c|
      iso3_to_iso2[c.iso3] = c.iso2.downcase
      iso2_to_iso3[c.iso2.downcase] = c.iso3
    end

    ultra_detail_iso2 = Set.new((territory_cfg["ultra_detail"] || []).map(&:to_s))
    ULTRA_DETAIL_MAX_VERTICES = territory_cfg.fetch("ultra_detail_max_vertices", 30)
    geoboundaries_dir = Rails.root.join("vendor/geo/geoboundaries")
    FileUtils.mkdir_p(geoboundaries_dir)
    geoboundaries_api = ENV.fetch("GEOBOUNDARIES_API", "https://www.geoboundaries.org/api/current/gbOpen")

    # Spherical Mercator latitude clamp (standard +/-85.05112878).
    MERCATOR_MAX_LAT = 85.05112878
    # Minimum Mercator span for micro-states after uniform scale-up.
    MIN_VIEW_SPAN = 0.05
    TARGET_CONTENT_SPAN = MIN_VIEW_SPAN * 0.82

    # Unwrap a linear ring so it doesn't jump across the antimeridian
    # (Russia/Chukotka, Fiji, NZ Chathams, ...). Returns new array.
    unwrapper = lambda do |ring|
      out = []
      offset = 0.0
      prev = nil
      ring.each do |lon, lat|
        if prev
          d = lon - prev
          offset -= 360.0 if d > 180.0
          offset += 360.0 if d < -180.0
        end
        out << [lon + offset, lat]
        prev = lon
      end
      out
    end

    # Spherical Mercator: x = lon(rad), y = ln(tan(pi/4 + lat(rad)/2)).
    projector = lambda do |lon, lat|
      lat = [[lat, MERCATOR_MAX_LAT].min, -MERCATOR_MAX_LAT].max
      x = lon * Math::PI / 180.0
      y = Math.log(Math.tan(Math::PI / 4.0 + (lat * Math::PI / 180.0) / 2.0))
      [x, -y] # SVG y grows downwards
    end

    # Shoelace area (degree space is fine for comparing polygons of one country).
    ring_area = lambda do |ring|
      sum = 0.0
      ring.each_cons(2) { |(x1, y1), (x2, y2)| sum += (x1 * y2 - x2 * y1) }
      sum.abs / 2.0
    end

    bbox_of = lambda do |ring|
      xs = ring.map(&:first)
      ys = ring.map(&:last)
      [xs.min, ys.min, xs.max, ys.max]
    end

    # Edge-to-edge gap between two bboxes, longitude scaled by cos(mean lat)
    # so high-latitude gaps aren't overstated.
    bbox_gap = lambda do |a, b|
      mean_lat = (a[1] + a[3] + b[1] + b[3]) / 4.0
      kx = Math.cos(mean_lat * Math::PI / 180.0)
      dx = [0.0, a[0] - b[2], b[0] - a[2]].max * kx
      dy = [0.0, a[1] - b[3], b[1] - a[3]].max
      Math.sqrt(dx * dx + dy * dy)
    end

    ring_centroid = lambda do |ring|
      xs = ring.map(&:first)
      ys = ring.map(&:last)
      [xs.sum / xs.size, ys.sum / ys.size]
    end

    centroid_in_box = lambda do |lon, lat, box|
      min_lon, min_lat, max_lon, max_lat = box
      lon >= min_lon && lon <= max_lon && lat >= min_lat && lat <= max_lat
    end

    flood_fill = lambda do |rings, gap_deg|
      by_area = rings.sort_by { |r| -ring_area.call(r) }
      kept = [by_area.shift]
      kept_boxes = [bbox_of.call(kept.first)]
      rest = by_area
      loop do
        found_idx = rest.index do |r|
          box = bbox_of.call(r)
          kept_boxes.any? { |kb| bbox_gap.call(kb, box) <= gap_deg }
        end
        break unless found_idx

        ring = rest.delete_at(found_idx)
        kept << ring
        kept_boxes << bbox_of.call(ring)
      end
      [kept, rest]
    end

    select_rings = lambda do |rings, iso2|
      sorted = rings.sort_by { |r| -ring_area.call(r) }

      if mainland_only.include?(iso2)
        return [sorted.first(1), sorted.drop(1)]
      end

      if keep_cluster.include?(iso2)
        kept, rest = flood_fill.call(rings, CLUSTER_GAP_DEG)
        return [kept, rest]
      end

      anchor = sorted.shift
      kept = [anchor]
      kept_boxes = [bbox_of.call(anchor)]
      rest = sorted
      mainland_gap = proximity_gap_deg.fetch(iso2, MAINLAND_GAP_DEG)

      loop do
        found_idx = rest.index do |r|
          box = bbox_of.call(r)
          kept_boxes.any? { |kb| bbox_gap.call(kb, box) <= mainland_gap }
        end
        break unless found_idx

        ring = rest.delete_at(found_idx)
        kept << ring
        kept_boxes << bbox_of.call(ring)
      end

      if proximity_only.include?(iso2)
        return [kept, rest]
      end

      anchor_area = ring_area.call(anchor)
      threshold = SIGNIFICANT_AREA_RATIO * anchor_area
      still_rest = []
      rest.each do |r|
        if ring_area.call(r) >= threshold
          kept << r
        else
          still_rest << r
        end
      end

      [kept, still_rest]
    end

    # Natural Earth ADM0_A3 sometimes differs from ISO 3166 (e.g. PSX→PSE, KOS→XKX).
    ne_to_iso3 = { "PSX" => "PSE", "KOS" => "XKX" }

    resolve_iso2 = lambda do |props|
      [props["ADM0_A3"], props["ISO_A3"]].each do |code|
        next if code.blank? || code == "-99"

        iso3 = ne_to_iso3[code] || code
        iso2 = iso3_to_iso2[iso3]
        return iso2 if iso2
      end
      nil
    end

    features_10m_by_iso2 = {}
    geo_high_detail["features"].each do |f|
      iso2 = resolve_iso2.call(f["properties"])
      features_10m_by_iso2[iso2] = f if iso2
    end

    max_outer_ring_vertices = lambda do |feature|
      geom = feature["geometry"]
      return 0 unless geom

      polys = geom["type"] == "Polygon" ? [geom["coordinates"]] : geom["coordinates"]
      polys.map { |poly| poly.first.size }.max
    end

    geoboundaries_feature = lambda do |iso3|
      cache_path = geoboundaries_dir.join("#{iso3}.geojson")
      unless cache_path.exist?
        meta_url = "#{geoboundaries_api}/#{iso3}/ADM0/"
        meta = JSON.parse(URI.open(meta_url).read)
        download_url = meta["gjDownloadURL"]
        raise "geoBoundaries: no download URL for #{iso3}" if download_url.blank?

        URI.open(download_url) do |remote|
          File.binwrite(cache_path, remote.read)
        end
      end

      collection = JSON.parse(File.read(cache_path))
      polys = []
      collection["features"].each do |feat|
        geom = feat["geometry"]
        next unless geom

        case geom["type"]
        when "Polygon" then polys << geom["coordinates"]
        when "MultiPolygon" then polys.concat(geom["coordinates"])
        end
      end
      return nil if polys.empty?

      {
        "type" => "Feature",
        "properties" => collection["features"].first["properties"],
        "geometry" => { "type" => "MultiPolygon", "coordinates" => polys }
      }
    rescue StandardError => e
      warn "geoBoundaries #{iso3}: #{e.message}"
      nil
    end

    ultra_detail_wanted = lambda do |iso2, feature|
      return true if ultra_detail_iso2.include?(iso2)

      max_outer_ring_vertices.call(feature) <= ULTRA_DETAIL_MAX_VERTICES
    end

    build_svg = lambda do |feature, iso2, ultra_res: false|
      polys = feature["geometry"]["type"] == "Polygon" ? [feature["geometry"]["coordinates"]] : feature["geometry"]["coordinates"]
      rings = polys.map { |poly| unwrapper.call(poly.first) }
      rings.reject! { |r| r.size < 4 }

      kept, dropped = select_rings.call(rings, iso2)
      if (boxes = exclude_centroid_in[iso2])
        kept, excluded = kept.partition do |ring|
          lon, lat = ring_centroid.call(ring)
          boxes.none? { |box| centroid_in_box.call(lon, lat, box) }
        end
        dropped = dropped + excluded
      end
      point_rings = kept.map { |ring| ring.map { |lon, lat| projector.call(lon, lat) } }

      xs = point_rings.flatten(1).map(&:first)
      ys = point_rings.flatten(1).map(&:last)
      min_x, max_x = xs.minmax
      min_y, max_y = ys.minmax
      w = [max_x - min_x, 1e-9].max
      h = [max_y - min_y, 1e-9].max

      micro_scaled = false
      if w < TARGET_CONTENT_SPAN || h < TARGET_CONTENT_SPAN
        scale = [TARGET_CONTENT_SPAN / w, TARGET_CONTENT_SPAN / h].min
        cx = (min_x + max_x) / 2.0
        cy = (min_y + max_y) / 2.0
        point_rings = point_rings.map do |pts|
          pts.map { |x, y| [cx + scale * (x - cx), cy + scale * (y - cy)] }
        end
        micro_scaled = true
        xs = point_rings.flatten(1).map(&:first)
        ys = point_rings.flatten(1).map(&:last)
        min_x, max_x = xs.minmax
        min_y, max_y = ys.minmax
        w = [max_x - min_x, 1e-9].max
        h = [max_y - min_y, 1e-9].max
      end

      coord_precision = if ultra_res
        6
      else
        micro_scaled ? 5 : 4
      end
      paths = point_rings.map do |pts|
        pts.map.with_index { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x.round(coord_precision)},#{y.round(coord_precision)}" }.join(" ") + " Z"
      end

      pad_x = w * 0.05
      pad_y = h * 0.05
      view_box = "#{min_x - pad_x} #{min_y - pad_y} #{w + pad_x * 2} #{h + pad_y * 2}"

      stroke_width = micro_scaled ? 2 : 3
      svg = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}"><g vector-effect="non-scaling-stroke" stroke-width="#{stroke_width}" stroke-linejoin="round">#{paths.map { |d| %(<path d="#{d}"/>) }.join}</g></svg>)
      { svg: svg, dropped: dropped.size, micro_scaled: micro_scaled }
    end

    built = 0
    dropped_notes = Hash.new(0)
    high_detail_notes = []
    ultra_detail_notes = []
    geo["features"].each do |f|
      iso2 = resolve_iso2.call(f["properties"])
      next unless iso2

      detail_feature = f
      result = build_svg.call(f, iso2)
      if result[:micro_scaled] && (detail = features_10m_by_iso2[iso2])
        result = build_svg.call(detail, iso2)
        detail_feature = detail
        high_detail_notes << iso2
      end
      if result[:micro_scaled] && ultra_detail_wanted.call(iso2, detail_feature)
        iso3 = iso2_to_iso3[iso2]
        if iso3 && (ultra = geoboundaries_feature.call(iso3))
          result = build_svg.call(ultra, iso2, ultra_res: true)
          ultra_detail_notes << iso2
        end
      end

      dropped_notes[iso2] = result[:dropped] if result[:dropped].positive?
      File.write(out_dir.join("#{iso2}.svg"), result[:svg])
      built += 1
    end
    puts "Built #{built} shape SVGs into #{out_dir}"
    puts "Missing: #{Country.count - built} (usually XKX/Kosovo — not in Natural Earth de facto set)"
    high_detail_notes.sort.each { |iso| puts "  #{iso.upcase}: 10m geometry (micro-state detail)" }
    ultra_detail_notes.sort.each { |iso| puts "  #{iso.upcase}: geoBoundaries ADM0 (ultra detail)" }
    dropped_notes.sort.each { |iso, n| puts "  #{iso.upcase}: dropped #{n} far-flung polygon(s)" }
  end
end
