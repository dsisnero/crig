require "../../spec_helper"

module Crig::Embeddings
  describe ToolSchema do
    it "from ToolEmbeddingDyn preserves name, context, docs" do
      tool = TestEmbeddingTool.new
      schema = ToolSchema.try_from(tool)
      schema.name.should eq("test_tool")
      schema.context["key"].as_s.should eq("value")
      schema.embedding_docs.should eq(["doc1", "doc2"])
    end

    it "implements Embed and feeds docs to embedder" do
      tool = TestEmbeddingTool.new
      schema = ToolSchema.try_from(tool)
      embedder = TextEmbedder.new
      schema.embed(embedder)
      embedder.texts.should eq(["doc1", "doc2"])
    end
  end

  struct TestEmbeddingTool
    include ToolEmbeddingDyn

    def name : String
      "test_tool"
    end

    def context : JSON::Any
      JSON.parse(%({"key":"value"}))
    end

    def embedding_docs : Array(String)
      ["doc1", "doc2"]
    end

    def call(args : String) : String
      args
    end
  end
end
