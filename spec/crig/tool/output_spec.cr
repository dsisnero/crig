require "../../spec_helper"

module Crig::Tool
  describe ToolOutput do
    it "json_shaped_strings_remain_literal_text" do
      text = %({"type":"image","data":"not-an-envelope"})
      output = ToolOutput.text(text)
      output.as_text.should eq(text)
      output.as_json.should be_nil
    end

    it "structured_values_remain_json" do
      value = JSON.parse(%({"status": "ok", "count": 2}))
      output = ToolOutput.json(value)
      output.as_json.should eq(value)
      output.as_text.should be_nil
      output.render.should eq(value.to_json)
    end

    it "explicit_json_string_is_distinct_from_literal_text" do
      json_val = JSON::Any.new("hello")
      json_output = ToolOutput.json(json_val)
      text_output = ToolOutput.text("hello")

      json_output.as_json.should eq(json_val)
      json_output.as_text.should be_nil

      text_output.as_text.should eq("hello")
      text_output.as_json.should be_nil
    end

    it "singleton_plain_content_has_one_canonical_representation" do
      ToolOutput.text("hello").should eq(ToolOutput.one(Crig::Completion::ToolResultContent.text("hello")))
      json_val = JSON.parse(%({"ok": true}))
      ToolOutput.json(json_val).should eq(ToolOutput.one(Crig::Completion::ToolResultContent.json(json_val)))
    end

    it "direct_ordered_content_is_not_serialized_as_json" do
      content = Crig::OneOrMany(Crig::Completion::ToolResultContent).many([
        Crig::Completion::ToolResultContent.text("before"),
        Crig::Completion::ToolResultContent.text("after"),
      ])
      output = ToolOutput.content(content)
      output.as_content.should eq(content)
    end

    it "debug_does_not_leak_content" do
      output = ToolOutput.content(
        Crig::OneOrMany(Crig::Completion::ToolResultContent).many([
          Crig::Completion::ToolResultContent.text("secret-tool-output"),
          Crig::Completion::ToolResultContent.json(JSON.parse(%({"credential": "secret-json-output"}))),
        ]).not_nil!
      )
      debug = output.to_s
      debug.should_not contain("secret-tool-output")
      debug.should_not contain("secret-json-output")
    end

    it "render_returns_text_for_text_output" do
      output = ToolOutput.text("hello world")
      output.render.should eq("hello world")
    end

    it "render_returns_json_string_for_json_output" do
      value = JSON.parse(%({"key": "value"}))
      output = ToolOutput.json(value)
      output.render.should eq(value.to_json)
    end
  end
end
