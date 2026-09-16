namespace :shapes do
  desc "Download Natural Earth 50m GeoJSON and build per-country SVGs into app/assets/images/shapes"
  task build: :environment do
    require "json"
    require "open-uri"

    src = ENV.fetch("GEOJSON_URL", "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson")
    vendor_path = Rails.root.join("vendor/geo/ne_50m_admin_0_countries.geojson")
    out_dir = Rails.root.join("app/assets/images/shapes")
    FileUtils.mkdir_p(vendor_path.dirname)
    FileUtils.mkdir_p(out_dir)

    unless vendor_path.exist?
      puts "Downloading #{src} ..."
      URI.open(src) do |remote|
        File.binwrite(vendor_path, remote.read)
      end
    end

    geo = JSON.parse(File.read(vendor_path))
    iso3_to_iso2 = {}
    Country.find_each { |c| iso3_to_iso2[c.iso3] = c.iso2.downcase }

    # Max edge-to-edge gap (degrees, longitude scaled by cos(lat)) for a polygon
    # to still count as part of the main territory. Drops far-flung extras like
    # Caribbean Netherlands, French Guiana, Greenland-as-Denmark, Hawaii, etc.,
    # while keeping archipelagos (Indonesia, Philippines, Japan) via chaining.
    CLUSTER_GAP_DEG = 10.0
    # Spherical Mercator latitude clamp (standard +/-85.05112878).
    MERCATOR_MAX_LAT = 85.05112878
    # Micro-states (Vatican, Monaco, …) otherwise get a sub-pixel viewBox and vanish on screen.
    MIN_VIEW_SPAN = 0.05

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

    built = 0
    dropped_notes = Hash.new(0)
    geo["features"].each do |f|
      iso2 = resolve_iso2.call(f["properties"])
      next unless iso2

      polys = f["geometry"]["type"] == "Polygon" ? [f["geometry"]["coordinates"]] : f["geometry"]["coordinates"]
      # Outer rings only (kids don't need enclave holes like Lesotho-in-SA),
      # unwrapped across the dateline.
      rings = polys.map { |poly| unwrapper.call(poly.first) }
      rings.reject! { |r| r.size < 4 }

      # Flood-fill from the largest polygon: keep everything chained within
      # CLUSTER_GAP_DEG of the main territory, drop the rest.
      by_area = rings.sort_by { |r| -ring_area.call(r) }
      kept = [by_area.shift]
      kept_boxes = [bbox_of.call(kept.first)]
      rest = by_area
      loop do
        found_idx = rest.index do |r|
          box = bbox_of.call(r)
          kept_boxes.any? { |kb| bbox_gap.call(kb, box) <= CLUSTER_GAP_DEG }
        end
        break unless found_idx

        ring = rest.delete_at(found_idx)
        kept << ring
        kept_boxes << bbox_of.call(ring)
      end
      dropped_notes[iso2] = rest.size if rest.any?

      xs = []
      ys = []
      paths = kept.map do |ring|
        pts = ring.map { |lon, lat| projector.call(lon, lat) }
        pts.each { |x, y| xs << x; ys << y }
        pts.map.with_index { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x.round(4)},#{y.round(4)}" }.join(" ") + " Z"
      end

      min_x, max_x = xs.minmax
      min_y, max_y = ys.minmax
      w = [max_x - min_x, 1e-9].max
      h = [max_y - min_y, 1e-9].max
      if w < MIN_VIEW_SPAN || h < MIN_VIEW_SPAN
        cx = (min_x + max_x) / 2.0
        cy = (min_y + max_y) / 2.0
        w = [w, MIN_VIEW_SPAN].max
        h = [h, MIN_VIEW_SPAN].max
        min_x = cx - w / 2.0
        min_y = cy - h / 2.0
        max_x = min_x + w
        max_y = min_y + h
      end
      pad_x = w * 0.05
      pad_y = h * 0.05
      view_box = "#{min_x - pad_x} #{min_y - pad_y} #{w + pad_x * 2} #{h + pad_y * 2}"

      svg = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}"><g vector-effect="non-scaling-stroke" stroke-width="3" stroke-linejoin="round">#{paths.map { |d| %(<path d="#{d}"/>) }.join}</g></svg>)
      File.write(out_dir.join("#{iso2}.svg"), svg)
      built += 1
    end
    puts "Built #{built} shape SVGs into #{out_dir}"
    puts "Missing: #{Country.count - built} (usually XKX/Kosovo — not in Natural Earth de facto set)"
    dropped_notes.sort.each { |iso, n| puts "  #{iso.upcase}: dropped #{n} far-flung polygon(s)" }
  end
end
