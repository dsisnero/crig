require "../src/crig"

module Crig::Examples::SentimentClassifier
  # An enum representing the sentiment of a document
  enum Sentiment
    Positive
    Negative
    Neutral
  end

  struct DocumentSentiment
    include JSON::Serializable

    # The sentiment of the document
    getter sentiment : Sentiment

    def initialize(@sentiment : Sentiment)
    end
  end

  def self.build_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentSentiment)
    client.extractor(DocumentSentiment, model).build
  end

  def self.extract_sentiment(
    extractor : Crig::Extractor(M, DocumentSentiment),
    text : String,
  ) : DocumentSentiment forall M
    extractor.extract(text)
  end
end

# Main executable code - always run for examples
begin
  # Create OpenAI client
  client = Crig::Providers::OpenAI::Client.from_env

  # Create extractor
  extractor = Crig::Examples::SentimentClassifier.build_extractor(client)

  # Extract sentiment
  sentiment = Crig::Examples::SentimentClassifier.extract_sentiment(extractor, "I am happy")

  puts "GPT-4: #{sentiment}"
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
