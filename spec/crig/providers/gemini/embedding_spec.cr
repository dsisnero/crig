require "../../../spec_helper"

describe Crig::Providers::Gemini::EmbeddingModel do
  it "knows upstream default dimensionalities" do
    Crig::Providers::Gemini::EmbeddingModel.model_default_ndims(Crig::Providers::Gemini::EMBEDDING_001).should eq(3072)
    Crig::Providers::Gemini::EmbeddingModel.model_default_ndims(Crig::Providers::Gemini::EMBEDDING_004).should eq(768)
    Crig::Providers::Gemini::EmbeddingModel.model_default_ndims("unknown-model").should be_nil
  end

  it "resolves default dimensions through make and client helpers" do
    client = Crig::Providers::Gemini::Client.new("test-key")

    Crig::Providers::Gemini::EmbeddingModel.make(client, Crig::Providers::Gemini::EMBEDDING_001, nil).ndims.should eq(3072)
    client.embedding_model(Crig::Providers::Gemini::EMBEDDING_004).ndims.should eq(768)
    Crig::Providers::Gemini::EmbeddingModel.make(client, "some-future-model", nil).ndims.should eq(768)
  end

  it "respects explicit dimensions and direct construction" do
    client = Crig::Providers::Gemini::Client.new("test-key")

    Crig::Providers::Gemini::EmbeddingModel.make(client, Crig::Providers::Gemini::EMBEDDING_001, 256).ndims.should eq(256)
    Crig::Providers::Gemini::EmbeddingModel.new(client, Crig::Providers::Gemini::EMBEDDING_001, 512).ndims.should eq(512)
  end
end
