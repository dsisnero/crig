require "../src/crig"

module Crig::Examples::SentimentClassifier
  enum Sentiment
    Positive
    Negative
    Neutral
  end

  struct DocumentSentiment
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter sentiment : Sentiment

    def initialize(@sentiment : Sentiment)
    end
  end

  DEFAULT_MODEL = Crig::Providers::OpenAI::GPT_4
  DEFAULT_TEXT  = "I am happy"

  def self.build_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = DEFAULT_MODEL,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentSentiment)
    client.extractor(DocumentSentiment, model).build
  end

  def self.classify(
    extractor : Crig::Extractor(M, DocumentSentiment),
    text : String = DEFAULT_TEXT,
  ) : DocumentSentiment forall M
    extractor.extract(text)
  end
end
