Rails.application.routes.draw do
  root "submissions#new"
  resources :submissions, only: %i[create show] do
    patch :confirm_all, on: :member
    post :build, on: :member
    get :ready, on: :member
    resources :quote_requests, only: :create
    resources :fields, only: :update, param: :name do
      patch :approve, on: :member
      patch :not_provided, on: :member
    end
  end

  # Fake carrier systems the channels talk to over real HTTP.
  namespace :mock_carriers do
    post "acme/api/v1/quotes", to: "acme#create", as: :acme_quotes
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
