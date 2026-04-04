module Crig
  module Client
    struct FinalCompletionResponse
      include JSON::Serializable
      include Crig::Completion::GetTokenUsage

      getter usage : Crig::Completion::Usage?

      def initialize(@usage : Crig::Completion::Usage? = nil)
      end

      def token_usage : Crig::Completion::Usage?
        @usage
      end
    end

    # Shared client mixin for completion-capable providers.
    # This is the ergonomic entry point used throughout the repo:
    # choose a model, then branch into an agent or extractor builder.
    module CompletionClient(M)
      abstract def completion_model(model : String) : M

      # Build an agent directly from a provider client and model identifier.
      def agent(model : String) : Crig::AgentBuilder(M)
        Crig::AgentBuilder(M).new(completion_model(model))
      end

      # Build a structured extractor directly from a provider client and model identifier.
      def extractor(type : T.class, model : String) : Crig::ExtractorBuilder(M, T) forall T
        Crig::ExtractorBuilder(M, T).new(completion_model(model))
      end
    end

    # Dynamic completion client surface used by the dyn-client builder.
    module CompletionClientDyn
      abstract def completion_model(model : String) : Crig::Completion::CompletionModelDyn

      # Dynamic clients still expose the same builder-first agent entry point.
      def agent(model : String) : Crig::AgentBuilder(Crig::Client::CompletionModelHandle)
        Crig::AgentBuilder(Crig::Client::CompletionModelHandle).new(
          Crig::Client::CompletionModelHandle.new(completion_model(model))
        )
      end
    end

    struct CompletionModelHandle
      include Crig::Completion::CompletionModel

      getter inner : Crig::Completion::CompletionModelDyn

      def self.make(_client, _model) : self
        raise "Cannot create a completion model handle from a client"
      end

      def self.new(inner : Crig::Completion::CompletionModelDyn) : self
        allocate.tap(&.initialize(inner))
      end

      def initialize(@inner : Crig::Completion::CompletionModelDyn)
      end

      def completion(request : Crig::Completion::Request::CompletionRequest)
        @inner.completion(request)
      end

      def stream(request : Crig::Completion::Request::CompletionRequest)
        @inner.stream(request)
      end

      # Preserve the normal request-builder workflow for dynamically typed models.
      def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
        prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
        @inner.completion_request(prompt_message)
      end
    end
  end
end
