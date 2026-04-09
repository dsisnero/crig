require "../spec_helper"

describe Crig::JSONUtils do
  it "serializes and deserializes stringified json" do
    dummy = DummyStringifiedJSON.new(JSON.parse(%({"key":"value"})))
    serialized = dummy.to_json
    inner = %({"key":"value"})
    payload = %({"data":#{inner.to_json}})
    parsed = DummyStringifiedJSON.from_json(payload)

    serialized.should eq(payload)
    parsed.data["key"].as_s.should eq("value")
  end

  it "deserializes empty stringified json as an empty object" do
    parsed = DummyStringifiedJSON.from_json(%({"data":""}))

    parsed.data.as_h.should eq({} of String => JSON::Any)
  end

  it "parses empty or valid tool arguments strings" do
    Crig::JSONUtils.parse_tool_arguments("").as_h.should eq({} of String => JSON::Any)
    Crig::JSONUtils.parse_tool_arguments("   ").as_h.should eq({} of String => JSON::Any)
    Crig::JSONUtils.parse_tool_arguments(%({"city":"Denver"}))["city"].as_s.should eq("Denver")
  end

  it "deserializes maybe-stringified json from strings and objects" do
    stringified_payload = Crig::Providers::OpenAI.build_json_any do |json|
      json.object do
        json.field "data", %({"city":"Denver"})
      end
    end

    DummyMaybeStringifiedJSON.from_json(stringified_payload.to_json).data["city"].as_s.should eq("Denver")
    DummyMaybeStringifiedJSON.from_json(%({"data":{"city":"Denver"}})).data["city"].as_s.should eq("Denver")
    DummyMaybeStringifiedJSON.from_json(%({"data":""})).data.as_h.should eq({} of String => JSON::Any)
  end
end
