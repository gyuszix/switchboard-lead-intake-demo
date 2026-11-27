class CreateQuoteRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :quote_requests do |t|
      t.references :submission, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :carrier, null: false
      t.string :status, null: false
      t.integer :premium
      t.string :reference
      t.text :message

      t.timestamps
    end
  end
end
