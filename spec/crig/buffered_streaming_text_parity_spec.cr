require "../spec_helper"

# Model whose buffered completion and raw stream both yield "Paris" with usage.
class ParisParityModel
  include Crig::Completion::CompletionModel

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("Paris")
      ),
      Crig::Completion::Usage.new(input_tokens: 4, output_tokens: 1, total_tokens: 5),
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::MockResponse).stream(
      ["Par", "is"],
      Crig::MockResponse.new(5)
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

module Crig
  describe "buffered_streaming_text_parity conformance" do
    it "returns equivalent text and usage from buffered and streamed surfaces" do
      model = ParisParityModel.new
      request = model.completion_request("Answer with exactly the single word Paris.")
        .temperature(0.0)
        .max_tokens(32)
        .build

      buffered = model.completion(request)
      buffered_text = buffered.choice.to_a.compact_map(&.text).map(&.text).join

      stream = model.stream(request)
      streamed_usage = nil.as(Crig::Completion::Usage?)
      streamed_text = String.build do |io|
        stream.each_item do |item|
          case item.kind
          in .text?
            if text = item.text
              io << text.text
            end
          in .final?
            streamed_usage = item.final.try(&.token_usage)
          in .tool_call?, .tool_call_delta?, .reasoning?, .reasoning_delta?
          end
        end
      end

      normalize = ->(text : String) { text.strip.strip { |c| !c.alphanumeric? } }
      buffered_answer = normalize.call(buffered_text)
      streamed_answer = normalize.call(streamed_text)

      buffered_answer.downcase.should eq("paris")
      streamed_answer.downcase.should eq("paris")
      buffered.usage.has_values?.should be_true
      streamed_usage.should_not be_nil
      streamed_usage.try(&.has_values?).should be_true
    end
  end
end
