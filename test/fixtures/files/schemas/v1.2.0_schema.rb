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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_030000) do
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

  create_table "family_members", force: :cascade do |t|
    t.string "avatar_color", default: "#3B82F6"
    t.string "avatar_icon", default: "chef-hat"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "pin_digest"
    t.string "role", default: "member"
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_family_members_on_household_id"
  end

  create_table "households", force: :cascade do |t|
    t.string "breakfast_time", default: "08:00", null: false
    t.datetime "created_at", null: false
    t.string "dinner_time", default: "18:00", null: false
    t.boolean "google_calendar_enabled", default: false, null: false
    t.string "google_calendar_id"
    t.text "google_service_account_json"
    t.string "lunch_time", default: "12:30", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ingredient_aisle_mappings", force: :cascade do |t|
    t.string "aisle_category", null: false
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.integer "household_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_ingredient_aisle_mappings_on_household_id_and_name"
    t.index ["household_id"], name: "index_ingredient_aisle_mappings_on_household_id"
    t.index ["name", "aisle_category"], name: "index_ingredient_aisle_mappings_on_name_and_aisle_category"
  end

  create_table "meal_plan_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_title"
    t.date "date", null: false
    t.integer "family_member_id"
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
    t.integer "household_id", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.date "week_start_date", null: false
    t.index ["household_id", "week_start_date"], name: "index_meal_plans_on_household_id_and_week_start_date", unique: true
    t.index ["household_id"], name: "index_meal_plans_on_household_id"
  end

  create_table "pantry_items", force: :cascade do |t|
    t.string "aisle_category", default: "Pantry & Grains", null: false
    t.datetime "created_at", null: false
    t.string "emoji"
    t.integer "household_id", null: false
    t.boolean "is_staple", default: true, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id", "name"], name: "index_pantry_items_on_household_id_and_name", unique: true
    t.index ["household_id"], name: "index_pantry_items_on_household_id"
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
    t.integer "family_member_id", null: false
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
    t.integer "household_id", null: false
    t.string "image_url"
    t.text "instructions"
    t.string "meal_types", default: "breakfast,lunch,dinner"
    t.integer "prep_time", default: 15
    t.integer "servings", default: 4
    t.string "source_url"
    t.string "tags"
    t.string "title", null: false
    t.integer "total_time"
    t.datetime "updated_at", null: false
    t.boolean "yields_leftovers", default: false, null: false
    t.index ["household_id", "title"], name: "index_recipes_on_household_id_and_title"
    t.index ["household_id"], name: "index_recipes_on_household_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "family_members", "households"
  add_foreign_key "ingredient_aisle_mappings", "households"
  add_foreign_key "meal_plan_slots", "family_members"
  add_foreign_key "meal_plan_slots", "meal_plans"
  add_foreign_key "meal_plan_slots", "recipes"
  add_foreign_key "meal_plans", "households"
  add_foreign_key "pantry_items", "households"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_requests", "family_members"
  add_foreign_key "recipe_requests", "recipes"
  add_foreign_key "recipes", "households"
end
