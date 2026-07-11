require "../../spec_helper"

module Crig
  describe ProviderResponseHelpers do
    it "CompletionError responds to provider_response helpers" do
      err = Completion::CompletionError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "CompletionError returns nil for non-provider-response errors" do
      err = Completion::CompletionError.http_error(Exception.new("network failure"))
      err.provider_response_body.should be_nil
      err.provider_response_status.should be_nil
    end

    it "CompletionError.from_provider_body works without status" do
      err = Completion::CompletionError.from_provider_body("error body")
      err.provider_response_body.should eq("error body")
      err.provider_response_status.should be_nil
    end

    it "EmbeddingError responds to provider_response helpers" do
      err = Embeddings::EmbeddingError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "TranscriptionError responds to provider_response helpers" do
      err = TranscriptionError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "ImageGenerationError responds to provider_response helpers" do
      err = ImageGenerationError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "AudioGenerationError responds to provider_response helpers" do
      err = AudioGenerationError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "VerifyError responds to provider_response helpers" do
      err = Client::VerifyError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "RerankError responds to provider_response helpers" do
      err = RerankError.from_http_response(200, "ok")
      err.provider_response_body.should eq("ok")
      err.provider_response_status.should eq(200)
    end

    it "provider_response_json parses body as JSON" do
      err = Completion::CompletionError.from_http_response(200, %({"key":"value"}))
      json = err.provider_response_json
      json.should_not be_nil
      json.not_nil!["key"].as_s.should eq("value")
    end

    it "provider_response_json returns nil on empty body" do
      err = Completion::CompletionError.from_http_response(200, "")
      err.provider_response_json.should be_nil
    end
  end
end
