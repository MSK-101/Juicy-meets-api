Rails.application.routes.draw do
  devise_for :users, skip: :all

  # OAuth routes (standard omniauth paths)
  get '/auth/:provider/callback', to: 'api/v1/omniauth_callbacks#google_oauth2'
  post '/auth/:provider/callback', to: 'api/v1/omniauth_callbacks#google_oauth2' # For development testing
  get '/auth/failure', to: 'api/v1/omniauth_callbacks#failure'

  namespace :api do
    namespace :v1 do
      # Authentication routes - Simple and clear
      post 'login', to: 'sessions#create'
      delete 'logout', to: 'sessions#destroy'

      # User management - RESTful
      resources :users, only: [:create, :show] do
        collection do
          get :me  # /api/v1/users/me -> users#show
        end
      end

      # Profile management - Singular resource (one profile per user)
      resource :profile, only: [:show, :update] do
        get :status  # /api/v1/profile/status
      end

      # Email confirmations - RESTful nested resource
      resource :confirmation, only: [] do
        member do
          post :confirm     # /api/v1/confirmation/confirm
          post :resend      # /api/v1/confirmation/resend
          post :send_email  # /api/v1/confirmation/send_email
        end
      end

      # Authentication info - Organized namespace
      namespace :auth do
        get :providers    # /api/v1/auth/providers
        get :oauth_urls   # /api/v1/auth/oauth_urls
        get 'google', to: redirect('/auth/google_oauth2')
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
