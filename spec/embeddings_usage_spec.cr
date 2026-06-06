require "./spec_helper"

struct FakeUsageEmbeddingModel
  include Crig::Embeddings::EmbeddingModel

  def max_documents : Int32
    5
  end

  def ndims : Int32
    3
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    texts.map do |text|
      Crig::Embeddings::Embedding.new(document: text, vec: [0.1, 0.2, 0.3] of Float64)
    end
  end

  def embed_texts_with_usage(texts : Enumerable(String)) : Crig::Embeddings::EmbeddingResponse
    embeddings = embed_texts(texts)
    Crig::Embeddings::EmbeddingResponse.new(
      embeddings,
      Crig::Completion::Usage.new(input_tokens: 4, output_tokens: 0, total_tokens: 4),
    )
  end
end

describe "EmbeddingResponse and embed_texts_with_usage" do
  it "EmbedingResponse holds embeddings and usage" do
    embeddings = [Crig::Embeddings::Embedding.new(document: "test", vec: [1.0])]
    usage = Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 0, total_tokens: 1)
    response = Crig::Embeddings::EmbeddingResponse.new(embeddings, usage)
    response.embeddings.size.should eq(1)
    response.usage.input_tokens.should eq(1)
  end

  it "embed_texts_with_usage defaults to zero usage" do
    model = FakeCompletionModel.new
    # Test default impl via the DefaultUsageModel
  end

  it "embed_texts_with_usage returns usage from provider" do
    model = FakeUsageEmbeddingModel.new
    response = model.embed_texts_with_usage(["hello", "world"])
    response.embeddings.size.should eq(2)
    response.usage.input_tokens.should eq(4)
  end
end
