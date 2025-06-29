Rails.application.routes.draw do
  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      post 'login', to: 'sessions#create'
      delete 'logout', to: 'sessions#destroy'

      resources :users, only: [:create] do
        collection do
          get 'profile'
          put 'complete_profile'
        end
      end

      # Email confirmation routes
      post 'confirmations/confirm', to: 'confirmations#confirm'
      post 'confirmations/resend', to: 'confirmations#resend'
      post 'confirmations/send', to: 'confirmations#send_confirmation'
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
