require "./spec_helper"

describe "Anthropic Citation" do
  it "deserializes char_location citation" do
    json = %({"type":"char_location","cited_text":"hello","document_index":0,"start_char_index":5,"end_char_index":10})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::CharLocation)
  end

  it "deserializes page_location citation" do
    json = %({"type":"page_location","cited_text":"hello","document_index":0,"start_page_number":1,"end_page_number":2})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::PageLocation)
  end

  it "deserializes content_block_location citation" do
    json = %({"type":"content_block_location","cited_text":"hello","document_index":0,"start_block_index":0,"end_block_index":1})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::ContentBlockLocation)
  end

  it "deserializes search_result_location citation" do
    json = %({"type":"search_result_location","cited_text":"hello","document_index":0,"url":"https://example.com"})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::SearchResultLocation)
  end

  it "deserializes web_search_result_location citation" do
    json = %({"type":"web_search_result_location","cited_text":"hello","url":"https://example.com"})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::WebSearchResultLocation)
  end

  it "falls back to unknown for unrecognized citation types" do
    json = %({"type":"future_citation_kind","foo":"bar"})
    citation = Crig::Providers::Anthropic::Citation.from_json(json)
    citation.kind.should eq(Crig::Providers::Anthropic::Citation::Kind::Unknown)
  end
end

describe "Anthropic Content text citations" do
  it "parses text content with citations" do
    json = %({"type":"text","text":"cited text","citations":[{"type":"char_location","cited_text":"cited","document_index":0,"start_char_index":0,"end_char_index":5}]})
    content = Crig::Providers::Anthropic::Content.from_json_value(JSON.parse(json))
    content.kind.text?.should be_true
    content.text.should eq("cited text")
    content.citations.should_not be_nil
    content.citations.not_nil!.size.should eq(1)
  end

  it "parses text content without citations" do
    json = %({"type":"text","text":"plain text"})
    content = Crig::Providers::Anthropic::Content.from_json_value(JSON.parse(json))
    content.kind.text?.should be_true
    content.text.should eq("plain text")
    content.citations.should be_nil
  end
end

describe "Anthropic Content server_tool_use" do
  it "parses server_tool_use content" do
    json = %({"type":"server_tool_use","id":"toolu_01","name":"web_search","input":{}})
    content = Crig::Providers::Anthropic::Content.from_json_value(JSON.parse(json))
    content.kind.server_tool_use?.should be_true
    content.id.should eq("toolu_01")
    content.name.should eq("web_search")
  end
end

describe "Anthropic Content web_search_tool_result" do
  it "parses web_search_tool_result content" do
    json = %({"type":"web_search_tool_result","tool_use_id":"toolu_01","content":["Result 1","Result 2"]})
    content = Crig::Providers::Anthropic::Content.from_json_value(JSON.parse(json))
    content.kind.web_search_tool_result?.should be_true
    content.tool_use_id.should eq("toolu_01")
  end
end

describe "Anthropic Content document fields" do
  it "parses document with title, context, and citations config" do
    json = %({"type":"document","source":{"type":"text","media_type":"text/plain","data":"doc content"},"title":"My Doc","context":"extra info","citations":{"enabled":true}})
    content = Crig::Providers::Anthropic::Content.from_json_value(JSON.parse(json))
    content.kind.document?.should be_true
    content.document_title.should eq("My Doc")
    content.document_context.should eq("extra info")
    content.document_citations_enabled.should be_true
  end
end

describe "Anthropic ANTHROPIC_RAW_CONTENT_KEY" do
  it "defines the raw content key constant" do
    Crig::Providers::Anthropic::ANTHROPIC_RAW_CONTENT_KEY.should eq("anthropic_content")
  end
end
