require "../spec_helper"

struct ConformanceExtractedPerson
  include JSON::Serializable

  @[JSON::Field(key: "first_name")]
  getter first_name : String?
  @[JSON::Field(key: "last_name")]
  getter last_name : String?
  getter job : String?

  def initialize(@first_name : String?, @last_name : String?, @job : String?)
  end
end

# Model that answers the extractor's submit tool call with an ExtractedPerson.
class AdaExtractorModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
      Crig::Completion::AssistantContent.tool_call(
        "submit_1",
        "submit",
        JSON.parse(%({"first_name":"Ada","last_name":"Lovelace","job":"mathematician"})),
      )
    )
    Crig::Completion::CompletionResponse(String).new(
      choice,
      Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

module Crig
  describe "structured_extraction conformance" do
    it "extracts a person through the submit tool and validates fields and usage" do
      model = AdaExtractorModel.new
      extractor = ExtractorBuilder(typeof(model), ConformanceExtractedPerson).new(model)
        .max_tokens(384)
        .retries(0)
        .build

      response = extractor.extract_with_usage("Hello, my name is Ada Lovelace and I work as a mathematician.")

      Conformance.validate_extraction_fields(
        "structured_extraction",
        response.data.first_name,
        response.data.last_name,
        response.data.job,
        response.usage,
      )

      response.data.first_name.should eq("Ada")
      response.data.last_name.should eq("Lovelace")
      response.data.job.should eq("mathematician")
    end
  end
end
