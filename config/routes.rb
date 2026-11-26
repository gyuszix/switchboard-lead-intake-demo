Rails.application.routes.draw do
  root "submissions#new"
  resources :submissions, only: %i[create show] do
    patch :confirm_all, on: :member
    post :build, on: :member
    get :ready, on: :member
    resources :fields, only: :update, param: :name do
      patch :approve, on: :member
      patch :not_provided, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
