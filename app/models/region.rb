class Region < ApplicationRecord
  EDITIONS = %w[us_states de_states ch_cantons it_regions].freeze

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z]{2}-[a-z0-9]+\z/ }
  validates :edition, presence: true, inclusion: { in: EDITIONS }
  validates :name_de, presence: true
  validates :name_en, presence: true

  scope :for_edition, ->(edition) { where(edition: edition) }

  def aliases_de
    split_aliases(read_attribute(:aliases_de))
  end

  def aliases_de=(arr)
    write_attribute(:aliases_de, Array(arr).map(&:to_s).map(&:strip).reject(&:blank?).join("|||"))
  end

  def aliases_en
    split_aliases(read_attribute(:aliases_en))
  end

  def aliases_en=(arr)
    write_attribute(:aliases_en, Array(arr).map(&:to_s).map(&:strip).reject(&:blank?).join("|||"))
  end

  def display_name(locale = I18n.locale)
    locale.to_sym == :en ? name_en : name_de
  end

  def all_names
    [name_de, name_en, *aliases_de, *aliases_en].compact.map(&:to_s)
  end

  def matches_guess?(guess, locale = I18n.locale)
    return false if guess.blank?

    normalized_guess = Country.normalize(guess)
    return false if normalized_guess.blank?

    all_names.any? { |n| Country.normalize(n) == normalized_guess }
  end

  def evaluate_guess(guess, _mode, locale = I18n.locale)
    matches_guess?(guess, locale) ? [ :correct, nil ] : [ :wrong, nil ]
  end

  def shape_path
    "shapes/regions/#{code}.svg"
  end

  def flag_path
    "flags/regions/#{code}.svg"
  end

  private

  def split_aliases(value)
    return [] if value.blank? || value == "[]"
    value.to_s.split("|||").map(&:strip).reject(&:blank?)
  end
end
