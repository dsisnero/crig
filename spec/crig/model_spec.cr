require "../spec_helper"

describe Crig::Model::Model do
  it "builds from id only" do
    model = Crig::Model::Model.from_id("gpt-4")

    model.id.should eq("gpt-4")
    model.name.should be_nil
    model.description.should be_nil
    model.type.should be_nil
    model.created_at.should be_nil
    model.owned_by.should be_nil
    model.context_length.should be_nil
  end

  it "builds with id and name" do
    model = Crig::Model::Model.new("gpt-4", "GPT-4")

    model.id.should eq("gpt-4")
    model.name.should eq("GPT-4")
  end

  it "uses name for display when present" do
    Crig::Model::Model.new("gpt-4", "GPT-4").display_name.should eq("GPT-4")
    Crig::Model::Model.from_id("gpt-4").display_name.should eq("gpt-4")
    Crig::Model::Model.new("gpt-4", "GPT-4").to_s.should eq("GPT-4")
  end

  it "round-trips via json" do
    model = Crig::Model::Model.new(
      "gpt-4",
      name: "GPT-4",
      type: "chat",
      created_at: 1_677_610_600_i64,
      owned_by: "openai",
      context_length: 8192,
    )

    parsed = Crig::Model::Model.from_json(model.to_json)

    parsed.id.should eq("gpt-4")
    parsed.name.should eq("GPT-4")
    parsed.type.should eq("chat")
  end
end

describe Crig::Model::ModelList do
  it "builds and inspects list state" do
    list = Crig::Model::ModelList.new([Crig::Model::Model.from_id("gpt-4")])

    list.len.should eq(1)
    list.empty?.should be_false
    list.iter.to_a.size.should eq(1)
  end

  it "supports empty lists" do
    list = Crig::Model::ModelList.new([] of Crig::Model::Model)

    list.empty?.should be_true
    list.is_empty.should be_true
    list.len.should eq(0)
  end

  it "round-trips via json" do
    list = Crig::Model::ModelList.new([Crig::Model::Model.from_id("gpt-4")])
    parsed = Crig::Model::ModelList.from_json(list.to_json)

    parsed.len.should eq(1)
    parsed.data.first.id.should eq("gpt-4")
  end

  it "supports borrowed and owned iteration helpers" do
    list = Crig::Model::ModelList.new([
      Crig::Model::Model.from_id("gpt-4"),
      Crig::Model::Model.from_id("gpt-3.5-turbo"),
    ])

    list.iter.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
    list.into_iter.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
    list.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
  end
end

describe Crig::Model::ModelListingError do
  it "formats each error variant" do
    Crig::Model::ModelListingError.api_error(404, "Not found").to_s.should eq("API error (status 404): Not found")
    Crig::Model::ModelListingError.request_error("Connection failed").to_s.should eq("Request error: Connection failed")
    Crig::Model::ModelListingError.parse_error("Invalid JSON").to_s.should eq("Parse error: Invalid JSON")
    Crig::Model::ModelListingError.auth_error("Invalid API key").to_s.should eq("Authentication error: Invalid API key")
    Crig::Model::ModelListingError.rate_limit_error("Too many requests").to_s.should eq("Rate limit error: Too many requests")
    Crig::Model::ModelListingError.service_unavailable("Maintenance mode").to_s.should eq("Service unavailable: Maintenance mode")
    Crig::Model::ModelListingError.unknown_error("Something went wrong").to_s.should eq("Unknown error: Something went wrong")
  end

  it "round-trips via json" do
    error = Crig::Model::ModelListingError.api_error(404, "Not found")
    parsed = Crig::Model::ModelListingError.from_json(error.to_json)

    parsed.kind.api_error?.should be_true
    parsed.status_code.should eq(404)
    parsed.message.should eq("Not found")
  end

  it "formats response body preview without truncation" do
    body = "{\"ok\":true}".to_slice
    preview = Crig::Model::ModelListingError.format_response_body_preview(body)
    preview.should eq(%({"ok":true}))
  end

  it "formats response body preview with truncation" do
    limit = Crig::Model::ModelListingError::RESPONSE_BODY_PREVIEW_LIMIT
    body = Bytes.new(limit + 3, 0x61_u8) # 'a' repeated
    preview = Crig::Model::ModelListingError.format_response_body_preview(body)

    preview.starts_with?("a" * limit).should be_true
    preview.should contain("...<truncated 3 bytes>")
  end

  it "api_error_with_context includes provider path and preview" do
    body = "{\"error\":\"boom\"}".to_slice
    error = Crig::Model::ModelListingError.api_error_with_context(
      "Gemini", "/v1beta/models?pageSize=1000", 500, body
    )

    error.kind.api_error?.should be_true
    error.status_code.should eq(500)
    error.message.should contain("provider=Gemini")
    error.message.should contain("path=/v1beta/models?pageSize=1000")
    error.message.should contain("status=500")
    error.message.should contain(%({"error":"boom"}))
  end

  it "parse_error_with_context includes parse error and preview" do
    body = "{\"models\":[{\"displayName\":\"broken\"}]}".to_slice
    error = Crig::Model::ModelListingError.parse_error_with_context(
      "Gemini", "/v1beta/models?pageSize=1000", "EOF while parsing an object", body
    )

    error.kind.parse_error?.should be_true
    error.message.should contain("provider=Gemini")
    error.message.should contain("path=/v1beta/models?pageSize=1000")
    error.message.should contain("parse_error=EOF while parsing an object")
    error.message.should contain(%({"models":[{"displayName":"broken"}]}))
  end
end
