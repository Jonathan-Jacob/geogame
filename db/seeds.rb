require "yaml"

file = Rails.root.join("db/seed_files/countries.yml")
entries = YAML.load_file(file)

entries.each do |e|
  country = Country.find_or_initialize_by(iso2: e["iso2"])
  country.assign_attributes(
    iso3: e["iso3"],
    sporcle_name: e["sporcle"],
    name_de: e["de"],
    name_en: e["en"],
    aliases_de: e["aliases_de"] || [],
    aliases_en: e["aliases_en"] || [],
    difficulty_shape: e["shape"] || "medium",
    difficulty_flag: e["flag"] || "medium"
  )
  unless country.save
    puts I18n.with_locale(:en) { "FAILED #{e['iso2']}/#{e['sporcle']}: #{country.errors.full_messages.join(', ')}" }
  end
end

puts "Seeded #{Country.count} countries"
puts "Shapes: easy=#{Country.where(difficulty_shape: 'easy').count} medium=#{Country.where(difficulty_shape: 'medium').count} hard=#{Country.where(difficulty_shape: 'hard').count}"
puts "Flags:  easy=#{Country.where(difficulty_flag: 'easy').count} medium=#{Country.where(difficulty_flag: 'medium').count} hard=#{Country.where(difficulty_flag: 'hard').count}"
