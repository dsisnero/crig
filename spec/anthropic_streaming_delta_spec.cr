require "./spec_helper"

describe "Anthropic streaming ContentDelta" do
  it "parses citations_delta content delta" do
    json = %({
      "type": "citations_delta",
      "citation": {
        "type": "char_location",
        "cited_text": "hello world",
        "document_index": 0,
        "start_char_index": 0,
        "end_char_index": 11
      }
    })
    delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(JSON.parse(json))
    delta.kind.should eq(Crig::Providers::Anthropic::ContentDeltaKind::CitationsDelta)
    delta.citation.should_not be_nil
    delta.citation.not_nil!.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::CharLocation)
  end

  it "falls back to Unknown for unrecognized delta types" do
    json = %({"type":"future_delta_kind","value":"test"})
    delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(JSON.parse(json))
    delta.kind.should eq(Crig::Providers::Anthropic::ContentDeltaKind::Unknown)
  end

  it "still parses existing text_delta" do
    json = %({"type":"text_delta","text":"hello"})
    delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(JSON.parse(json))
    delta.kind.should eq(Crig::Providers::Anthropic::ContentDeltaKind::TextDelta)
    delta.text.should eq("hello")
  end
end
