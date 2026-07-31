require "../spec_helper"
describe "Crig::Completion::Reasoning constructors", tags: %w[completion reasoning constructors] do
  it "constructs reasoning with new" do
    single = Crig::Completion::Reasoning.new("think")
    single.first_text.should eq("think")
    single.first_signature.should be_nil
    single.display_text.should eq("think")
  end

  it "constructs reasoning with signature" do
    signed = Crig::Completion::Reasoning.new_with_signature("signed", "sig-1")
    signed.first_text.should eq("signed")
    signed.first_signature.should eq("sig-1")
    signed.display_text.should eq("signed")
  end

  it "constructs multi reasoning" do
    multi = Crig::Completion::Reasoning.multi(["a", "b"])
    multi.display_text.should eq("a\nb")
    multi.first_text.should eq("a")
  end

  it "roundtrips reasoning content through JSON" do
    text_variant = Crig::Completion::ReasoningContent.text("plain", "sig")
    json = text_variant.to_json
    parsed = Crig::Completion::ReasoningContent.from_json(json)
    parsed.kind.text?.should be_true
    parsed.text.should eq("plain")
    parsed.signature.should eq("sig")

    encrypted_variant = Crig::Completion::ReasoningContent.encrypted("opaque")
    json2 = encrypted_variant.to_json
    parsed2 = Crig::Completion::ReasoningContent.from_json(json2)
    parsed2.kind.encrypted?.should be_true
    parsed2.data.should eq("opaque")

    redacted_variant = Crig::Completion::ReasoningContent.redacted("redacted")
    json3 = redacted_variant.to_json
    parsed3 = Crig::Completion::ReasoningContent.from_json(json3)
    parsed3.kind.redacted?.should be_true
    parsed3.data.should eq("redacted")

    summary_variant = Crig::Completion::ReasoningContent.summary("sum")
    json4 = summary_variant.to_json
    parsed4 = Crig::Completion::ReasoningContent.from_json(json4)
    parsed4.kind.summary?.should be_true
    parsed4.summary.should eq("sum")
  end
end

describe "merge_reasoning_blocks", tags: %w[streaming reasoning merge] do
  it "preserves order and signatures for matching ids" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new_with_signature("step-1", "sig-1").with_id("rs_1")
    second = Crig::Completion::Reasoning.new_with_signature("step-2", "sig-2").with_id("rs_1")
    incoming = Crig::Completion::Reasoning.new_with_signature("step-3", "sig-3").with_id("rs_1")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, second)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(1)
    accumulated.first.id.should eq("rs_1")
    accumulated.first.content.size.should eq(3)
    accumulated.first.content[0].text.should eq("step-1")
    accumulated.first.content[1].text.should eq("step-2")
    accumulated.first.content[2].text.should eq("step-3")
    accumulated.first.content[0].signature.should eq("sig-1")
    accumulated.first.content[1].signature.should eq("sig-2")
    accumulated.first.content[2].signature.should eq("sig-3")
  end

  it "keeps distinct ids as separate items" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new("step-1").with_id("rs_a")
    incoming = Crig::Completion::Reasoning.new("step-2").with_id("rs_b")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should eq("rs_a")
    accumulated[1].id.should eq("rs_b")
  end

  it "keeps nil ids as separate items" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new("first")
    incoming = Crig::Completion::Reasoning.new("second")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
  end
end

describe "OneOrMany#map_one_or_many", tags: %w[one_or_many map] do
  it "transforms single item to new type" do
    one = Crig::OneOrMany(String).one("42")
    result = one.map_one_or_many { |s| s.to_i32 }
    result.first.should eq(42)
    result.len.should eq(1)
  end

  it "transforms multiple items preserving OneOrMany" do
    many = Crig::OneOrMany(String).many(["1", "2", "3"])
    result = many.map_one_or_many { |s| s.to_i32 }
    result.to_a.should eq([1, 2, 3])
    result.len.should eq(3)
  end
end

describe "JSONUtils::StringOrVecConverter", tags: %w[json string_or_vec] do
  it "deserializes a single string into an array" do
    result = DummyStringOrVec.from_json(%({"items":"hello"}))
    result.items.should eq(["hello"])
  end

  it "deserializes an array into an array" do
    result = DummyStringOrVec.from_json(%({"items":["hello","world"]}))
    result.items.should eq(["hello", "world"])
  end
end

describe "JSONUtils::NullOrVecConverter", tags: %w[json null_or_vec] do
  it "deserializes null into empty array" do
    result = DummyNullOrVec.from_json(%({"items":null}))
    result.items.should eq([] of String)
  end

  it "deserializes an array into an array" do
    result = DummyNullOrVec.from_json(%({"items":["a","b"]}))
    result.items.should eq(["a", "b"])
  end
