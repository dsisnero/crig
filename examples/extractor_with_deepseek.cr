require "../src/crig"

module Crig::Examples::ExtractorWithDeepSeek
  # A record representing a person
  struct Person
    include JSON::Serializable

    # The person's first name, if provided (nil otherwise)
    getter first_name : String?
    # The person's last name, if provided (nil otherwise)
    getter last_name : String?
    # The person's job, if provided (nil otherwise)
    getter job : String?

    def initialize(
      @first_name : String? = nil,
      @last_name : String? = nil,
      @job : String? = nil
    )
    end
  end

  def self.build_extractor(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, Person)
    client.extractor(Person, model).build
  end

  def self.pretty_person(person : Person) : String
    JSON.parse(person.to_json).to_pretty_json
  end

  def self.pretty_response(response : Crig::ExtractionResponse(Person)) : String
    JSON.parse(response.data.to_json).to_pretty_json
  end
end

# Main executable code - always run for examples
begin
  # Check if DEEPSEEK_API_KEY is set
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?

  if deepseek_api_key
    puts "Setting up DeepSeek extractor example (low-cost alternative to OpenAI):"
    puts "  - Model: DeepSeek Chat"
    puts "  - Task: Structured data extraction"
    puts "  - Cost: ~10x cheaper than GPT-4"
    puts ""

    # Create DeepSeek client
    puts "1. Setting up DeepSeek client..."
    client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    puts "   ✓ DeepSeek client ready"

    # Create extractor
    puts "2. Creating structured data extractor for Person records..."
    data_extractor = Crig::Examples::ExtractorWithDeepSeek.build_extractor(client)
    puts "   ✓ Extractor ready"

    # Example 1: Extract without usage tracking
    puts "3. Example 1: Extract without usage tracking"
    puts "   Text: \"Hello my name is John Doe! I am a software engineer.\""
    puts "=" * 60
    person = data_extractor.extract("Hello my name is John Doe! I am a software engineer.")
    puts "Extracted data:"
    puts Crig::Examples::ExtractorWithDeepSeek.pretty_person(person)
    puts "=" * 60

    # Example 2: Extract with usage tracking
    puts ""
    puts "4. Example 2: Extract with usage tracking"
    puts "   Text: \"Jane Smith is a data scientist.\""
    puts "=" * 60
    response = data_extractor.extract_with_usage("Jane Smith is a data scientist.")
    puts "Extracted data:"
    puts Crig::Examples::ExtractorWithDeepSeek.pretty_response(response)
    puts ""
    puts "Token usage:"
    puts "  Input tokens: #{response.usage.input_tokens}"
    puts "  Output tokens: #{response.usage.output_tokens}"
    puts "  Total tokens: #{response.usage.total_tokens}"
    puts "=" * 60

    # Example 3: More complex extraction
    puts ""
    puts "5. Example 3: Complex extraction with partial information"
    puts "   Text: \"Dr. Robert Johnson, Chief Medical Officer\""
    puts "=" * 60
    person3 = data_extractor.extract("Dr. Robert Johnson, Chief Medical Officer")
    puts "Extracted data:"
    puts Crig::Examples::ExtractorWithDeepSeek.pretty_person(person3)
    puts "=" * 60

    puts ""
    puts "Summary: DeepSeek provides structured data extraction at ~10x lower cost"
    puts "than OpenAI GPT-4, with similar accuracy for common extraction tasks."
  else
    puts "DEEPSEEK_API_KEY not set."
    puts "This example uses DeepSeek Chat as a low-cost alternative to OpenAI for structured data extraction."
    puts ""
    puts "To run this example:"
    puts "  export DEEPSEEK_API_KEY=your_deepseek_key"
    puts "  crystal run examples/extractor_with_deepseek.cr"
    puts ""
    puts "Note: DeepSeek API is significantly cheaper than OpenAI (~10x cheaper)."
    puts "      Get a free API key at: https://platform.deepseek.com/"
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