class QuizzesController < ApplicationController
  MODES = %w[shape flag].freeze
  LEVELS = %w[easy medium hard mixed].freeze
  ROUNDS_PER_GAME = 10

  helper_method :quiz_link_params

  before_action :set_mode_level
  before_action :disable_turbo_preview_cache, only: :show

  def show
    if prefetch_request?
      assign_saved_quiz
      # A prefetch of this URL can land in the gap after a guess, when the
      # round has moved on and no subject is stored yet. Do not let Turbo
      # keep that empty page. The image preload on a real response is separate.
      head :no_content if !@finished && @country.nil?
      return
    end

    if session.delete(:quiz_restart)
      clear_finished_state_for_current_game
      forget_progress
      reset_game
    else
      reset_game_if_needed
    end
    return if load_finished_state!

    restore_progress_if_rewound
    @country = pick_next_subject
    session[:current_country_id] = @country&.id
    @round = session[:quiz_round]
    @score = session[:quiz_score]
    @total = ROUNDS_PER_GAME
    @next_country = queue_next_subject
    @last_result = session.delete(:last_result)
    @last_answer = session.delete(:last_answer)
    @last_guess_name = session.delete(:last_guess_name)
    remember_progress
  end

  def guess
    if game_over?
      redirect_to quiz_path(quiz_link_params)
      return
    end

    country = find_subject(session[:current_country_id])
    unless country
      redirect_to quiz_path(quiz_link_params)
      return
    end

    guess_text = params[:guess].to_s
    outcome, matched_twin = country.evaluate_guess(guess_text, @mode, I18n.locale)

    case outcome
    when :correct
      session[:quiz_score] = [session[:quiz_score].to_i + 1, ROUNDS_PER_GAME].min
      session[:last_result] = "correct"
    when :twin_accepted
      session[:quiz_score] = [session[:quiz_score].to_i + 1, ROUNDS_PER_GAME].min
      session[:last_result] = "correct_twin"
      session[:last_guess_name] = matched_twin.display_name(I18n.locale)
    else
      session[:last_result] = "wrong"
    end
    session[:last_answer] = country.display_name(I18n.locale)
    advance_round!(country)
  end

  def skip
    if game_over?
      redirect_to quiz_path(quiz_link_params)
      return
    end

    country = find_subject(session[:current_country_id])
    session[:last_result] = "skipped"
    session[:last_answer] = country&.display_name(I18n.locale)
    advance_round!(country)
  end

  def reset
    session.delete(:quiz_summary)
    forget_progress
    reset_game
    redirect_to quiz_path(quiz_link_params)
  end

  private

  def quiz_link_params
    base = { mode: @mode, locale: I18n.locale }
    @edition ? base.merge(edition: @edition) : base.merge(level: @level)
  end

  def set_mode_level
    @mode = params[:mode].in?(MODES) ? params[:mode] : "shape"
    @edition = params[:edition].in?(Region::EDITIONS) ? params[:edition] : nil
    @level = if @edition
      nil
    else
      params[:level].in?(LEVELS) ? params[:level] : "mixed"
    end
  end

  def game_key
    "quiz_#{@mode}_#{@edition || @level}"
  end

  def subject_scope
    if @edition
      Region.for_edition(@edition)
    else
      Country.for_mode_level(@mode, @level)
    end
  end

  def find_subject(id)
    subject_scope.find_by(id: id)
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
    @last_guess_name = summary["last_guess_name"]
    @round = ROUNDS_PER_GAME
    @total = ROUNDS_PER_GAME
    @country = find_subject(summary["country_id"])
    true
  end

  def finish_game!(country)
    session[:quiz_summary] = {
      "game_key" => game_key,
      "score" => session[:quiz_score].to_i.clamp(0, ROUNDS_PER_GAME),
      "country_id" => country&.id,
      "last_result" => session[:last_result],
      "last_answer" => session[:last_answer],
      "last_guess_name" => session[:last_guess_name]
    }.compact
    forget_progress
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

  def clear_finished_state_for_current_game
    summary = session[:quiz_summary]
    session.delete(:quiz_summary) if summary.is_a?(Hash) && summary["game_key"] == game_key
  end

  def disable_turbo_preview_cache
    response.headers["Turbo-Cache-Control"] = "no-cache"
  end

  def reset_game
    session[:game_key] = game_key
    session[:quiz_round] = 1
    session[:quiz_score] = 0
    session[:current_country_id] = nil
    session[:queued_country_id] = nil
    session[:seen_ids] = []
    session.delete(:last_result)
    session.delete(:last_answer)
    session.delete(:last_guess_name)
  end

  # Read-only render for a prefetched quiz page. Must not reset or advance.
  def assign_saved_quiz
    if game_over?
      load_finished_state!
      return
    end

    if session[:game_key] == game_key && session[:quiz_round].present?
      @country = find_subject(session[:current_country_id])
      @round = session[:quiz_round]
      @score = session[:quiz_score].to_i
      @total = ROUNDS_PER_GAME
      @last_result = session[:last_result]
      @last_answer = session[:last_answer]
      @last_guess_name = session[:last_guess_name]
      @next_country = find_subject(session[:queued_country_id]) if @mode == "flag" && @country
    else
      @country = nil
      @round = 1
      @score = 0
      @total = ROUNDS_PER_GAME
    end
  end

  def progress_store
    session[:quiz_progress] = {} unless session[:quiz_progress].is_a?(Hash)
    session[:quiz_progress]
  end

  def remember_progress
    progress_store[game_key] = {
      "round" => session[:quiz_round],
      "score" => session[:quiz_score],
      "current_country_id" => session[:current_country_id],
      "queued_country_id" => session[:queued_country_id],
      "seen_ids" => session[:seen_ids]
    }
  end

  def forget_progress
    progress_store.delete(game_key)
  end

  # A hover prefetch can write round 1 over an in-progress game. The saved
  # copy is ahead of that, so put the round back.
  def restore_progress_if_rewound
    saved = progress_store[game_key]
    return unless saved.is_a?(Hash)
    return unless saved["round"].to_i > session[:quiz_round].to_i

    session[:game_key] = game_key
    session[:quiz_round] = saved["round"]
    session[:quiz_score] = saved["score"]
    session[:current_country_id] = saved["current_country_id"]
    session[:queued_country_id] = saved["queued_country_id"]
    session[:seen_ids] = saved["seen_ids"]
  end

  # The next subject is chosen while this round is on screen. Guess and skip
  # promote it before the redirect, so the session never stores a round with
  # no subject. Flag mode also preloads that subject's image.
  def advance_round!(answered)
    session[:quiz_round] = session[:quiz_round].to_i + 1

    if session[:quiz_round] > ROUNDS_PER_GAME
      finish_game!(answered)
    else
      promote_queued_subject(answered)
      remember_progress
    end

    redirect_to quiz_path(quiz_link_params)
  end

  def promote_queued_subject(answered)
    queued_id = session.delete(:queued_country_id)
    subject = find_subject(queued_id) || draw_unseen_subject(exclude_ids: [answered&.id].compact)
    session[:current_country_id] = subject&.id
  end

  def pick_next_subject
    if (subject = find_subject(session[:current_country_id]))
      return subject
    end

    queued_id = session.delete(:queued_country_id)
    if (subject = find_subject(queued_id))
      return subject
    end

    draw_unseen_subject
  end

  # Chosen while the current round is on screen. Flag mode preloads the image;
  # both modes need the id so the next request can render a subject immediately.
  def queue_next_subject
    return if @country.nil? || session[:quiz_round].to_i >= ROUNDS_PER_GAME

    if (queued = find_subject(session[:queued_country_id]))
      return queued
    end

    subject = draw_unseen_subject(exclude_ids: [@country.id])
    session[:queued_country_id] = subject&.id
    subject
  end

  def draw_unseen_subject(exclude_ids: [])
    seen = Array(session[:seen_ids])
    pool = subject_scope.where.not(id: seen)
    if pool.none?
      pool = subject_scope.where.not(id: exclude_ids)
      pool = subject_scope if pool.none?
    end
    subject = pool.order("RANDOM()").first
    return nil unless subject

    session[:seen_ids] = (seen + [subject.id]).last(ROUNDS_PER_GAME * 2)
    subject
  end
end
