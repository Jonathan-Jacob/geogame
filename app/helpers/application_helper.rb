module ApplicationHelper
  include QuizHelper

  def special_background?
    special_context?
  end

  def home_path_for_quiz
    if special_context?
      localized_root_path(locale: I18n.locale, view: "special")
    else
      localized_root_path(locale: I18n.locale)
    end
  end

  def special_context?
    (controller_name.in?(%w[home asset_gallery]) && params[:view] == "special") ||
      (controller_name == "quizzes" && params[:edition].in?(Region::EDITIONS))
  end
end
