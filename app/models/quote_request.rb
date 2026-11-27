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
end
