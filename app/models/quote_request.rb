# One attempt to get a quote from (or send a submission to) a carrier
# through one channel. Re-running a channel creates a new row.
class QuoteRequest < ApplicationRecord
  CARRIERS = {
    "api" => "Acme Insurance",
    "portal" => "Beacon Mutual",
    "email" => "Northwind Specialty"
  }.freeze
  CHANNEL_LABELS = { "api" => "API", "portal" => "Portal bot", "email" => "Email" }.freeze
  STATUSES = %w[quoted declined referred sent failed].freeze

  belongs_to :submission

  validates :channel, inclusion: { in: CARRIERS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :carrier, presence: true

  # The portal and email channels store their record as JSON in the same
  # columns the API channel uses for its raw exchange.
  def request_data = parse_record(request_body)
  def response_data = parse_record(response_body)

  private

  def parse_record(text)
    data = JSON.parse(text.to_s)
    data.is_a?(Hash) ? data : nil
  rescue JSON::ParserError
    nil
  end
end
