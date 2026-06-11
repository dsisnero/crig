require "json"

module Crig
  module Completion
    class CompletionError < Exception
      enum Kind
        HttpError
        JsonError
        UrlError
        RequestError
        ResponseError
        ProviderError
        Other
      end

      getter kind : Kind
      getter source_error : Exception?

      def initialize(message : String, @kind : Kind = Kind::Other, @source_error : Exception? = nil)
        super(message)
      end

      def self.http_error(error : Exception) : self
        new("HttpError: #{error.message || error.class.name}", Kind::HttpError, error)
      end

      def self.json_error(error : Exception) : self
        new("JsonError: #{error.message || error.class.name}", Kind::JsonError, error)
      end

      def self.url_error(error : Exception) : self
        new("UrlError: #{error.message || error.class.name}", Kind::UrlError, error)
      end

      def self.request_error(error : Exception) : self
        new("RequestError: #{error.message || error.class.name}", Kind::RequestError, error)
      end

      def self.response_error(message : String) : self
        new("ResponseError: #{message}", Kind::ResponseError)
      end

      def self.provider_error(message : String) : self
        new("ProviderError: #{message}", Kind::ProviderError)
      end
    end

    class PromptError < Exception
      enum Kind
        CompletionError
        ToolError
        ToolServerError
        MaxTurnsError
        PromptCancelled
        UnknownToolCall
        Other
      end

      getter kind : Kind
      getter chat_history : Array(Message)?
      getter prompt : Message?
      getter max_turns : Int32?
      getter reason : String?
      getter completion_error : CompletionError?
      getter tool_error : Crig::ToolSetError?
      getter tool_server_error : Crig::ToolServerError?
      getter tool_name : String?
      getter available_tools : Array(String)?
      getter allowed_tools : Array(String)?

      def initialize(
        message : String,
        @kind : Kind = Kind::Other,
        @chat_history : Array(Message)? = nil,
        @prompt : Message? = nil,
        @max_turns : Int32? = nil,
        @reason : String? = nil,
        @completion_error : CompletionError? = nil,
        @tool_error : Crig::ToolSetError? = nil,
        @tool_server_error : Crig::ToolServerError? = nil,
        @tool_name : String? = nil,
        @available_tools : Array(String)? = nil,
        @allowed_tools : Array(String)? = nil,
      )
        super(message)
      end

      def self.completion_error(error : CompletionError) : self
        new("CompletionError: #{error.message}", Kind::CompletionError, completion_error: error)
      end

      def self.tool_error(error : Crig::ToolSetError) : self
        new("ToolCallError: #{error.message}", Kind::ToolError, tool_error: error)
      end

      def self.tool_server_error(error : Crig::ToolServerError) : self
        new("ToolServerError: #{error.message}", Kind::ToolServerError, tool_server_error: error)
      end

      def self.prompt_cancelled(chat_history : Array(Message), reason : String) : self
        new("PromptCancelled: #{reason}", Kind::PromptCancelled, chat_history: chat_history, reason: reason)
      end

      def self.max_turns_exceeded(max_turns : Int32, chat_history : Array(Message), prompt : Message) : self
        reason = "MaxTurnsExceeded: #{max_turns}"
        new(
          reason,
          Kind::MaxTurnsError,
          chat_history: chat_history,
          prompt: prompt,
          max_turns: max_turns,
          reason: reason,
        )
      end

      def self.unknown_tool_call(
        tool_name : String,
        available_tools : Array(String),
        allowed_tools : Array(String),
        chat_history : Array(Message),
      ) : self
        msg = "UnknownToolCall: #{tool_name} (available: #{available_tools.join(", ")}, allowed: #{allowed_tools.join(", ")})"
        new(
          msg,
          Kind::UnknownToolCall,
          chat_history: chat_history,
          tool_name: tool_name,
          available_tools: available_tools,
          allowed_tools: allowed_tools,
        )
      end
    end

    class StructuredOutputError < Exception
      enum Kind
        PromptError
        DeserializationError
        EmptyResponse
        Other
      end

      getter kind : Kind
      getter prompt_error : PromptError?
      getter source_error : Exception?

      def initialize(
        message : String,
        @kind : Kind = Kind::Other,
        @prompt_error : PromptError? = nil,
        @source_error : Exception? = nil,
      )
        super(message)
      end

      def self.prompt_error(error : PromptError) : self
        new("PromptError: #{error.message}", Kind::PromptError, prompt_error: error, source_error: error)
      end

      def self.deserialization_error(error : Exception) : self
        new("DeserializationError: #{error.message || error.class.name}", Kind::DeserializationError, source_error: error)
      end

      def self.empty_response : self
        new("EmptyResponse: model returned no content", Kind::EmptyResponse)
      end
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
      abstract def prompt_typed(type : T.class, prompt : Message | String) forall T
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
      include GetTokenUsage

      getter input_tokens : Int64
      getter output_tokens : Int64
      getter total_tokens : Int64
      getter cached_input_tokens : Int64
      getter cache_creation_input_tokens : Int64
      getter reasoning_tokens : Int64
      getter tool_use_prompt_tokens : Int64

      def initialize(
        @input_tokens : Int64 = 0,
        @output_tokens : Int64 = 0,
        @total_tokens : Int64 = 0,
        @cached_input_tokens : Int64 = 0,
        @cache_creation_input_tokens : Int64 = 0,
        @reasoning_tokens : Int64 = 0,
        @tool_use_prompt_tokens : Int64 = 0,
      )
      end

      def self.new(pull : JSON::PullParser)
        input_tokens = 0_i64
        output_tokens = 0_i64
        total_tokens = 0_i64
        cached_input_tokens = 0_i64
        cache_creation = 0_i64
        reasoning = 0_i64
        tool_use_prompt_tokens = 0_i64

        pull.read_object do |key|
          case key
          when "input_tokens"          then input_tokens = pull.read_int.to_i64
          when "output_tokens"         then output_tokens = pull.read_int.to_i64
          when "total_tokens"          then total_tokens = pull.read_int.to_i64
          when "cached_input_tokens"   then cached_input_tokens = pull.read_int.to_i64
          when "cache_creation_input_tokens" then cache_creation = pull.read_int.to_i64
          when "reasoning_tokens"      then reasoning = pull.read_int.to_i64
          when "tool_use_prompt_tokens" then tool_use_prompt_tokens = pull.read_int.to_i64
          else pull.skip
          end
        end

        new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens,
          cached_input_tokens: cached_input_tokens,
          cache_creation_input_tokens: cache_creation,
          reasoning_tokens: reasoning,
          tool_use_prompt_tokens: tool_use_prompt_tokens,
        )
      end

      def token_usage : Usage?
        self
      end

      def +(other : self) : self
        self.class.new(
          input_tokens: @input_tokens + other.input_tokens,
          output_tokens: @output_tokens + other.output_tokens,
          total_tokens: @total_tokens + other.total_tokens,
          cached_input_tokens: @cached_input_tokens + other.cached_input_tokens,
          cache_creation_input_tokens: @cache_creation_input_tokens + other.cache_creation_input_tokens,
          reasoning_tokens: @reasoning_tokens + other.reasoning_tokens,
          tool_use_prompt_tokens: @tool_use_prompt_tokens + other.tool_use_prompt_tokens,
        )
      end

      def add!(other : self) : self
        @input_tokens += other.input_tokens
        @output_tokens += other.output_tokens
        @total_tokens += other.total_tokens
        @cached_input_tokens += other.cached_input_tokens
        @cache_creation_input_tokens += other.cache_creation_input_tokens
        @reasoning_tokens += other.reasoning_tokens
        @tool_use_prompt_tokens += other.tool_use_prompt_tokens
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
    def self.allowed_tool_names_for_choice(executable_tool_names : Enumerable(String), tool_choice : ToolChoice?) : Set(String)
      case tool_choice
      when nil
        Set.new(executable_tool_names)
      when .none?
        Set(String).new
      when .auto?, .required?
        Set.new(executable_tool_names)
      when .specific?
        names = tool_choice.function_names
        Set.new(names)
      else
        Set(String).new
      end
    end

    def self.validate_tool_call_name?(
      tool_name : String,
      executable_tool_names : Enumerable(String),
      allowed_tool_names : Enumerable(String),
      chat_history : Array(Message),
    ) : PromptError?
      return nil if allowed_tool_names.includes?(tool_name)

      PromptError.unknown_tool_call(
        tool_name,
        executable_tool_names.to_a,
        allowed_tool_names.to_a,
        chat_history,
      )
    end
  end
end

require "./completion/message"
require "./completion/request"
