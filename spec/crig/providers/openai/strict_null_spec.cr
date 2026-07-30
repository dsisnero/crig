require "../../../spec_helper"

module Crig::Providers::OpenAI
  # Test JSON helper with required fields and optional strict.
  def self.tool_json(strict_value = nil)
    base = %({"type":"function","name":"get_weather","description":"Get the weather","parameters":{}})
    case strict_value
    when nil
      base
    when "null"
      %({"type":"function","name":"get_weather","description":"Get the weather","parameters":{},"strict":null})
    else
      %({"type":"function","name":"get_weather","description":"Get the weather","parameters":{},"strict":#{strict_value}})
    end
  end

  describe ResponsesToolDefinition do
    it "accepts strict: true" do
      tool = ResponsesToolDefinition.from_json(tool_json(true))
      tool.strict?.should be_true
      tool.name.should eq("get_weather")
    end

    it "accepts strict: false" do
      tool = ResponsesToolDefinition.from_json(tool_json(false))
      tool.strict?.should be_false
    end

    it "accepts strict: null as false" do
      tool = ResponsesToolDefinition.from_json(tool_json("null"))
      tool.strict?.should be_false
    end

    it "accepts missing strict as false" do
      tool = ResponsesToolDefinition.from_json(tool_json)
      tool.strict?.should be_false
    end
  end
end
