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

    get "beacon/login", to: "beacon#login", as: :beacon_login
    post "beacon/login", to: "beacon#authenticate"
    get "beacon/applications/new", to: "beacon#new_application", as: :beacon_new_application
    post "beacon/applications", to: "beacon#create_application", as: :beacon_applications
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
