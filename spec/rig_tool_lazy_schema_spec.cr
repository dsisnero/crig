require "./spec_helper"

module Crig
  describe "Tool schema memoization" do
    it "memoized parameters returns the correct schema" do
      tool = SimpleEchoMemoizedTool.new
      params = tool.parameters
      params["type"].should eq("string")
    end
  end

  struct SimpleEchoMemoizedTool
    include Tool(String, String)

    def name : String
      "echo"
    end

    def description : String
      "Echo"
    end

    def parameters : JSON::Any
      @parameters ||= JSON.parse(%({"type":"string"}))
    end

    def call_typed(args : String) : String
      args
    end
  end
end
