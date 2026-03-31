module Crig
  module Client
    class DynClientBuilderError < Exception
      def self.not_found(provider : String) : self
        new("Provider '#{provider}' not found")
      end

      def self.not_capable(provider : String, role : String) : self
        new("Provider '#{provider}' cannot be coerced to a '#{role}'")
      end

      def self.completion(message : String) : self
        new("Error generating response\n#{message}")
      end
    end

    enum DefaultProviders : UInt8
      Anthropic
      Cohere
      Gemini
      HuggingFace
      OpenAI
      OpenRouter
      Together
      XAI
      Azure
      DeepSeek
      Galadriel
      Groq
      Hyperbolic
      Moonshot
      Mira
      Mistral
      Ollama
      Perplexity

      def provider_name : String
        self.class.provider_names[to_i]
      end

      def to_s : String
        provider_name
      end

      def to_s(io : IO) : Nil
        io << provider_name
      end

      def self.all : Array(self)
        values
      end

      def self.provider_names
        {
          "anthropic",
          "cohere",
          "gemini",
          "huggingface",
          "openai",
          "openrouter",
          "together",
          "xai",
          "azure",
          "deepseek",
          "galadriel",
          "groq",
          "hyperbolic",
          "moonshot",
          "mira",
          "mistral",
          "ollama",
          "perplexity",
        }
      end

      def env_factory : ProviderFactory
        factory = case self
                  in .anthropic?
                    -> { AnyClient.new(Crig::Providers::Anthropic::Client.from_env) }
                  in .cohere?
                    -> { AnyClient.new(Crig::Providers::Cohere::Client.from_env) }
                  in .gemini?
                    -> { AnyClient.new(Crig::Providers::Gemini::Client.from_env) }
                  in .hugging_face?
                    -> { AnyClient.new(Crig::Providers::HuggingFace::Client.from_env) }
                  in .open_ai?
                    -> { AnyClient.new(Crig::Providers::OpenAI::Client.from_env) }
                  in .open_router?
                    -> { AnyClient.new(Crig::Providers::OpenRouter::Client.from_env) }
                  in .together?
                    -> { AnyClient.new(Crig::Providers::Together::Client.from_env) }
                  in .xai?
                    -> { AnyClient.new(Crig::Providers::XAI::Client.from_env) }
                  in .azure?
                    -> { AnyClient.new(Crig::Providers::Azure::Client.from_env) }
                  in .deep_seek?
                    -> { AnyClient.new(Crig::Providers::DeepSeek::Client.from_env) }
                  in .galadriel?
                    -> { AnyClient.new(Crig::Providers::Galadriel::Client.from_env) }
                  in .groq?
                    -> { AnyClient.new(Crig::Providers::Groq::Client.from_env) }
                  in .hyperbolic?
                    -> { AnyClient.new(Crig::Providers::Hyperbolic::Client.from_env) }
                  in .moonshot?
                    -> { AnyClient.new(Crig::Providers::Moonshot::Client.from_env) }
                  in .mira?
                    -> { AnyClient.new(Crig::Providers::Mira::Client.from_env) }
                  in .mistral?
                    -> { AnyClient.new(Crig::Providers::Mistral::Client.from_env) }
                  in .ollama?
                    -> { AnyClient.new(Crig::Providers::Ollama::Client.from_env) }
                  in .perplexity?
                    -> { AnyClient.new(Crig::Providers::Perplexity::Client.from_env) }
                  end

        ProviderFactory.new(factory)
      end
    end

    class AnyClient
      getter completion : Crig::CompletionClientDyn?
      getter embeddings : Crig::EmbeddingsClientDyn?
      getter transcription : Crig::TranscriptionClientDyn?
      getter image_generation : Crig::ImageGenerationClientDyn?
      getter audio_generation : Crig::AudioGenerationClientDyn?

      def initialize(
        @completion : Crig::CompletionClientDyn? = nil,
        @embeddings : Crig::EmbeddingsClientDyn? = nil,
        @transcription : Crig::TranscriptionClientDyn? = nil,
        @image_generation : Crig::ImageGenerationClientDyn? = nil,
        @audio_generation : Crig::AudioGenerationClientDyn? = nil,
      )
      end

      def self.new(client)
        new(
          completion: client.as?(Crig::CompletionClientDyn),
          embeddings: client.as?(Crig::EmbeddingsClientDyn),
          transcription: client.as?(Crig::TranscriptionClientDyn),
          image_generation: client.as?(Crig::ImageGenerationClientDyn),
          audio_generation: client.as?(Crig::AudioGenerationClientDyn),
        )
      end

      def as_completion : Crig::CompletionClientDyn?
        @completion
      end

      def as_embedding : Crig::EmbeddingsClientDyn?
        @embeddings
      end

      def as_transcription : Crig::TranscriptionClientDyn?
        @transcription
      end

      def as_image_generation : Crig::ImageGenerationClientDyn?
        @image_generation
      end

      def as_audio_generation : Crig::AudioGenerationClientDyn?
        @audio_generation
      end
    end

    struct ProviderFactory
      getter from_env : Proc(AnyClient)

      def initialize(@from_env : Proc(AnyClient))
      end
    end

    struct DynClientBuilder
      getter factories : Hash(String, ProviderFactory)

      def initialize(@factories : Hash(String, ProviderFactory) = self.class.default_factories)
      end

      def register(provider_name : String, model : String, &from_env : -> AnyClient) : self
        key = self.class.to_key(provider_name, model)
        self.class.new(@factories.merge({key => ProviderFactory.new(from_env)}))
      end

      def factory(provider_name : String, model : String) : ProviderFactory?
        @factories[self.class.to_key(provider_name, model)]? || @factories[provider_name]?
      end

      def from_env(provider_name : String, model : String) : AnyClient
        factory(provider_name, model).try(&.from_env.call) ||
          raise DynClientBuilderError.not_found(self.class.to_key(provider_name, model))
      end

      def agent(provider_name : String, model : String) : Crig::AgentBuilder(Crig::CompletionModelHandle)
        key = self.class.to_key(provider_name, model)
        completion = from_env(provider_name, model).as_completion ||
                     raise DynClientBuilderError.not_capable(key, "Completion")
        completion.agent(model)
      end

      def completion(provider_name : String, model : String) : Crig::Completion::CompletionModelDyn
        key = self.class.to_key(provider_name, model)
        completion = from_env(provider_name, model).as_completion ||
                     raise DynClientBuilderError.not_capable(key, "Embedding Model")
        completion.completion_model(model)
      end

      def embeddings(provider_name : String, model : String) : Crig::EmbeddingModelDyn
        key = self.class.to_key(provider_name, model)
        embeddings = from_env(provider_name, model).as_embedding ||
                     raise DynClientBuilderError.not_capable(key, "Embedding Model")
        embeddings.embedding_model(model)
      end

      def transcription(provider_name : String, model : String) : Crig::TranscriptionModelDyn
        key = self.class.to_key(provider_name, model)
        transcription = from_env(provider_name, model).as_transcription ||
                        raise DynClientBuilderError.not_capable(key, "transcription model")
        transcription.transcription_model(model)
      end

      def image_generation(provider_name : String, model : String) : Crig::ImageGenerationModelDyn
        key = self.class.to_key(provider_name, model)
        image_generation = from_env(provider_name, model).as_image_generation ||
                           raise DynClientBuilderError.not_capable(key, "Image generation")
        image_generation.image_generation_model(model)
      end

      def audio_generation(provider_name : String, model : String) : Crig::AudioGenerationModelDyn
        key = self.class.to_key(provider_name, model)
        audio_generation = from_env(provider_name, model).as_audio_generation ||
                           raise DynClientBuilderError.not_capable(key, "Image generation")
        audio_generation.audio_generation_model(model)
      end

      def stream_completion(
        provider_name : String,
        model : String,
        request : Crig::Completion::Request::CompletionRequest,
      ) : Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse)
        completion(provider_name, model).stream(request)
      end

      def stream_prompt(
        provider_name : String,
        model : String,
        prompt : Crig::Completion::Message | String,
      ) : Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse)
        message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt

        request = Crig::Completion::Request::CompletionRequest.new(
          Crig::OneOrMany(Crig::Completion::Message).one(message),
        )

        stream_completion(provider_name, model, request)
      end

      def stream_chat(
        provider_name : String,
        model : String,
        prompt : Crig::Completion::Message | String,
        history : Array(Crig::Completion::Message),
      ) : Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse)
        message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
        messages = history + [message]
        chat_history = if messages.empty?
                         Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user(""))
                       else
                         Crig::OneOrMany(Crig::Completion::Message).many(messages)
                       end

        request = Crig::Completion::Request::CompletionRequest.new(chat_history)
        stream_completion(provider_name, model, request)
      end

      def self.to_key(provider_name : String, model : String) : String
        "#{provider_name}:#{model}"
      end

      def self.default_factories : Hash(String, ProviderFactory)
        factories = {} of String => ProviderFactory
        DefaultProviders.all.each do |provider|
          factories[provider.provider_name] = provider.env_factory
        end
        factories
      end
    end
  end
end
