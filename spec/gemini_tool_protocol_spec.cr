require "./spec_helper"

describe "Gemini Tool Protocol Finish Reason Errors" do
  it "returns ResponseError for MalformedFunctionCall finish reason" do
    json = %({
      "responseId": "resp-1",
      "candidates": [{
        "content": {"parts": [{"text": ""}], "role": "model"},
        "finishReason": "MALFORMED_FUNCTION_CALL",
        "finishMessage": "The function call was malformed"
      }],
      "usageMetadata": {"promptTokenCount": 10, "totalTokenCount": 10}
    })

    expect_raises(Crig::Completion::CompletionError, /Gemini stopped/) do
      Crig::Providers::Gemini::GenerateContentResponse.from_json(json).to_completion_response
    end
  end

  it "does not error on normal Stop finish reason" do
    json = %({
      "responseId": "resp-2",
      "candidates": [{
        "content": {"parts": [{"text": "Hello"}], "role": "model"},
        "finishReason": "STOP",
        "finishMessage": "Finished"
      }],
      "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5, "totalTokenCount": 15}
    })

    response = Crig::Providers::Gemini::GenerateContentResponse.from_json(json).to_completion_response
    response.raw_response.should_not be_nil
  end
end

describe "Gemini Streaming StreamingCompletionResponse fields" do
  it "deserializes finish_reason, finish_message, and model_version" do
    json = %({
      "usageMetadata": {"promptTokenCount": 10, "totalTokenCount": 10},
      "finishReason": "STOP",
      "finishMessage": "DONE",
      "modelVersion": "gemini-2.0-flash@001"
    })

    response = Crig::Providers::Gemini::StreamingCompletionResponse.from_json(json)
    response.finish_reason.should_not be_nil
    response.finish_message.should eq("DONE")
    response.model_version.should eq("gemini-2.0-flash@001")
  end

  it "handles missing optional streaming response fields" do
    json = %({"usageMetadata": {"promptTokenCount": 10, "totalTokenCount": 10}})
    response = Crig::Providers::Gemini::StreamingCompletionResponse.from_json(json)
    response.finish_reason.should be_nil
    response.finish_message.should be_nil
    response.model_version.should be_nil
  end
end
