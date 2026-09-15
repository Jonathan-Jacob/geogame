module QuizHelper
  def shape_svg(country)
    path = Rails.root.join("app/assets/images/shapes/#{country.iso2.downcase}.svg")
    unless path.exist?
      return content_tag(:div, t("quiz.shape_missing"),
        class: "country-shape-missing flex items-center justify-center bg-slate-100 rounded-xl p-8 text-slate-400")
    end

    raw = path.read
    style = shape_aspect_style(raw)
    content_tag(:div, raw.html_safe, class: "country-shape-canvas", style: style)
  end

  def shape_aspect_style(svg_markup)
    return unless svg_markup =~ /viewBox="\s*[\d.eE+-]+\s+[\d.eE+-]+\s+([\d.eE+-]+)\s+([\d.eE+-]+)"/

    w = Regexp.last_match(1).to_f
    h = Regexp.last_match(2).to_f
    return if w <= 0 || h <= 0

    "aspect-ratio: #{w} / #{h};"
  end

  def flag_svg(country, css_class: "w-full max-w-[420px] rounded-xl shadow")
    path = Rails.root.join("app/assets/images/flags/#{country.iso2.downcase}.svg")
    if path.exist?
      image_tag("flags/#{country.iso2.downcase}.svg", alt: t("quiz.flag_alt"), class: css_class)
    else
      content_tag(:div, t("quiz.flag_missing"), class: "p-8 bg-slate-100 rounded-xl text-slate-400")
    end
  end

  def level_badge(level)
    colors = { "easy" => "bg-emerald-200", "medium" => "bg-amber-200", "hard" => "bg-rose-200", "mixed" => "bg-sky-200" }
    content_tag(:span, t("quiz.level_#{level}"), class: "geo-chip #{colors[level] || 'bg-white'}")
  end

  FINISHED_EMOJI = { zero: "🤞", low: "💪", mid: "🥳", high: "😍", perfect: "🤯" }.freeze

  def finished_tier(score, total)
    return :perfect if score == total && total.positive?

    case score
    when 0 then :zero
    when 1..3 then :low
    when 4..6 then :mid
    else :high
    end
  end

  def finished_emoji(score, total)
    FINISHED_EMOJI[finished_tier(score, total)]
  end

  def finished_message(score, total)
    tier = finished_tier(score, total)
    t("quiz.finished_text_#{tier}", score: score, total: total)
  end
end
