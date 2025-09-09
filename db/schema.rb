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

ActiveRecord::Schema[7.2].define(version: 2025_09_09_213656) do
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
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.string "transaction_type", default: "credit", null: false
    t.string "description"
    t.integer "reference_id"
    t.string "reference_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reference_type", "reference_id"], name: "index_coin_transactions_on_reference_type_and_reference_id"
    t.index ["transaction_type"], name: "index_coin_transactions_on_transaction_type"
    t.index ["user_id", "created_at"], name: "index_coin_transactions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_coin_transactions_on_user_id"
  end

  create_table "deduction_rules", force: :cascade do |t|
    t.string "name"
    t.integer "threshold_seconds"
    t.integer "coins", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "deduction_type", default: "duration", null: false
    t.index ["active"], name: "index_deduction_rules_on_active"
    t.index ["deduction_type"], name: "index_deduction_rules_on_deduction_type"
    t.index ["threshold_seconds"], name: "index_deduction_rules_on_threshold_seconds", unique: true
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

  create_table "purchases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "coin_package_id", null: false
    t.integer "coins_count", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "transaction_id"
    t.string "payment_status", default: "pending"
    t.datetime "purchased_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coin_package_id"], name: "index_purchases_on_coin_package_id"
    t.index ["payment_status"], name: "index_purchases_on_payment_status"
    t.index ["transaction_id"], name: "index_purchases_on_transaction_id", unique: true
    t.index ["user_id", "created_at"], name: "index_purchases_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_purchases_on_user_id"
  end

  create_table "sequences", force: :cascade do |t|
    t.integer "video_count", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.bigint "pool_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.text "content_type", default: [], array: true
    t.index ["active"], name: "index_sequences_on_active"
    t.index ["content_type"], name: "index_sequences_on_content_type", using: :gin
    t.index ["pool_id", "position"], name: "index_sequences_on_pool_id_and_position"
    t.index ["pool_id"], name: "index_sequences_on_pool_id"
    t.index ["position"], name: "index_sequences_on_position"
  end

  create_table "staff_assignments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "pool_id", null: false
    t.bigint "sequence_id", null: false
    t.string "status", default: "active", null: false
    t.text "notes"
    t.datetime "last_online_at"
    t.integer "total_chat_time", default: 0
    t.integer "total_chats", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_online_at"], name: "index_staff_assignments_on_last_online_at"
    t.index ["pool_id", "status"], name: "index_staff_assignments_on_pool_id_and_status"
    t.index ["pool_id"], name: "index_staff_assignments_on_pool_id"
    t.index ["sequence_id"], name: "index_staff_assignments_on_sequence_id"
    t.index ["user_id"], name: "index_staff_assignments_on_user_id"
  end

  create_table "user_ip_addresses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address", null: false
    t.datetime "created_at", null: false
    t.index ["ip_address"], name: "index_user_ip_addresses_on_ip_address"
    t.index ["user_id", "ip_address"], name: "index_user_ip_addresses_on_user_id_and_ip_address", unique: true
    t.index ["user_id"], name: "index_user_ip_addresses_on_user_id"
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
    t.integer "coin_balance", default: 0, null: false
    t.datetime "last_activity_at"
    t.integer "total_online_time", default: 0
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "user_status", default: 0, null: false
    t.bigint "sequence_id"
    t.integer "videos_watched_in_current_sequence"
    t.integer "sequence_total_videos"
    t.index ["coin_balance"], name: "index_users_on_coin_balance"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_activity_at"], name: "index_users_on_last_activity_at"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["sequence_id"], name: "index_users_on_sequence_id"
    t.index ["sequence_total_videos"], name: "index_users_on_sequence_total_videos"
    t.index ["status"], name: "index_users_on_status"
    t.index ["user_status"], name: "index_users_on_user_status"
    t.index ["videos_watched_in_current_sequence"], name: "index_users_on_videos_watched_in_current_sequence"
  end

  create_table "video_chat_sessions", force: :cascade do |t|
    t.string "session_id", null: false
    t.bigint "user_id"
    t.bigint "partner_user_id"
    t.bigint "staff_user_id"
    t.bigint "video_id"
    t.bigint "pool_id"
    t.bigint "sequence_id"
    t.string "session_type", null: false
    t.string "status", default: "active", null: false
    t.integer "duration_seconds"
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.string "room_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["partner_user_id"], name: "index_video_chat_sessions_on_partner_user_id"
    t.index ["pool_id", "status"], name: "index_video_chat_sessions_on_pool_id_and_status"
    t.index ["pool_id"], name: "index_video_chat_sessions_on_pool_id"
    t.index ["room_id"], name: "index_video_chat_sessions_on_room_id"
    t.index ["sequence_id", "status"], name: "index_video_chat_sessions_on_sequence_id_and_status"
    t.index ["sequence_id"], name: "index_video_chat_sessions_on_sequence_id"
    t.index ["session_id"], name: "index_video_chat_sessions_on_session_id", unique: true
    t.index ["staff_user_id", "status"], name: "index_video_chat_sessions_on_staff_user_id_and_status"
    t.index ["staff_user_id"], name: "index_video_chat_sessions_on_staff_user_id"
    t.index ["started_at"], name: "index_video_chat_sessions_on_started_at"
    t.index ["user_id", "status"], name: "index_video_chat_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_video_chat_sessions_on_user_id"
    t.index ["video_id", "status"], name: "index_video_chat_sessions_on_video_id_and_status"
    t.index ["video_id"], name: "index_video_chat_sessions_on_video_id"
  end

  create_table "video_waiting_rooms", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "room_id"
    t.bigint "partner_user_id"
    t.string "status", default: "waiting", null: false
    t.boolean "is_initiator", default: false
    t.datetime "joined_at", null: false
    t.bigint "pool_id"
    t.bigint "sequence_id"
    t.string "match_type", default: "real_user", null: false
    t.bigint "video_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "session_version"
    t.datetime "completed_at"
    t.index ["completed_at"], name: "index_video_waiting_rooms_on_completed_at"
    t.index ["partner_user_id"], name: "index_video_waiting_rooms_on_partner_user_id"
    t.index ["pool_id", "status"], name: "index_video_waiting_rooms_on_pool_id_and_status"
    t.index ["pool_id"], name: "index_video_waiting_rooms_on_pool_id"
    t.index ["room_id"], name: "index_video_waiting_rooms_on_room_id"
    t.index ["sequence_id", "status"], name: "index_video_waiting_rooms_on_sequence_id_and_status"
    t.index ["sequence_id"], name: "index_video_waiting_rooms_on_sequence_id"
    t.index ["status"], name: "index_video_waiting_rooms_on_status"
    t.index ["user_id"], name: "index_video_waiting_rooms_on_user_id"
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
  add_foreign_key "coin_transactions", "users"
  add_foreign_key "purchases", "coin_packages"
  add_foreign_key "purchases", "users"
  add_foreign_key "sequences", "pools"
  add_foreign_key "staff_assignments", "pools"
  add_foreign_key "staff_assignments", "sequences"
  add_foreign_key "staff_assignments", "users"
  add_foreign_key "user_ip_addresses", "users"
  add_foreign_key "users", "sequences"
  add_foreign_key "video_chat_sessions", "pools"
  add_foreign_key "video_chat_sessions", "sequences"
  add_foreign_key "video_chat_sessions", "users"
  add_foreign_key "video_chat_sessions", "users", column: "partner_user_id"
  add_foreign_key "video_chat_sessions", "users", column: "staff_user_id"
  add_foreign_key "video_chat_sessions", "videos"
  add_foreign_key "video_waiting_rooms", "pools"
  add_foreign_key "video_waiting_rooms", "sequences"
  add_foreign_key "video_waiting_rooms", "users"
  add_foreign_key "video_waiting_rooms", "users", column: "partner_user_id"
  add_foreign_key "videos", "admins"
  add_foreign_key "videos", "pools"
  add_foreign_key "videos", "sequences"
end
