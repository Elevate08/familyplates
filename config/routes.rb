Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication & Registration
  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token

  # Family Member Profiles & Switcher
  get "select_profile" => "profiles#select", as: :select_profile
  post "set_profile/:id" => "profiles#set", as: :set_profile
  resources :family_members, only: %i[index create update destroy] do
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
    resource :account, only: %i[edit update]
    resource :household, only: %i[edit update] do
      post :test_google_calendar
      post :sync_google_calendar
    end
  end

  # Onboarding Wizard
  namespace :onboarding do
    get :recipes
    post :save_recipes
    get :pantry
    post :save_pantry
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
