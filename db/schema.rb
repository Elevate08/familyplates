# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_04_210000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "device_grants", id: :string, force: :cascade do |t|
    t.datetime "approved_at"
    t.string "client_name"
    t.datetime "created_at", null: false
    t.string "device_code", null: false
    t.datetime "expires_at", null: false
    t.string "household_id"
    t.string "ip_address"
    t.string "kind", default: "kiosk", null: false
    t.datetime "last_polled_at"
    t.string "session_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "user_code", null: false
    t.string "user_id"
    t.index ["device_code"], name: "index_device_grants_on_device_code", unique: true
    t.index ["household_id"], name: "index_device_grants_on_household_id"
    t.index ["session_id"], name: "index_device_grants_on_session_id"
    t.index ["status"], name: "index_device_grants_on_status"
    t.index ["user_code"], name: "index_device_grants_on_user_code", unique: true
    t.index ["user_id"], name: "index_device_grants_on_user_id"
  end

  create_table "family_members", id: :string, force: :cascade do |t|
    t.string "avatar_color", default: "#3B82F6"
    t.string "avatar_icon", default: "chef-hat"
    t.datetime "created_at", null: false
    t.string "household_id", null: false
    t.string "name", null: false
    t.string "pin_digest"
    t.string "role", default: "member"
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["household_id", "user_id"], name: "index_family_members_on_household_id_and_user_id", unique: true, where: "user_id IS NOT NULL"
    t.index ["household_id"], name: "index_family_members_on_household_id"
  end

  create_table "households", id: :string, force: :cascade do |t|
    t.string "breakfast_time", default: "08:00", null: false
    t.string "calendar_feed_token"
    t.datetime "created_at", null: false
    t.string "dinner_time", default: "18:00", null: false
    t.boolean "google_calendar_enabled", default: false, null: false
    t.string "google_calendar_id"
    t.text "google_service_account_json"
    t.string "join_code", null: false
    t.string "lunch_time", default: "12:30", null: false
    t.string "name", null: false
    t.datetime "onboarded_at"
    t.datetime "updated_at", null: false
    t.index ["calendar_feed_token"], name: "index_households_on_calendar_feed_token", unique: true
    t.index ["join_code"], name: "index_households_on_join_code", unique: true
  end

  create_table "identities", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "ingredient_aisle_mappings", force: :cascade do |t|
    t.string "aisle_category", null: false
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "household_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_ingredient_aisle_mappings_on_household_id_and_name"
    t.index ["household_id"], name: "index_ingredient_aisle_mappings_on_household_id"
    t.index ["name", "aisle_category"], name: "index_ingredient_aisle_mappings_on_name_and_aisle_category"
  end

  create_table "magic_codes", id: :string, force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false, collation: "NOCASE"
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["code"], name: "index_magic_codes_on_code", unique: true
    t.index ["email"], name: "index_magic_codes_on_email"
    t.index ["user_id"], name: "index_magic_codes_on_user_id"
  end

  create_table "meal_plan_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_title"
    t.date "date", null: false
    t.string "family_member_id"
    t.string "google_event_id"
    t.boolean "is_leftover", default: false, null: false
    t.integer "meal_plan_id", null: false
    t.string "meal_type", default: "dinner", null: false
    t.text "notes"
    t.integer "recipe_id"
    t.string "scheduled_time"
    t.datetime "updated_at", null: false
    t.index ["family_member_id"], name: "index_meal_plan_slots_on_family_member_id"
    t.index ["google_event_id"], name: "index_meal_plan_slots_on_google_event_id"
    t.index ["meal_plan_id", "date", "meal_type"], name: "index_meal_plan_slots_on_meal_plan_id_and_date_and_meal_type"
    t.index ["meal_plan_id"], name: "index_meal_plan_slots_on_meal_plan_id"
    t.index ["recipe_id"], name: "index_meal_plan_slots_on_recipe_id"
  end

  create_table "meal_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "household_id", null: false
    t.text "notes"
    t.integer "number"
    t.datetime "updated_at", null: false
    t.date "week_start_date", null: false
    t.index ["household_id", "number"], name: "index_meal_plans_on_household_id_and_number", unique: true
    t.index ["household_id", "week_start_date"], name: "index_meal_plans_on_household_id_and_week_start_date", unique: true
    t.index ["household_id"], name: "index_meal_plans_on_household_id"
  end

  create_table "pantry_items", force: :cascade do |t|
    t.string "aisle_category", default: "Pantry & Grains", null: false
    t.datetime "created_at", null: false
    t.string "emoji"
    t.string "household_id", null: false
    t.boolean "is_staple", default: true, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_pantry_items_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_pantry_items_on_household_id"
  end

  create_table "passkeys", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.text "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id", "created_at"], name: "index_passkeys_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.json "data"
    t.json "metadata"
    t.json "object"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.bigint "subscription_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.json "object"
    t.string "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.string "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "data"
    t.boolean "default"
    t.string "payment_method_type"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.bigint "customer_id", null: false
    t.json "data"
    t.datetime "ends_at", precision: nil
    t.json "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.json "object"
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "platform_admin_sessions", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "platform_admin_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["platform_admin_id"], name: "index_platform_admin_sessions_on_platform_admin_id"
    t.index ["token"], name: "index_platform_admin_sessions_on_token", unique: true
  end

  create_table "platform_admins", id: :string, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_signed_in_at"
    t.string "otp_secret", null: false
    t.string "password_digest", null: false
    t.string "role", default: "owner", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_platform_admins_on_email", unique: true
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.string "aisle_category", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.decimal "quantity"
    t.string "raw_text"
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["recipe_id", "name"], name: "index_recipe_ingredients_on_recipe_id_and_name"
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
  end

  create_table "recipe_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "family_member_id", null: false
    t.datetime "fulfilled_at"
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.date "week_start_date", null: false
    t.index ["family_member_id"], name: "index_recipe_requests_on_family_member_id"
    t.index ["recipe_id", "family_member_id", "fulfilled_at"], name: "index_recipe_requests_on_active_request"
    t.index ["recipe_id", "family_member_id", "week_start_date"], name: "idx_on_recipe_id_family_member_id_week_start_date_5f86066019"
    t.index ["recipe_id"], name: "index_recipe_requests_on_recipe_id"
  end

  create_table "recipes", force: :cascade do |t|
    t.integer "cook_time", default: 20
    t.datetime "created_at", null: false
    t.text "description"
    t.string "equipment"
    t.string "household_id", null: false
    t.string "image_url"
    t.text "instructions"
    t.string "meal_types", default: "breakfast,lunch,dinner"
    t.integer "number"
    t.integer "prep_time", default: 15
    t.integer "servings", default: 4
    t.string "source_url"
    t.string "tags"
    t.string "title", null: false
    t.integer "total_time"
    t.datetime "updated_at", null: false
    t.boolean "yields_leftovers", default: false, null: false
    t.index ["household_id", "number"], name: "index_recipes_on_household_id_and_number", unique: true
    t.index ["household_id", "title"], name: "index_recipes_on_household_id_and_title"
    t.index ["household_id"], name: "index_recipes_on_household_id"
  end

  create_table "sessions", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "ip_address"
    t.string "kind", default: "browser", null: false
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false, collation: "NOCASE"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "device_grants", "households", on_delete: :cascade
  add_foreign_key "device_grants", "sessions", on_delete: :cascade
  add_foreign_key "device_grants", "users", on_delete: :cascade
  add_foreign_key "family_members", "households"
  add_foreign_key "family_members", "users", on_delete: :nullify
  add_foreign_key "identities", "users", on_delete: :cascade
  add_foreign_key "ingredient_aisle_mappings", "households"
  add_foreign_key "magic_codes", "users", on_delete: :cascade
  add_foreign_key "meal_plan_slots", "family_members"
  add_foreign_key "meal_plan_slots", "meal_plans"
  add_foreign_key "meal_plan_slots", "recipes"
  add_foreign_key "meal_plans", "households"
  add_foreign_key "pantry_items", "households"
  add_foreign_key "passkeys", "users", on_delete: :cascade
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_requests", "family_members"
  add_foreign_key "recipe_requests", "recipes"
  add_foreign_key "recipes", "households"
  add_foreign_key "sessions", "users", on_delete: :cascade
end
