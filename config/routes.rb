Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/:locale", locale: /de|en/ do
    root "home#index", as: :localized_root
    get "quiz/:mode", to: "quizzes#show", as: :quiz, constraints: { mode: /shape|flag/ }
    post "quiz/:mode/guess", to: "quizzes#guess", as: :quiz_guess, constraints: { mode: /shape|flag/ }
    post "quiz/:mode/skip", to: "quizzes#skip", as: :quiz_skip, constraints: { mode: /shape|flag/ }
    post "quiz/reset", to: "quizzes#reset", as: :quiz_reset
    get "countries.json", to: "countries#index", as: :countries_json
  end

  root to: redirect("/de", status: 302)
end
