# The three sample call transcripts and their fixture extractions, used to
# demo the app and as a fallback when Ollama is unreachable.
module Sample
  DIR = Rails.root.join("config/samples")

  ALL = [
    { key: "bakery", title: "Clean: bakery" },
    { key: "landscaping", title: "Misheard FEIN: landscaping" },
    { key: "it_services", title: "Messy: IT services" }
  ].freeze

  def self.all
    ALL.map { _1.merge(transcript: DIR.join("#{_1[:key]}.txt").read) }
  end

  # Fixture extraction for a sample transcript, or nil if it isn't one.
  def self.fixture_for(transcript)
    sample = all.find { squish(_1[:transcript]) == squish(transcript) }
    sample && JSON.parse(DIR.join("#{sample[:key]}.json").read)
  end

  def self.squish(text) = text.to_s.squish
end
