class Country < ApplicationRecord
  LEVELS = %w[easy medium hard].freeze
  MODES = %w[shape flag].freeze

  validates :iso2, presence: true, uniqueness: true, length: { is: 2 }
  validates :iso3, presence: true, uniqueness: true, length: { is: 3 }
  validates :sporcle_name, presence: true, uniqueness: true
  validates :name_de, presence: true
  validates :name_en, presence: true
  validates :difficulty_shape, inclusion: { in: LEVELS }
  validates :difficulty_flag, inclusion: { in: LEVELS }

  scope :for_mode_level, ->(mode, level) {
    column = mode == "flag" ? :difficulty_flag : :difficulty_shape
    level == "mixed" || level.blank? ? all : where(column => level)
  }

  # Aliases stored as plain "|||"-joined strings — no YAML/JSON coder involved.
  # Keeps it working on any Ruby version with only core String/Array.
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
    [sporcle_name, name_de, name_en, *aliases_de, *aliases_en].compact.map(&:to_s)
  end

  def matches_guess?(guess, locale = I18n.locale)
    return false if guess.blank?

    normalized_guess = self.class.normalize(guess)
    return false if normalized_guess.blank?

    all_names.any? { |n| self.class.normalize(n) == normalized_guess }
  end

  def self.normalize(str)
    I18n.transliterate(str.to_s).downcase.strip.gsub(/[^a-z0-9\s\-'&]/, "").squeeze(" ").strip
  end

  def shape_path
    "shapes/#{iso2.downcase}.svg"
  end

  def flag_path
    "flags/#{iso2.downcase}.svg"
  end

  private

  def split_aliases(value)
    return [] if value.blank? || value == "[]"
    value.to_s.split("|||").map(&:strip).reject(&:blank?)
  end
end
