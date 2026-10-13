namespace :regions do
  desc "Download Natural Earth admin-1 and build shape SVGs for special editions"
  task shapes: :environment do
    require "json"
    require "open-uri"
    require "set"
    require "yaml"

    src = ENV.fetch(
      "GEOJSON_URL",
      "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson"
    )
    vendor_path = Rails.root.join("vendor/geo/ne_10m_admin_1_states_provinces.geojson")
    out_dir = Rails.root.join("app/assets/images/shapes/regions")
    FileUtils.mkdir_p(vendor_path.dirname)
    FileUtils.mkdir_p(out_dir)

    unless vendor_path.exist?
      puts "Downloading #{src} ..."
      URI.open(src, "User-Agent" => "GeoQuiz/1.0 (local shape import)") do |remote|
        File.binwrite(vendor_path, remote.read)
      end
    end

    entries = YAML.load_file(Rails.root.join("db/seed_files/regions.yml"))
    wanted = entries.map { |e| e["code"].to_s.downcase }
    keep_cluster = Set.new(%w[us-hi])
    mainland_only = Set.new(%w[us-ak])
    cluster_gap_deg = 10.0
    mainland_gap_deg = 4.0
    significant_area_ratio = 0.10
    max_ring_points = 320
    # Same idea as country shapes: a unit whose largest ring is still only a
    # handful of corners (Basel-Stadt 26, Geneva 42) is rebuilt from geoBoundaries.
    # 50 sits above those coarse outlines and below the next canton (Obwalden, 70).
    ultra_detail_max_vertices = 50
    mercator_max_lat = 85.05112878
    geoboundaries_dir = Rails.root.join("vendor/geo/geoboundaries")
    FileUtils.mkdir_p(geoboundaries_dir)
    geoboundaries_api = ENV.fetch("GEOBOUNDARIES_API", "https://www.geoboundaries.org/api/current/gbOpen")
    iso2_to_iso3 = YAML.load_file(Rails.root.join("db/seed_files/countries.yml")).each_with_object({}) do |entry, map|
      map[entry["iso2"].to_s.downcase] = entry["iso3"].to_s.upcase
    end

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

    projector = lambda do |lon, lat|
      lat = [[lat, mercator_max_lat].min, -mercator_max_lat].max
      x = lon * Math::PI / 180.0
      y = Math.log(Math.tan(Math::PI / 4.0 + (lat * Math::PI / 180.0) / 2.0))
      [x, -y]
    end

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

    bbox_gap = lambda do |a, b|
      mean_lat = (a[1] + a[3] + b[1] + b[3]) / 4.0
      kx = Math.cos(mean_lat * Math::PI / 180.0)
      dx = [0.0, a[0] - b[2], b[0] - a[2]].max * kx
      dy = [0.0, a[1] - b[3], b[1] - a[3]].max
      Math.sqrt(dx * dx + dy * dy)
    end

    decimate = lambda do |ring|
      return ring if ring.size <= max_ring_points

      step = (ring.size.to_f / (max_ring_points - 1)).ceil
      sampled = []
      ring.each_with_index { |pt, i| sampled << pt if (i % step).zero? }
      sampled << ring.last if sampled.last != ring.last
      sampled.size >= 4 ? sampled : ring
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
      kept
    end

    select_rings = lambda do |rings, code|
      sorted = rings.sort_by { |r| -ring_area.call(r) }
      return sorted.first(1) if mainland_only.include?(code)
      return flood_fill.call(rings, cluster_gap_deg) if keep_cluster.include?(code)

      anchor = sorted.shift
      kept = [anchor]
      kept_boxes = [bbox_of.call(anchor)]
      rest = sorted

      loop do
        found_idx = rest.index do |r|
          box = bbox_of.call(r)
          kept_boxes.any? { |kb| bbox_gap.call(kb, box) <= mainland_gap_deg }
        end
        break unless found_idx

        ring = rest.delete_at(found_idx)
        kept << ring
        kept_boxes << bbox_of.call(ring)
      end

      anchor_area = ring_area.call(anchor)
      threshold = significant_area_ratio * anchor_area
      rest.each { |r| kept << r if ring_area.call(r) >= threshold }
      kept
    end

    outer_rings = lambda do |feature, include_holes: false|
      geom = feature["geometry"]
      return [] unless geom

      polys = case geom["type"]
      when "Polygon" then [geom["coordinates"]]
      when "MultiPolygon" then geom["coordinates"]
      else []
      end
      polys.flat_map do |poly|
        rings = include_holes ? poly : [ poly.first ]
        rings.filter_map do |ring|
          next if ring.nil? || ring.size < 4

          unwrapper.call(ring)
        end
      end
    end

    point_inside = lambda do |pt, ring|
      x, y = pt
      crossings = 0
      ring.each_cons(2) do |(x1, y1), (x2, y2)|
        next if y1 == y2
        if ((y1 > y) != (y2 > y)) && (x < (x2 - x1) * (y - y1) / (y2 - y1) + x1)
          crossings += 1
        end
      end
      crossings.odd?
    end

    ring_abs_area = lambda do |ring|
      sum = 0.0
      pts = ring.dup
      pts << pts.first if pts.first != pts.last
      pts.each_cons(2) { |(x1, y1), (x2, y2)| sum += (x1 * y2) - (x2 * y1) }
      sum.abs / 2.0
    end

    ring_centroid = lambda do |ring|
      uniq = ring.first == ring.last ? ring[0..-2] : ring
      return ring.first if uniq.empty?

      count = uniq.size.to_f
      [ uniq.sum(&:first) / count, uniq.sum(&:last) / count ]
    end

    # A ring whose center sits inside a larger ring is a hole, or the exclave that fills one.
    # The outer ring already covers that area, so the inner ring is dropped.
    drop_holes = lambda do |rings|
      areas = rings.map { |ring| ring_abs_area.call(ring) }
      rings.reject.with_index do |ring, index|
        center = ring_centroid.call(ring)
        rings.each_with_index.any? do |other, other_index|
          next false if other_index == index
          next false unless areas[other_index] > areas[index]

          point_inside.call(center, other)
        end
      end
    end

    # Drop edges shared by two provinces so only the region outline remains.
    dissolve_rings = lambda do |rings|
      quant = ->(pt) { [ pt[0].round(5), pt[1].round(5) ] }
      counts = Hash.new(0)
      rings.each do |ring|
        pts = ring.map { |pt| quant.call(pt) }
        pts << pts.first if pts.first != pts.last
        pts.each_cons(2) { |a, b| counts[[ a, b ]] += 1 unless a == b }
      end

      remaining = []
      seen = {}
      counts.each do |(a, b), count|
        next if seen[[ a, b ]]

        seen[[ a, b ]] = seen[[ b, a ]] = true
        reverse = counts[[ b, a ]].to_i
        if count > reverse
          (count - reverse).times { remaining << [ a, b ] }
        elsif reverse > count
          (reverse - count).times { remaining << [ b, a ] }
        end
      end

      outgoing = Hash.new { |h, k| h[k] = [] }
      remaining.each { |a, b| outgoing[a] << b }

      built = []
      until outgoing.values.all?(&:empty?)
        start = outgoing.find { |_pt, dests| dests.any? }&.first
        break unless start

        ring = [ start ]
        current = start
        closed = false
        remaining.size.times do
          nxt = outgoing[current].shift
          break unless nxt

          ring << nxt
          if nxt == start
            closed = true
            break
          end
          current = nxt
        end
        built << ring if closed && ring.size >= 4
      end
      built
    end

    adm1_by_iso3 = {}
    load_adm1 = lambda do |iso3|
      return adm1_by_iso3[iso3] if adm1_by_iso3.key?(iso3)

      cache_path = geoboundaries_dir.join("#{iso3}-ADM1.geojson")
      unless cache_path.exist?
        meta_url = "#{geoboundaries_api}/#{iso3}/ADM1/"
        meta = JSON.parse(URI.open(meta_url).read)
        download_url = meta["gjDownloadURL"]
        raise "geoBoundaries: no download URL for #{iso3} ADM1" if download_url.blank?

        puts "Downloading geoBoundaries #{iso3} ADM1 ..."
        URI.open(download_url, "User-Agent" => "GeoQuiz/1.0 (local shape import)") do |remote|
          File.binwrite(cache_path, remote.read)
        end
      end

      index = {}
      JSON.parse(File.read(cache_path))["features"].each do |feature|
        iso = feature.dig("properties", "shapeISO").to_s.downcase
        index[iso] = feature if iso.present? && !index.key?(iso)
      end
      adm1_by_iso3[iso3] = index
    rescue StandardError => e
      warn "geoBoundaries #{iso3} ADM1: #{e.message}"
      adm1_by_iso3[iso3] = {}
    end

    build_svg = lambda do |rings, ultra_res: false|
      point_rings = rings.map do |ring|
        pts = ultra_res ? ring : decimate.call(ring)
        pts.map { |lon, lat| projector.call(lon, lat) }
      end
      xs = point_rings.flatten(1).map(&:first)
      ys = point_rings.flatten(1).map(&:last)
      min_x, max_x = xs.minmax
      min_y, max_y = ys.minmax
      w = [max_x - min_x, 1e-9].max
      h = [max_y - min_y, 1e-9].max

      coord_precision = ultra_res ? 6 : 4
      paths = point_rings.map do |pts|
        pts.map.with_index { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x.round(coord_precision)},#{y.round(coord_precision)}" }.join(" ") + " Z"
      end

      pad_x = w * 0.05
      pad_y = h * 0.05
      view_box = "#{min_x - pad_x} #{min_y - pad_y} #{w + pad_x * 2} #{h + pad_y * 2}"
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}"><g vector-effect="non-scaling-stroke" stroke-width="3" stroke-linejoin="round">#{paths.map { |d| %(<path d="#{d}"/>) }.join}</g></svg>)
    end

    # Natural Earth admin-1 stores Italian provinces, not the 20 regions.
    italy_regions = {
      "Piemonte" => "it-21",
      "Valle d'Aosta" => "it-23",
      "Lombardia" => "it-25",
      "Trentino-Alto Adige" => "it-32",
      "Veneto" => "it-34",
      "Friuli-Venezia Giulia" => "it-36",
      "Liguria" => "it-42",
      "Emilia-Romagna" => "it-45",
      "Toscana" => "it-52",
      "Umbria" => "it-55",
      "Marche" => "it-57",
      "Lazio" => "it-62",
      "Abruzzo" => "it-65",
      "Molise" => "it-67",
      "Campania" => "it-72",
      "Apulia" => "it-75",
      "Basilicata" => "it-77",
      "Calabria" => "it-78",
      "Sicily" => "it-82",
      "Sardegna" => "it-88"
    }

    geo = JSON.parse(File.read(vendor_path))
    rings_by_code = Hash.new { |h, k| h[k] = [] }
    geo["features"].each do |feature|
      props = feature["properties"] || {}
      code = if props["iso_a2"] == "IT"
        italy_regions[props["region"]]
      else
        props["iso_3166_2"].to_s.downcase
      end
      next unless code && wanted.include?(code)

      rings_by_code[code].concat(outer_rings.call(feature, include_holes: code.start_with?("it-")))
    end

    built = 0
    missing = []
    ultra_detail_notes = []
    wanted.each do |code|
      rings = rings_by_code[code]
      if rings.empty?
        missing << code
        next
      end

      if code.start_with?("it-")
        rings = dissolve_rings.call(rings)
        rings = drop_holes.call(rings)
      end
      kept = select_rings.call(rings, code)
      ultra = false
      if kept.map(&:size).max.to_i <= ultra_detail_max_vertices
        iso3 = iso2_to_iso3[code.split("-", 2).first]
        feature = iso3 && load_adm1.call(iso3)[code]
        if feature
          kept = select_rings.call(outer_rings.call(feature), code)
          ultra = true
          ultra_detail_notes << code
        end
      end
      File.write(out_dir.join("#{code}.svg"), build_svg.call(kept, ultra_res: ultra))
      built += 1
    end

    puts "Built #{built} region shape SVGs into #{out_dir}"
    ultra_detail_notes.sort.each { |code| puts "  #{code}: geoBoundaries ADM1 (more corners)" }
    puts "Missing from Natural Earth: #{missing.join(', ')}" if missing.any?
  end

  desc "Download region flag SVGs from the iso3166-flags GitHub dataset"
  task flags: :environment do
    require "open-uri"
    require "yaml"

    # MIT-licensed ISO 3166-2 SVGs. Avoids Wikimedia, which rate-limits Special:FilePath.
    # https://github.com/amckenna41/iso3166-flags
    base = "https://raw.githubusercontent.com/amckenna41/iso3166-flags/main/iso3166-2-flags"
    user_agent = "GeoQuiz/1.0 (local geography-quiz asset import) Ruby/#{RUBY_VERSION}"
    out_dir = Rails.root.join("app/assets/images/flags/regions")
    FileUtils.mkdir_p(out_dir)
    entries = YAML.load_file(Rails.root.join("db/seed_files/regions.yml"))

    pending = entries.reject do |entry|
      dest = out_dir.join("#{entry["code"]}.svg")
      dest.exist? && dest.size.positive?
    end
    puts "#{entries.size - pending.size} already saved, #{pending.size} still to fetch"
    if pending.empty?
      puts "Done."
      next
    end

    failed = []
    pending.each do |entry|
      code = entry["code"]
      country, sub = code.split("-", 2)
      filename = "#{country.upcase}-#{sub.upcase}.svg"
      url = "#{base}/#{country.upcase}/#{filename}"

      begin
        body = nil
        content_type = nil
        URI.open(url, "User-Agent" => user_agent) do |remote|
          content_type = remote.content_type
          body = remote.read
        end
      rescue OpenURI::HTTPError => e
        failed << code
        puts "FAILED #{code}: #{e.message}"
        next
      end

      svg = body.to_s.lstrip.start_with?("<svg", "<?xml") || content_type.to_s.include?("svg")
      unless svg
        failed << code
        puts "FAILED #{code}: response was not an SVG"
        next
      end
      File.binwrite(out_dir.join("#{code}.svg"), body)
      puts "saved #{code}"
    end

    puts "Done. #{entries.size - failed.size} flags in #{out_dir}"
    puts "Failed: #{failed.join(', ')}" if failed.any?
  end
end
