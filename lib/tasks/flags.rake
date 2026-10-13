namespace :flags do
  desc "Replace the 4:3 country flags with each flag's real proportions"
  task ratios: :environment do
    require "open-uri"
    require "tmpdir"

    # Public-domain Wikipedia SVGs. Unlike flag-icons, these keep the real ratio
    # (Switzerland square, Qatar 11:28, Nepal its double pennant, and so on).
    # https://github.com/hampusborgos/country-flags
    url = "https://codeload.github.com/hampusborgos/country-flags/tar.gz/main"
    dest_root = Rails.root.join("app/assets/images/flags")

    Dir.mktmpdir("country-flags") do |dir|
      archive = File.join(dir, "flags.tar.gz")
      puts "Downloading original-ratio flags ..."
      URI.open(url, "User-Agent" => "GeoQuiz/1.0 (local flag import)") do |remote|
        File.binwrite(archive, remote.read)
      end
      system("tar", "-xzf", archive, "-C", dir) || abort("Could not unpack the flag archive")

      svg_dir = Dir[File.join(dir, "*", "svg")].first
      abort "Flag archive had no svg folder" unless svg_dir

      replaced = 0
      Dir[File.join(svg_dir, "*.svg")].each do |file|
        dest = dest_root.join(File.basename(file))
        next unless dest.exist?

        FileUtils.cp(file, dest)
        replaced += 1
      end
      puts "Replaced #{replaced} country flags. Each one now uses its own proportions."
    end
  end
end
