Rails.application.routes.draw do
  root "submissions#new"
  resources :submissions, only: %i[create show]

  get "up" => "rails/health#show", as: :rails_health_check
end
