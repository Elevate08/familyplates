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
    resource :household, only: %i[edit update]
    resource :calendar, only: %i[show edit update], controller: "calendars" do
      post :test_connection
      post :sync_plan
    end
  end

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
