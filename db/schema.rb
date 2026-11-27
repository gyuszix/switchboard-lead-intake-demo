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

ActiveRecord::Schema[8.1].define(version: 2026_11_27_002553) do
  create_table "quote_requests", force: :cascade do |t|
    t.integer "submission_id", null: false
    t.string "channel", null: false
    t.string "carrier", null: false
    t.string "status", null: false
    t.integer "premium"
    t.string "reference"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["submission_id"], name: "index_quote_requests_on_submission_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.text "transcript", null: false
    t.json "fields", default: [], null: false
    t.boolean "used_fixtures", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "submission_json"
    t.datetime "ready_at"
  end

  add_foreign_key "quote_requests", "submissions"
end
