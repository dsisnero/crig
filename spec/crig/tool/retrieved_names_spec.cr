require "../../spec_helper"

module Crig
  describe ToolSetBuilder do
    it "retrieved_tool adds embedding-backed tool" do
      tool = SimpleEmbeddingTool.new("add", "Adds", JSON.parse(%({"type":"object"})))
      builder = ToolSetBuilder.new.retrieved_tool(tool)
      ts = builder.build
      ts.contains("add").should be_true
    end

    it "retrieved_tool chains with static_tool" do
      adder = SimpleEmbeddingTool.new("add", "Adds", JSON.parse(%({"type":"object"})))
      tool = SimpleEchoTool2.new
      ts = ToolSetBuilder.new
        .static_tool(tool)
        .retrieved_tool(adder)
        .build
      ts.contains("echo").should be_true
      ts.contains("add").should be_true
    end
  end

  struct SimpleEchoTool2
    include ToolDyn

    def name : String
      "echo"
    end

    def description : String
      "Echo"
    end

    def parameters : JSON::Any
      JSON.parse(%({"type":"string"}))
    end

    def call(args : String) : String
      args
    end
  end

  struct SimpleEmbeddingTool
    include ToolEmbeddingDyn

    getter name : String
    getter description : String
    getter parameters : JSON::Any

    def initialize(@name : String, @description : String, @parameters : JSON::Any)
    end

    def call(args : String) : String
      args
    end

    def embedding_docs : Array(String)
      [@description]
    end

    def context : JSON::Any
      JSON.parse(%({}))
    end
  end
end
