require "../../../spec_helper"

module Crig::Providers::Internal
  describe EmbeddingCompatible do
    describe ".build_request" do
      it "includes model and input" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        json = EmbeddingCompatible.build_request("test-model", ["hello", "world"], 0, nil, nil, config)
        parsed = JSON.parse(json)
        parsed["model"].as_s.should eq("test-model")
        parsed["input"].as_a.map(&.as_s).should eq(["hello", "world"])
      end

      it "includes dimensions when > 0" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        json = EmbeddingCompatible.build_request("test-model", ["hello"], 256, nil, nil, config)
        parsed = JSON.parse(json)
        parsed["dimensions"].as_i.should eq(256)
      end

      it "omits dimensions when 0" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        json = EmbeddingCompatible.build_request("test-model", ["hello"], 0, nil, nil, config)
        parsed = JSON.parse(json)
        parsed.as_h.has_key?("dimensions").should be_false
      end

      it "includes encoding_format when set" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        json = EmbeddingCompatible.build_request("test-model", ["hello"], 0, "float", nil, config)
        parsed = JSON.parse(json)
        parsed["encoding_format"].as_s.should eq("float")
      end

      it "includes user when set" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        json = EmbeddingCompatible.build_request("test-model", ["hello"], 0, nil, "user-abc", config)
        parsed = JSON.parse(json)
        parsed["user"].as_s.should eq("user-abc")
      end
    end

    describe ".parse_response" do
      it "returns embeddings from valid response" do
        body = %({"object":"list","data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],"model":"test","usage":{"prompt_tokens":1,"total_tokens":1}})
        results = EmbeddingCompatible.parse_response(body, ["hello"])
        results.size.should eq(1)
        results[0].document.should eq("hello")
        results[0].vec.should eq([0.1_f64, 0.2_f64])
      end

      it "raises on error payload" do
        body = %({"error":{"message":"API error"}})
        expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.parse_response(body, ["hello"])
        end
      end

      it "raises on data length mismatch" do
        body = %({"object":"list","data":[],"model":"test","usage":{"prompt_tokens":0,"total_tokens":0}})
        expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.parse_response(body, ["hello"])
        end
      end
    end

    describe ".parse_response_with_usage" do
      it "surfaces provider-reported usage" do
        body = %({"object":"list","data":[{"object":"embedding","embedding":[0.1],"index":0}],"model":"test","usage":{"prompt_tokens":2,"completion_tokens":0,"total_tokens":2}})
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        response = EmbeddingCompatible.parse_response_with_usage(body, ["hello"], config)
        response.embeddings.size.should eq(1)
        response.usage.total_tokens.should eq(2)
        response.usage.input_tokens.should eq(2)
      end

      it "raises MissingUsage when usage required but absent" do
        body = %({"object":"list","data":[{"object":"embedding","embedding":[0.1],"index":0}],"model":"test"})
        config = EmbeddingCompatible::Config.new(provider_name: "test", requires_usage: true)
        expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.parse_response_with_usage(body, ["hello"], config)
        end
      end

      it "returns zero usage when not required and absent" do
        body = %({"object":"list","data":[{"object":"embedding","embedding":[0.1],"index":0}],"model":"test"})
        config = EmbeddingCompatible::Config.new(provider_name: "test", requires_usage: false)
        response = EmbeddingCompatible.parse_response_with_usage(body, ["hello"], config)
        response.usage.total_tokens.should eq(0)
      end
    end

    describe ".validate_parameters" do
      it "rejects base64 encoding format" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        error = expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.validate_parameters("base64", nil, config)
        end
        error.to_s.should contain("base64")
      end

      it "rejects unsupported encoding format" do
        config = EmbeddingCompatible::Config.new(provider_name: "test", supports_encoding_format: false)
        error = expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.validate_parameters("float", nil, config)
        end
        error.to_s.should contain("encoding_format")
      end

      it "rejects unsupported user parameter" do
        config = EmbeddingCompatible::Config.new(provider_name: "test", supports_user: false)
        error = expect_raises(Crig::Embeddings::EmbeddingError) do
          EmbeddingCompatible.validate_parameters(nil, "user-1", config)
        end
        error.to_s.should contain("user")
      end

      it "accepts supported parameters" do
        config = EmbeddingCompatible::Config.new(provider_name: "test")
        EmbeddingCompatible.validate_parameters("float", "user-1", config)
      end
    end
  end
end
