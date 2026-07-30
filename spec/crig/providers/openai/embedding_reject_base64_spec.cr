require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe EmbeddingModel do
    it "rejects base64 encoding format before HTTP call" do
      client = Crig::Providers::OpenAI::Client.new("sk-test")

      model = EmbeddingModel.new(
        client,
        TEXT_EMBEDDING_3_SMALL,
        1536,
        EncodingFormat::Base64,
      )

      expect_raises(Crig::Embeddings::EmbeddingError) do
        model.embed_texts(["hello"])
      end
    end

    it "accepts float encoding format" do
      client = Crig::Providers::OpenAI::Client.new("sk-test")

      model = EmbeddingModel.new(
        client,
        TEXT_EMBEDDING_3_SMALL,
        1536,
        EncodingFormat::Float,
      )

      model.encoding_format.should eq(EncodingFormat::Float)
    end
  end
end
