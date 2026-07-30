require "../spec_helper"

module Crig
  describe "Extractor submit tool name collision" do
    it "agent builder raises on tool named 'submit'" do
      model = FakeCompletionModel.new
      builder = AgentBuilder(typeof(model)).new(model)
      builder = builder.tool(Crig::Completion::ToolDefinition.new("submit", "Submits", JSON.parse(%({"type":"object"}))))

      expect_raises(Exception, /submit/) do
        builder.build
      end
    end

    it "agent builder raises on ToolDyn with name 'submit'" do
      model = FakeCompletionModel.new
      builder = AgentBuilder(typeof(model)).new(model)
      builder = builder.tool(SubmitCollisionTool.new)

      expect_raises(Exception, /submit/) do
        builder.build
      end
    end

    it "agent builder accepts a tool named 'other'" do
      model = FakeCompletionModel.new
      builder = AgentBuilder(typeof(model)).new(model)
      builder = builder.tool(Crig::Completion::ToolDefinition.new("other", "Other", JSON.parse(%({"type":"object"}))))
      agent = builder.build
      agent.static_tools.size.should eq(1)
    end
  end

  struct SubmitCollisionTool
    include Crig::ToolDyn

    def name : String
      "submit"
    end

    def description : String
      "Submit"
    end

    def parameters : JSON::Any
      JSON.parse(%({"type":"object"}))
    end

    def call(args : String) : String
      args
    end
  end
end
