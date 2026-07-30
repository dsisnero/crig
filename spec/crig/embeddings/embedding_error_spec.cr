require "../../spec_helper"

module Crig::Embeddings
  describe EmbeddingError do
    it "unsupported_parameter" do
      err = EmbeddingError.unsupported_parameter("openai", "encoding_format")
      err.kind.unsupported_parameter?.should be_true
      err.provider.should eq("openai")
      err.parameter.should eq("encoding_format")
      err.message.to_s.should contain("openai")
      err.message.to_s.should contain("encoding_format")
    end

    it "invalid_parameter_value" do
      err = EmbeddingError.invalid_parameter_value("together", "dimensions", "must be ≤ 2048")
      err.kind.invalid_parameter_value?.should be_true
      err.provider.should eq("together")
      err.parameter.should eq("dimensions")
      err.requirement.should eq("must be ≤ 2048")
    end

    it "unsupported_response_encoding" do
      err = EmbeddingError.unsupported_response_encoding("openai", "base64")
      err.kind.unsupported_response_encoding?.should be_true
      err.provider.should eq("openai")
      err.encoding_format.should eq("base64")
      err.message.to_s.should contain("base64")
    end

    it "missing_usage" do
      err = EmbeddingError.missing_usage("openai")
      err.kind.missing_usage?.should be_true
      err.provider.should eq("openai")
      err.message.to_s.should contain("openai")
    end
  end
end
