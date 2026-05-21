module Crig
  module Providers
    module Llamafile
      LLAMAFILE_API_BASE_URL = "http://localhost:8080"
      LLAMA_CPP              = "LLaMA_CPP"

      struct LlamafileExt
      end

      struct LlamafileBuilder
      end

      struct Client
        getter completions_client : Crig::Providers::OpenAI::CompletionsClient
        getter responses_client : Crig::Providers::OpenAI::Client

        def initialize(@completions_client : Crig::Providers::OpenAI::CompletionsClient, @responses_client : Crig::Providers::OpenAI::Client)
        end

        def self.from_url(base_url : String) : self
          builder.base_url(base_url).build
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          from_url(ENV["LLAMAFILE_API_BASE_URL"]? || LLAMAFILE_API_BASE_URL)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def embedding_model(model : String) : EmbeddingModel
          EmbeddingModel.new(self, model)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end
      end

      struct ClientBuilder
        getter base_url : String

        def initialize(@base_url : String = LLAMAFILE_API_BASE_URL)
        end

        def base_url(base_url : String) : self
          self.class.new(base_url)
        end

        def build : Client
          completions = Crig::Providers::OpenAI::CompletionsClient.new("llamafile", "#{@base_url.rstrip('/')}/v1")
          responses = Crig::Providers::OpenAI::Client.new("llamafile", "#{@base_url.rstrip('/')}/v1")
          Client.new(completions, responses)
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.current
          span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "chat")
          span.set_attribute(Crig::Telemetry::GEN_AI_PROVIDER_NAME, "llamafile")
          span.set_attribute(Crig::Telemetry::GEN_AI_REQUEST_MODEL, @model)
          if preamble = request.preamble
            span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
          end

          result = @client.completions_client.completion_model(@model).completion(request)
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @client.completions_client.completion_model(@model).stream(request)
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : Crig::Providers::OpenAI::OpenAIUsage

        def initialize(@usage : Crig::Providers::OpenAI::OpenAIUsage = Crig::Providers::OpenAI::OpenAIUsage.new)
        end

        def token_usage : Crig::Completion::Usage?
          @usage.to_crig_usage
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32 = 0)
        end

        def self.make(client : Client, model : String, ndims : Int32?) : self
          new(client, model, ndims || 0)
        end

        def max_documents : Int32
          1024
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          model = if @ndims > 0
                    @client.responses_client.embedding_model_with_ndims(@model, @ndims)
                  else
                    @client.responses_client.embedding_model(@model)
                  end
          model.embed_texts(texts)
        end
      end
    end
  end
end
