require "json"

module Crig
  module Completion
    class CompletionError < Exception
    end

    class PromptError < Exception
      getter chat_history : Array(Message)?
      getter prompt : Message?
      getter max_turns : Int32?
      getter reason : String?

      def initialize(
        message : String,
        @chat_history : Array(Message)? = nil,
        @prompt : Message? = nil,
        @max_turns : Int32? = nil,
        @reason : String? = nil,
      )
        super(message)
      end

      def self.prompt_cancelled(chat_history : Array(Message), reason : String) : self
        new("PromptCancelled: #{reason}", chat_history: chat_history, reason: reason)
      end

      def self.max_turns_exceeded(max_turns : Int32, chat_history : Array(Message), prompt : Message) : self
        reason = "MaxTurnsExceeded: #{max_turns}"
        new(
          reason,
          chat_history: chat_history,
          prompt: prompt,
          max_turns: max_turns,
          reason: reason,
        )
      end
    end

    class StructuredOutputError < Exception
    end

    module GetTokenUsage
      abstract def token_usage : Usage?
    end

    module Prompt
      abstract def prompt(prompt : Message | String) : String
    end

    module Chat
      abstract def chat(prompt : Message | String, chat_history : Array(Message)) : String
    end

    module TypedPrompt
      abstract def prompt_typed(prompt : Message | String)
    end

    module Completion
      abstract def completion(prompt : Message | String, chat_history : Array(Message)) : Request::CompletionRequestBuilder
    end

    module CompletionModel
      abstract def completion(request : Request::CompletionRequest)
      abstract def stream(request : Request::CompletionRequest)
      abstract def completion_request(prompt : Message | String) : Request::CompletionRequestBuilder

      def completion_async(request : Request::CompletionRequest)
        Crig::Concurrency.run do
          completion(request)
        end
      end

      def stream_async(request : Request::CompletionRequest)
        Crig::Concurrency.run do
          stream(request)
        end
      end
    end

    module CompletionModelDyn
      abstract def completion(request : Request::CompletionRequest)
      abstract def stream(request : Request::CompletionRequest)
      abstract def completion_request(prompt : Message) : Request::CompletionRequestBuilder

      def completion_async(request : Request::CompletionRequest)
        Crig::Concurrency.run do
          completion(request)
        end
      end

      def stream_async(request : Request::CompletionRequest)
        Crig::Concurrency.run do
          stream(request)
        end
      end
    end

    struct ToolDefinition
      include JSON::Serializable

      getter name : String
      getter description : String
      getter parameters : JSON::Any

      def initialize(@name : String, @description : String, @parameters : JSON::Any)
      end
    end

    struct Usage
      include JSON::Serializable

      getter input_tokens : Int64
      getter output_tokens : Int64
      getter total_tokens : Int64
      getter cached_input_tokens : Int64

      def initialize(
        @input_tokens : Int64 = 0,
        @output_tokens : Int64 = 0,
        @total_tokens : Int64 = 0,
        @cached_input_tokens : Int64 = 0,
      )
      end

      def +(other : self) : self
        self.class.new(
          input_tokens: @input_tokens + other.input_tokens,
          output_tokens: @output_tokens + other.output_tokens,
          total_tokens: @total_tokens + other.total_tokens,
          cached_input_tokens: @cached_input_tokens + other.cached_input_tokens,
        )
      end

      def add!(other : self) : self
        @input_tokens += other.input_tokens
        @output_tokens += other.output_tokens
        @total_tokens += other.total_tokens
        @cached_input_tokens += other.cached_input_tokens
        self
      end
    end

    struct CompletionResponse(T)
      getter choice : Crig::OneOrMany(AssistantContent)
      getter usage : Usage
      getter raw_response : T
      getter message_id : String?

      def initialize(
        @choice : Crig::OneOrMany(AssistantContent),
        @usage : Usage,
        @raw_response : T,
        @message_id : String? = nil,
      )
      end
    end
  end
end

require "./completion/message"
require "./completion/request"
