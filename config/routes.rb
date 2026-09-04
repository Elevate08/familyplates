Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Session / Profile Logout
  resource :session, only: %i[new create destroy] do
    get :verify
    post :verify, to: "sessions#submit_verify"
  end
  get "signed_out" => "sessions#signed_out", as: :signed_out

  # Multi-tenant Signup & Email Verification
  resource :signup, only: %i[new create] do
    get :verify
    post :verify, to: "signups#submit_verify"
  end
  get "signup" => "signups#new"

  # Hosted Subscriptions & Billing
  resource :subscription, only: %i[show create destroy] do
    get :portal
  end

  # Family Member Profiles & Switcher
  get "select_profile" => "profiles#select", as: :select_profile
  post "set_profile/:id" => "profiles#set", as: :set_profile
  # Roster mutation lives only in Admin::FamilyMembersController. This is the
  # read-only roster plus the profile switcher.
  resources :family_members, only: %i[index] do
    member do
      post :switch
    end
  end
  get "activity", to: "activity_events#index", as: :activity_history
  get "suspended", to: "suspensions#show", as: :suspended
  resource :account_data, only: :show, controller: "account_data" do
    get :export
    post :request_deletion
  end
  resources :support_threads, only: %i[index show create] do
    resources :messages, only: :create, controller: "support_messages"
  end

  # Connected Devices
  resources :devices, only: %i[index destroy] do
    collection do
      delete :destroy_all
    end
  end

  # Passkey Authentication & Management
  resources :passkeys, only: %i[index create destroy] do
    collection do
      post :registration_options
      post :authentication_options
      post :callback
    end
  end

  # External Identity Providers (OAuth / OIDC)
  post "auth/:provider" => "external_auth#passthru", as: :auth_request
  get "auth/:provider/callback" => "external_auth#callback", as: :auth_callback
  post "auth/:provider/callback" => "external_auth#callback"
  delete "auth/identities/:id" => "external_auth#destroy_identity", as: :auth_identity

  # Device Pairing (RFC 8628)
  get "pair" => "device_pairings#index", as: :pair
  get "pair/new" => "device_pairings#new", as: :new_pair
  post "pair/device_authorization" => "device_pairings#device_authorization", as: :device_authorization_pair
  post "pair/token" => "device_pairings#token", as: :token_pair
  get "pair/verify" => "device_pairings#verify", as: :verify_pair
  post "pair/approve" => "device_pairings#approve", as: :approve_pair
  post "pair/deny" => "device_pairings#deny", as: :deny_pair
  get "kiosk" => "device_pairings#new", defaults: { kind: "kiosk" }

  # Household Join Code Redemption
  get "join" => "joins#new", as: :join
  post "join" => "joins#create"

  # Signed Profile Transfer Links
  get "transfer/:token" => "transfers#show", as: :transfer
  post "transfer/:token" => "transfers#claim", as: :claim_transfer

  # User Preferences (for active family member)
  resource :preferences, only: %i[edit update]
  get "preferences" => "preferences#edit"

  # Admin Control Center (parents/organizers)
  namespace :admin do
    root to: "dashboard#index"
    resources :family_members, only: %i[index create edit update destroy] do
      member do
        patch :reset_pin
      end
    end
    # Calendar testing and syncing live only on Admin::CalendarsController.
    resource :household, only: %i[edit update] do
      post :reset_join_code
    end
    resource :calendar, only: %i[show edit update], controller: "calendars" do
      post :test_connection
      post :sync_plan
      post :regenerate_feed_token
    end
  end

  # Private hosted-platform operator console. This is intentionally separate
  # from the household organizer admin namespace and authentication boundary.
  namespace :platform_admin do
    root to: "dashboard#index"
    resource :session, only: %i[new create destroy]
    resources :audit_events, only: :index
    resources :deletion_requests, only: %i[index destroy], controller: "deletion_requests"
    resources :households, only: %i[index show] do
      member do
        post :suspend
        post :restore
      end
    end
    resources :support_threads, only: %i[index show] do
      member do
        post :reply
        patch :resolve
      end
    end
  end

  # Public iCalendar subscription feeds (token-authenticated)
  get "calendars/feed/:token", to: "calendar_feeds#show", as: :calendar_feed, defaults: { format: :ics }, constraints: { token: /[a-zA-Z0-9_-]+/ }
  get "calendars/feed/:token/members/:member_id", to: "calendar_feeds#member", as: :calendar_member_feed, defaults: { format: :ics }, constraints: { token: /[a-zA-Z0-9_-]+/ }

  # First-Boot Setup & Onboarding Wizard
  get "onboarding" => "onboarding#family", as: :onboarding
  get "setup" => "onboarding#family", as: :setup
  scope :onboarding, as: :onboarding do
    get "family", to: "onboarding#family"
    post "save_family", to: "onboarding#save_family"
    get "members", to: "onboarding#members"
    post "add_member", to: "onboarding#add_member"
    delete "members/:id", to: "onboarding#remove_member", as: :remove_member
    get "recipes", to: "onboarding#recipes"
    post "save_recipes", to: "onboarding#save_recipes"
    get "pantry", to: "onboarding#pantry"
    post "save_pantry", to: "onboarding#save_pantry"
    get "complete", to: "onboarding#complete"
  end

  # Pantry Items
  resources :pantry_items, only: %i[index create update destroy] do
    member do
      patch :toggle_staple
    end
  end

  # Recipes & Scraper
  resources :recipes do
    collection do
      post :bulk_update
      post :bulk_destroy
    end
    resources :recipe_requests, only: %i[create destroy]
  end
  resources :recipe_imports, only: %i[new create]

  # Weekly Meal Plans & Outputs
  resources :meal_plans do
    resources :meal_plan_slots, only: %i[create update destroy]
    member do
      get :print
      post :sync_calendar
    end
  end
  resources :meal_plan_slots, only: %i[create update destroy]

  # Grocery List (current active or specific plan)
  get "grocery_list" => "grocery_lists#show", as: :grocery_list
  get "grocery_list/:meal_plan_id" => "grocery_lists#show", as: :plan_grocery_list

  # Dashboard & Landing
  root "home#index"
end
