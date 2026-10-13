class ApplicationController < ActionController::Base
  before_action :set_locale
  allow_browser versions: :modern

  private

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
  end

  # Turbo prefetches links on hover. Those GETs must not start or reset a quiz.
  def prefetch_request?
    purpose = [
      request.headers["Sec-Purpose"],
      request.headers["X-Sec-Purpose"],
      request.headers["Purpose"],
      request.headers["X-Purpose"]
    ].compact.join(" ")
    purpose.match?(/prefetch|preview/i)
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
