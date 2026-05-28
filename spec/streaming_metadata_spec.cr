require "./spec_helper"

struct MockStreamingResponse
  include Crig::Completion::GetTokenUsage

  def token_usage : Crig::Completion::Usage?
    Crig::Completion::Usage.new(total_tokens: 3)
  end
end

describe "Streaming TextStart and TextAdditionalParams" do
  it "TextStart resets text item index and applies initial metadata" do
    items = [] of Crig::RawStreamingChoice(MockStreamingResponse)

    items << Crig::RawStreamingChoice(MockStreamingResponse).text_start(JSON.parse(%({"block":1})))
    items << Crig::RawStreamingChoice(MockStreamingResponse).message("hello")
    items << Crig::RawStreamingChoice(MockStreamingResponse).final_response(
      MockStreamingResponse.new
    )

    raw = Crig::StreamingResult(MockStreamingResponse).new(items)
    stream = Crig::StreamingCompletionResponse(MockStreamingResponse).stream_raw_choices(raw.items)
    output = stream.consume

    output.any? { |o| o.kind.text? }.should be_true

    response = stream.to_completion_response
    choice = response.choice.to_a
    text_items = choice.select(&.kind.text?).map(&.text.not_nil!)
    text_items.size.should eq(1)
    text_items.first.additional_params.should_not be_nil
    text_items.first.additional_params.not_nil!["block"].raw.should eq(1)
  end

  it "TextAdditionalParams merges metadata into existing text block" do
    items = [] of Crig::RawStreamingChoice(MockStreamingResponse)

    items << Crig::RawStreamingChoice(MockStreamingResponse).text_start(JSON.parse(%({"citations":[]})))
    items << Crig::RawStreamingChoice(MockStreamingResponse).message("cited text")
    items << Crig::RawStreamingChoice(MockStreamingResponse).text_additional_params(JSON.parse(%({"citations":[{"type":"char_location"}]})))
    items << Crig::RawStreamingChoice(MockStreamingResponse).final_response(
      MockStreamingResponse.new
    )

    raw = Crig::StreamingResult(MockStreamingResponse).new(items)
    stream = Crig::StreamingCompletionResponse(MockStreamingResponse).stream_raw_choices(raw.items)
    stream.consume

    response = stream.to_completion_response
    choice = response.choice.to_a
    text_items = choice.select(&.kind.text?).map(&.text.not_nil!)
    text_items.size.should eq(1)
    params = text_items.first.additional_params
    params.should_not be_nil
    params.not_nil!.as_h.has_key?("citations").should be_true
  end

  it "TextStart without params still works" do
    items = [] of Crig::RawStreamingChoice(MockStreamingResponse)

    items << Crig::RawStreamingChoice(MockStreamingResponse).text_start
    items << Crig::RawStreamingChoice(MockStreamingResponse).message("plain")
    items << Crig::RawStreamingChoice(MockStreamingResponse).final_response(
      MockStreamingResponse.new
    )

    raw = Crig::StreamingResult(MockStreamingResponse).new(items)
    stream = Crig::StreamingCompletionResponse(MockStreamingResponse).stream_raw_choices(raw.items)
    stream.consume

    response = stream.to_completion_response
    choice = response.choice.to_a
    text_items = choice.select(&.kind.text?).map(&.text.not_nil!)
    text_items.size.should eq(1)
    text_items.first.text.should eq("plain")
  end
end

describe "merge_text_additional_params" do
  it "merges object fields" do
    existing = JSON.parse(%({"a":1,"b":2}))
    incoming = JSON.parse(%({"b":3,"c":4}))
    Crig::JSONUtils.merge_text_additional_params(existing, incoming)
    existing["a"].raw.should eq(1)
    existing["b"].raw.should eq(3)
    existing["c"].raw.should eq(4)
  end

  it "concatenates arrays" do
    existing = JSON.parse(%({"citations":[{"a":1}]}))
    incoming = JSON.parse(%({"citations":[{"b":2}]}))
    Crig::JSONUtils.merge_text_additional_params(existing, incoming)
    existing["citations"].as_a.size.should eq(2)
  end

  it "no-ops on non-object existing" do
    existing = JSON.parse(%("hello"))
    incoming = JSON.parse(%({"key":"value"}))
    Crig::JSONUtils.merge_text_additional_params(existing, incoming)
    existing.as_s.should eq("hello")
  end
end
