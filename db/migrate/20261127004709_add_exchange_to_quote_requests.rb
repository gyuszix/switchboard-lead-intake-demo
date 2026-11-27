class AddExchangeToQuoteRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :quote_requests, :request_body, :text
    add_column :quote_requests, :response_body, :text
  end
end
