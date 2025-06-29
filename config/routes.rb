Rails.application.routes.draw do
  devise_for :users, skip: :all

  # OAuth routes (standard omniauth paths)
  get '/auth/:provider/callback', to: 'api/v1/omniauth_callbacks#google_oauth2'
  get '/auth/failure', to: 'api/v1/omniauth_callbacks#failure'

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

      # OAuth routes
      get 'auth/google', to: redirect('/auth/google_oauth2')
      get 'auth/google_oauth2/callback', to: 'omniauth_callbacks#google_oauth2'
      get 'auth/oauth_urls', to: 'auth#oauth_urls'
      get 'auth/providers', to: 'auth#providers'
      post 'auth/simulate_oauth', to: 'auth#simulate_oauth'
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
