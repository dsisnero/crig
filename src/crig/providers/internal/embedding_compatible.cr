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
          encoding_format : Crig::Providers::OpenAI::EncodingFormat?,
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
                json.field "encoding_format", enc.to_wire
              end
              if u = user
                json.field "user", u
              end
            end
          end.to_json
        end

        def self.parse_response(body : String, documents : Array(String)) : Array(Crig::Embeddings::Embedding)
          parsed = JSON.parse(body)
          if error = parsed["error"]?
            raise Crig::Embeddings::EmbeddingError.new(error["message"].as_s)
          end

          embedding_response = Crig::Providers::OpenAI::EmbeddingResponse.from_json(body)
          if embedding_response.data.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embedding_response.data.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
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
