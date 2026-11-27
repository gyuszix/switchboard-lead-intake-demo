class AddDocumentToQuoteRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :quote_requests, :document, :binary
  end
end
