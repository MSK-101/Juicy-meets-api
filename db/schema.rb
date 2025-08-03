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

ActiveRecord::Schema[7.2].define(version: 2025_08_03_212050) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admins", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
  end

  create_table "coin_deduction_rules", force: :cascade do |t|
    t.string "name", null: false
    t.integer "duration_seconds", null: false
    t.integer "coins_deducted", null: false
    t.boolean "active", default: true
    t.text "description"
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_coin_deduction_rules_on_active"
    t.index ["sort_order"], name: "index_coin_deduction_rules_on_sort_order"
  end

  create_table "coin_packages", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.integer "coins_count", null: false
    t.boolean "active", default: true
    t.text "description"
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_coin_packages_on_active"
    t.index ["sort_order"], name: "index_coin_packages_on_sort_order"
  end

  create_table "coin_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "transaction_type", null: false
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.bigint "coin_package_id"
    t.bigint "coin_deduction_rule_id"
    t.bigint "user_coin_purchase_id"
    t.string "reference_id"
    t.text "description"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coin_deduction_rule_id"], name: "index_coin_transactions_on_coin_deduction_rule_id"
    t.index ["coin_package_id"], name: "index_coin_transactions_on_coin_package_id"
    t.index ["metadata"], name: "index_coin_transactions_on_metadata", using: :gin
    t.index ["reference_id"], name: "index_coin_transactions_on_reference_id"
    t.index ["transaction_type"], name: "index_coin_transactions_on_transaction_type"
    t.index ["user_coin_purchase_id"], name: "index_coin_transactions_on_user_coin_purchase_id"
    t.index ["user_id"], name: "index_coin_transactions_on_user_id"
  end

  create_table "jwt_denylists", force: :cascade do |t|
    t.string "jti"
    t.datetime "exp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
  end

  create_table "pools", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_pools_on_active"
  end

  create_table "sequences", force: :cascade do |t|
    t.integer "video_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.bigint "pool_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["active"], name: "index_sequences_on_active"
    t.index ["pool_id", "position"], name: "index_sequences_on_pool_id_and_position"
    t.index ["pool_id"], name: "index_sequences_on_pool_id"
    t.index ["position"], name: "index_sequences_on_position"
  end

  create_table "user_coin_purchases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "coin_package_id", null: false
    t.integer "coins_count", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "transaction_id"
    t.string "payment_status", default: "pending"
    t.datetime "purchased_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coin_package_id"], name: "index_user_coin_purchases_on_coin_package_id"
    t.index ["payment_status"], name: "index_user_coin_purchases_on_payment_status"
    t.index ["purchased_at"], name: "index_user_coin_purchases_on_purchased_at"
    t.index ["transaction_id"], name: "index_user_coin_purchases_on_transaction_id"
    t.index ["user_id"], name: "index_user_coin_purchases_on_user_id"
  end

  create_table "user_coins", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "balance", default: 0, null: false
    t.integer "total_earned", default: 0, null: false
    t.integer "total_spent", default: 0, null: false
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["balance"], name: "index_user_coins_on_balance"
    t.index ["last_activity_at"], name: "index_user_coins_on_last_activity_at"
    t.index ["user_id"], name: "index_user_coins_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "age"
    t.integer "gender"
    t.integer "interested_in"
    t.boolean "profile_completed", default: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "provider"
    t.string "uid"
    t.string "role", default: "user"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "videos", force: :cascade do |t|
    t.string "name", null: false
    t.integer "gender", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "sequence_id", null: false
    t.bigint "pool_id", null: false
    t.bigint "admin_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_videos_on_admin_id"
    t.index ["gender"], name: "index_videos_on_gender"
    t.index ["pool_id", "status"], name: "index_videos_on_pool_id_and_status"
    t.index ["pool_id"], name: "index_videos_on_pool_id"
    t.index ["sequence_id", "status"], name: "index_videos_on_sequence_id_and_status"
    t.index ["sequence_id"], name: "index_videos_on_sequence_id"
    t.index ["status"], name: "index_videos_on_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "coin_transactions", "coin_deduction_rules"
  add_foreign_key "coin_transactions", "coin_packages"
  add_foreign_key "coin_transactions", "user_coin_purchases"
  add_foreign_key "coin_transactions", "users"
  add_foreign_key "sequences", "pools"
  add_foreign_key "user_coin_purchases", "coin_packages"
  add_foreign_key "user_coin_purchases", "users"
  add_foreign_key "user_coins", "users"
  add_foreign_key "videos", "admins"
  add_foreign_key "videos", "pools"
  add_foreign_key "videos", "sequences"
end
