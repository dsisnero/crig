require "../../spec_helper"

module Crig::Embeddings
  describe EmbeddingModel do
    it "FakeEmbeddingModel embed_texts returns embeddings" do
      model = FakeEmbeddingModel.new
      results = model.embed_texts(["hello", "world"])
      results.size.should eq(2)
      results[0].document.should eq("hello")
      results[0].vec.size.should eq(3)
      results[1].document.should eq("world")
    end

    it "FakeEmbeddingModel embed_text returns single embedding" do
      model = FakeEmbeddingModel.new
      result = model.embed_text("hello")
      result.document.should eq("hello")
    end

    it "FakeEmbeddingModel embed_texts_with_usage returns usage" do
      model = FakeEmbeddingModel.new
      response = model.embed_texts_with_usage(["hello"])
      response.embeddings.size.should eq(1)
      response.usage.should be_a(Crig::Completion::Usage)
    end

    it "FakeEmbeddingModel ndims returns correct dimensions" do
      model = FakeEmbeddingModel.new
      model.ndims.should eq(3)
    end

    it "FakeEmbeddingModel max_documents returns limit" do
      model = FakeEmbeddingModel.new
      model.max_documents.should eq(2)
    end
  end

  describe Embedding do
    it "equality compares only document name" do
      e1 = Embedding.new("doc1", [1.0, 2.0])
      e2 = Embedding.new("doc1", [3.0, 4.0])
      e1.should eq(e2)
    end

    it "inequality detects different document names" do
      e1 = Embedding.new("doc1", [1.0, 2.0])
      e2 = Embedding.new("doc2", [1.0, 2.0])
      e1.should_not eq(e2)
    end
  end

  describe EmbeddingResponse do
    it "stores embeddings and usage" do
      emb = [Embedding.new("doc", [1.0])]
      usage = Crig::Completion::Usage.new(input_tokens: 5, output_tokens: 3)
      response = EmbeddingResponse.new(emb, usage)
      response.embeddings.size.should eq(1)
      response.usage.input_tokens.should eq(5)
      response.usage.output_tokens.should eq(3)
    end
  end
end
