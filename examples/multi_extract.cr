require "../src/crig"

module Crig::Examples::MultiExtract
  struct Names
    include JSON::Serializable

    getter names : Array(String)

    def initialize(@names : Array(String))
    end
  end

  struct Topics
    include JSON::Serializable

    getter topics : Array(String)

    def initialize(@topics : Array(String))
    end
  end

  struct Sentiment
    include JSON::Serializable

    getter sentiment : Float64
    getter confidence : Float64

    def initialize(@sentiment : Float64, @confidence : Float64)
    end
  end

  def self.names_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::ExtractorBuilder(Crig::Providers::OpenAI::ResponsesCompletionModel, Names)
    client.extractor(Names, model)
      .preamble("Extract names (e.g.: of people, places) from the given text.")
  end

  def self.topics_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::ExtractorBuilder(Crig::Providers::OpenAI::ResponsesCompletionModel, Topics)
    client.extractor(Topics, model)
      .preamble("Extract topics from the given text.")
  end

  def self.sentiment_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::ExtractorBuilder(Crig::Providers::OpenAI::ResponsesCompletionModel, Sentiment)
    client.extractor(Sentiment, model)
      .preamble("Extract sentiment (and how confident you are of the sentiment) from the given text.")
  end

  def self.format_analysis(names : Names, topics : Topics, sentiment : Sentiment) : String
    "Extracted names: #{names.names.join(", ")}\n" \
    "Extracted topics: #{topics.topics.join(", ")}\n" \
    "Extracted sentiment: #{sentiment.sentiment}"
  end
end
