# The hosted edition's routes, drawn into the app's own route set rather than
# a mounted engine, so they keep the helper names (new_signup_path and so on)
# that core views use when the engine is loaded. Rails loads this file before
# config/routes.rb.
Rails.application.routes.draw do
  # Public sign-up and email verification
  resource :signup, only: %i[new create] do
    get :verify
    post :verify, to: "signups#submit_verify"
  end
  get "signup" => "signups#new"

  # Asking the operator to delete a household
  post "account_data/request_deletion", to: "account_deletion_requests#create", as: :request_deletion_account_data

  # Customer support conversations with the operator
  resources :support_threads, only: %i[index show create] do
    member do
      patch :resolve
    end
    resources :messages, only: :create, controller: "support_messages"
  end

  # Hosted Subscriptions & Billing
  resource :subscription, only: %i[show create destroy] do
    get :portal
  end

  # Where a suspended household is sent
  get "suspended", to: "suspensions#show", as: :suspended

  # Private hosted-platform operator console. This is intentionally separate
  # from the household organizer admin namespace and authentication boundary.
  namespace :platform_admin do
    root to: "dashboard#index"
    resource :session, only: %i[new create destroy]
    resources :audit_events, only: :index
    resources :deletion_requests, only: %i[index destroy], controller: "deletion_requests"
    resources :promotion_programs, only: %i[index create update]
    resources :bulk_operations, only: %i[index new create] do
      collection do
        post :preview
      end
    end
    resources :households, only: %i[index show] do
      member do
        post :suspend
        post :restore
        post :cancel_subscription
        post :comp
      end
      post "charges/:charge_id/refund", action: :refund_charge, on: :member, as: :refund_charge
    end
    resources :support_threads, only: %i[index show] do
      member do
        post :reply
        patch :resolve
        patch :reopen
        patch :change_status
      end
    end
  end

  # Signing in as an operator, for the Playwright crawl
  if Rails.env.test?
    post "__test/sign_in_platform_admin", to: "test_support/platform_admins#create"
  end
end
