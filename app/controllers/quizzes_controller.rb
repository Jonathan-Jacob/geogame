class QuizzesController < ApplicationController
  MODES = %w[shape flag].freeze
  LEVELS = %w[easy medium hard mixed].freeze
  ROUNDS_PER_GAME = 10

  before_action :set_mode_level

  def show
    reset_game_if_needed
    return if load_finished_state!

    @country = current_country || pick_next_country
    session[:current_country_id] = @country.id
    @round = session[:quiz_round]
    @score = session[:quiz_score]
    @total = ROUNDS_PER_GAME
    @last_result = session.delete(:last_result)
    @last_answer = session.delete(:last_answer)
  end

  def guess
    if game_over?
      redirect_to quiz_path(mode: @mode, locale: I18n.locale, level: @level)
      return
    end

    country = Country.find_by(id: session[:current_country_id])
    unless country
      redirect_to quiz_path(mode: @mode, locale: I18n.locale, level: @level)
      return
    end

    guess_text = params[:guess].to_s

    if country.matches_guess?(guess_text, I18n.locale)
      session[:quiz_score] = [session[:quiz_score].to_i + 1, ROUNDS_PER_GAME].min
      session[:last_result] = "correct"
    else
      session[:last_result] = "wrong"
    end
    session[:last_answer] = country.display_name(I18n.locale)
    session[:quiz_round] = session[:quiz_round].to_i + 1
    session[:current_country_id] = nil

    if session[:quiz_round] > ROUNDS_PER_GAME
      finish_game!(country)
    end

    redirect_to quiz_path(mode: @mode, locale: I18n.locale, level: @level)
  end

  def skip
    if game_over?
      redirect_to quiz_path(mode: @mode, locale: I18n.locale, level: @level)
      return
    end

    country = Country.find_by(id: session[:current_country_id])
    session[:last_result] = "skipped"
    session[:last_answer] = country&.display_name(I18n.locale)
    session[:quiz_round] = session[:quiz_round].to_i + 1
    session[:current_country_id] = nil

    finish_game!(country) if session[:quiz_round] > ROUNDS_PER_GAME

    redirect_to quiz_path(mode: @mode, locale: I18n.locale, level: @level)
  end

  def reset
    session.delete(:quiz_summary)
    reset_game
    redirect_to quiz_path(mode: params[:mode].in?(MODES) ? params[:mode] : "shape", locale: I18n.locale, level: params[:level].in?(LEVELS) ? params[:level] : "mixed")
  end

  private

  def set_mode_level
    @mode = params[:mode].in?(MODES) ? params[:mode] : "shape"
    @level = params[:level].in?(LEVELS) ? params[:level] : "mixed"
  end

  def game_key
    "quiz_#{@mode}_#{@level}"
  end

  def game_over?
    summary = session[:quiz_summary]
    summary.is_a?(Hash) && summary["game_key"] == game_key
  end

  def load_finished_state!
    summary = session[:quiz_summary]
    return false unless summary.is_a?(Hash) && summary["game_key"] == game_key

    @finished = true
    @final_score = summary["score"].to_i.clamp(0, ROUNDS_PER_GAME)
    @last_result = summary["last_result"]
    @last_answer = summary["last_answer"]
    @round = ROUNDS_PER_GAME
    @total = ROUNDS_PER_GAME
    @country = Country.find_by(id: summary["country_id"])
    true
  end

  def finish_game!(country)
    session[:quiz_summary] = {
      "game_key" => game_key,
      "score" => session[:quiz_score].to_i.clamp(0, ROUNDS_PER_GAME),
      "country_id" => country&.id,
      "last_result" => session[:last_result],
      "last_answer" => session[:last_answer]
    }
    reset_game
  end

  def reset_game_if_needed
    summary = session[:quiz_summary]
    if summary.is_a?(Hash) && summary["game_key"] != game_key
      session.delete(:quiz_summary)
    end

    if session[:game_key] != game_key || session[:quiz_round].nil?
      reset_game
    end
  end

  def reset_game
    session[:game_key] = game_key
    session[:quiz_round] = 1
    session[:quiz_score] = 0
    session[:current_country_id] = nil
    session[:seen_ids] = []
    session.delete(:last_result)
    session.delete(:last_answer)
  end

  def current_country
    Country.find_by(id: session[:current_country_id]) if session[:current_country_id]
  end

  def pick_next_country
    seen = Array(session[:seen_ids])
    pool = Country.for_mode_level(@mode, @level).where.not(id: seen)
    pool = Country.for_mode_level(@mode, @level) if pool.none?
    country = pool.order("RANDOM()").first
    session[:seen_ids] = (seen + [country.id]).last(ROUNDS_PER_GAME * 2)
    country
  end
end
