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

ActiveRecord::Schema[7.1].define(version: 2026_03_30_162050) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "payments", force: :cascade do |t|
    t.string "idempotency_key", null: false
    t.string "status", default: "pending", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.string "payer_id", null: false
    t.string "payee_id", null: false
    t.string "description"
    t.integer "attempts", default: 0, null: false
    t.string "error_message"
    t.string "gateway_reference"
    t.datetime "processed_at"
    t.datetime "cancelled_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "idx_payments_created_at"
    t.index ["idempotency_key"], name: "idx_payments_idempotency_key_unique", unique: true
    t.index ["payer_id", "status"], name: "idx_payments_payer_id_status"
    t.index ["payer_id"], name: "idx_payments_payer_id"
    t.index ["status"], name: "idx_payments_status"
  end

end
