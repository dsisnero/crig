require "../src/crig"

module Crig::Examples::SentimentClassifier
  # An enum representing the sentiment of a document
  enum Sentiment
    Positive
    Negative
    Neutral
  end

  # A struct representing the sentiment of a document
  struct DocumentSentiment
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    # The sentiment of the document
    getter sentiment : Sentiment

    def initialize(@sentiment : Sentiment)
    end
  end
end

begin
  # Check if OPENAI_API_KEY is set
  openai_api_key = ENV["OPENAI_API_KEY"]?

  if openai_api_key
    puts "Setting up sentiment classifier example:"
    puts "  - Model: GPT-4"
    puts "  - Task: Sentiment classification"
    puts "  - Method: Structured data extraction"
    puts ""

    # Create OpenAI client
    puts "1. Setting up OpenAI client..."
    client = Crig::Providers::OpenAI::Client.new(openai_api_key)
    puts "   ✓ OpenAI client ready"

    # Create extractor
    puts "2. Creating sentiment extractor..."
    data_extractor = client
      .extractor(Crig::Examples::SentimentClassifier::DocumentSentiment, "gpt-4")
      .build
    puts "   ✓ Extractor ready"

    # Test sentences with different sentiments
    test_sentences = [
      "I am happy",
      "This is terrible",
      "The weather is okay today",
      "I love this product!",
      "This service is awful",
      "It's neither good nor bad",
    ]

    puts "3. Testing sentiment classification:"
    puts "=" * 60

    test_sentences.each do |sentence|
      puts "Text: \"#{sentence}\""
      begin
        sentiment = data_extractor.extract(sentence)
        puts "Sentiment: #{sentiment.sentiment}"
      rescue ex
        puts "Error: #{ex.message}"
      end
      puts "-" * 40
    end

    puts "=" * 60
    puts ""
    puts "Summary: This example shows structured data extraction for sentiment analysis."
    puts "The model classifies text into Positive, Negative, or Neutral categories."
  else
    puts "OPENAI_API_KEY not set."
    puts "This example uses OpenAI GPT-4 for sentiment classification via structured extraction."
    puts ""
    puts "To run this example:"
    puts "  export OPENAI_API_KEY=your_openai_key"
    puts "  crystal run examples/sentiment_classifier.cr"
    puts ""
    puts "Note: Structured extraction allows the model to output data in a predefined format."
    puts "      This is useful for classification, entity extraction, and other structured tasks."
  end
rescue ex : Crig::Completion::CompletionError
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts "This could be due to:"
  STDERR.puts "1. Invalid API key"
  STDERR.puts "2. API quota exceeded"
  STDERR.puts "3. Network connectivity issues"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
