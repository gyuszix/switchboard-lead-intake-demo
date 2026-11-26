class CreateSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :submissions do |t|
      t.text :transcript, null: false
      t.json :fields, null: false, default: []
      t.boolean :used_fixtures, null: false, default: false

      t.timestamps
    end
  end
end
