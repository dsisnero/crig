module Crig
  module Providers
    module Internal
      module EmbeddingCompatible
        record Config,
          provider_name : String,
          requires_usage : Bool = true,
          supports_encoding_format : Bool = true,
          supports_user : Bool = true,
          embeddings_path : String = "/embeddings"

        def self.build_request(
          model : String,
          documents : Array(String),
          ndims : Int32,
          encoding_format : String?,
          user : String?,
          config : Config,
        ) : String
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", model
              json.field "input" do
                json.array do
                  documents.each { |document| json.string(document) }
                end
              end
              if ndims > 0
                json.field "dimensions", ndims
              end
              if enc = encoding_format
                json.field "encoding_format", enc
              end
              if u = user
                json.field "user", u
              end
            end
          end.to_json
        end

        def self.parse_response(body : String, documents : Array(String), config : Config = Config.new(provider_name: "openai")) : Array(Crig::Embeddings::Embedding)
          parse_response_with_usage(body, documents, config).embeddings
        end

        def self.parse_response_with_usage(body : String, documents : Array(String), config : Config) : Crig::Embeddings::EmbeddingResponse
          parsed = JSON.parse(body)
          if error = parsed["error"]?
            raise Crig::Embeddings::EmbeddingError.new(error["message"].as_s)
          end

          data = parsed["data"]?.try(&.as_a?) || raise Crig::Embeddings::EmbeddingError.new("Response data is missing")
          if data.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embeddings = data.zip(documents).map do |embedding_json, document|
            embedding = Crig::Providers::OpenAI::EmbeddingData.from_json(embedding_json.to_json)
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end

          usage = if raw_usage = parsed["usage"]?
                    Crig::Providers::OpenAI::OpenAIUsage.from_json(raw_usage.to_json).to_crig_usage
                  elsif config.requires_usage
                    raise Crig::Embeddings::EmbeddingError.missing_usage(config.provider_name)
                  else
                    Crig::Completion::Usage.new
                  end

          Crig::Embeddings::EmbeddingResponse.new(embeddings, usage)
        end

        def self.validate_parameters(
          encoding_format : String?,
          user : String?,
          config : Config,
        ) : Nil
          if encoding_format == "base64"
            raise Crig::Embeddings::EmbeddingError.unsupported_response_encoding(config.provider_name, "base64")
          end

          if encoding_format && !config.supports_encoding_format
            raise Crig::Embeddings::EmbeddingError.unsupported_parameter(config.provider_name, "encoding_format")
          end

          if user && !config.supports_user
            raise Crig::Embeddings::EmbeddingError.unsupported_parameter(config.provider_name, "user")
          end
        end

        def self.check_response_status(status_code : Int32, body : String, config : Config) : Nil
          if status_code >= 400
            raise Crig::Embeddings::EmbeddingError.new(body)
          end
        end
      end
    end
  end
end