end

struct SerializeOnlySerializer
  include JSON::Serializable
  getter value : String

  def initialize(@value : String = "")
  end
end

struct DeserializeOnlyParser
  include JSON::Serializable
  getter value : String

  def initialize(@value : String = "")
  end
end

describe "TypedPromptResponse serde", tags: %w[agent typed_prompt_response] do
  it "serializes with serialize-only output" do
    response = Crig::TypedPromptResponse(SerializeOnlySerializer).new(
      SerializeOnlySerializer.new("ok"),
      Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3),
    )
    json = response.to_json
    json.should contain(%("value":"ok"))
  end

  it "deserializes with deserialize-only output" do
    json = %({"output":{"value":"ok"},"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3,"cached_input_tokens":0,"cache_creation_input_tokens":0,"reasoning_tokens":0},"completion_calls":[]})
    response = Crig::TypedPromptResponse(DeserializeOnlyParser).from_json(json)
    response.output.value.should eq("ok")
    response.usage.input_tokens.should eq(1)
    response.usage.output_tokens.should eq(2)
    response.usage.total_tokens.should eq(3)
  end
end

describe "tool_result_to_user_message multimodal", tags: %w[streaming tool_result] do
  it "preserves multimodal tool output with response and image parts" do
    tool_output_json = %({
      "response": {
        "instruction": "Use the image part to answer."
      },
      "parts": [
        {
          "type": "image",
          "data": "base64data==",
          "mimeType": "image/png"
        }
      ]
    })

    message = Crig.tool_result_to_user_message("tool_call_1", "call_1", tool_output_json)

    message.role.user?.should be_true
    user_contents = message.content.to_a
    user_contents.size.should eq(1)

    first_content = user_contents.first.as(Crig::Completion::UserContent)
    first_content.kind.tool_result?.should be_true

    tool_result = first_content.tool_result.not_nil!
    tool_result.id.should eq("tool_call_1")
    tool_result.call_id.should eq("call_1")
    tool_result.content.size.should eq(2)

    items = tool_result.content.to_a
    items[0].kind.text?.should be_true
    items[0].text.not_nil!.text.should contain("Use the image part to answer.")

    items[1].kind.image?.should be_true
    image = items[1].image.not_nil!
    image.data.kind.base64?.should be_true
    image.data.string_value.should eq("base64data==")
    image.media_type.should eq(Crig::Completion::ImageMediaType::PNG)
  end
end

describe Crig::Providers::Mistral::Usage, tags: %w[mistral usage] do
  it "deserializes prompt_tokens_details.cached_tokens" do
    json = %({"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_tokens_details":{"cached_tokens":42}})
    usage = Crig::Providers::Mistral::Usage.from_json(json)
    usage.prompt_tokens.should eq(100)
    usage.completion_tokens.should eq(20)
    usage.total_tokens.should eq(120)
    usage.prompt_tokens_details.not_nil!.cached_tokens.should eq(42)
    usage.cached_tokens.should eq(42)
  end

  it "accepts singular prompt_token_details alias" do
    json = %({"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_token_details":{"cached_tokens":7}})
    usage = Crig::Providers::Mistral::Usage.from_json(json)
    usage.prompt_token_details_alias.not_nil!.cached_tokens.should eq(7)
    usage.cached_tokens.should eq(7)
  end

  it "falls back to num_cached_tokens" do
    json = %({"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"num_cached_tokens":13})
    usage = Crig::Providers::Mistral::Usage.from_json(json)
    usage.num_cached_tokens.should eq(13)
    usage.prompt_tokens_details.should be_nil
    usage.cached_tokens.should eq(13)
  end

  it "prefers prompt_tokens_details over num_cached_tokens" do
    json = %({"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"num_cached_tokens":1,"prompt_tokens_details":{"cached_tokens":99}})
    usage = Crig::Providers::Mistral::Usage.from_json(json)
    usage.cached_tokens.should eq(99)
  end

  it "threads cached tokens into Completion::Usage" do
    json = %({"id":"cmpl-x","object":"chat.completion","model":"mistral-small-latest","created":1700000000,"choices":[{"index":0,"message":{"content":"hi","role":"assistant","prefix":false,"tool_calls":[]},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_tokens_details":{"cached_tokens":42}}})
    response = Crig::Providers::Mistral::CompletionResponse.from_json(json)
    usage = response.token_usage.not_nil!
    usage.input_tokens.should eq(100)
    usage.output_tokens.should eq(20)
    usage.total_tokens.should eq(120)
    usage.cached_input_tokens.should eq(42)
  end
end
