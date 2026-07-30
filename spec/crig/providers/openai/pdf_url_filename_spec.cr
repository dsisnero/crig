require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe "URL-backed PDF in Responses API" do
    it "omits filename for URL-backed PDF" do
      doc = Crig::Completion::UserContent.document_url("https://example.com/doc.pdf", Crig::Completion::DocumentMediaType::PDF)
      msg = Crig::Completion::Message.user(doc)
      items = InputItem.from_completion_message(msg)
      items.size.should eq(1)
      json = items.first.to_json_value
      content = json["input"]?.try(&.["content"]?.try(&.[0]?)) || json["content"]?.try(&.[0]?) || json
      content["type"].as_s.should eq("input_file")
      content["file_url"].as_s.should eq("https://example.com/doc.pdf")
      content["filename"]?.try(&.raw).should be_nil
    end
  end
end
