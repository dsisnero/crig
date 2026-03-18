module Crig
  alias ToolResolver = String, String -> String

  UNKNOWN_AGENT_NAME = "Unnamed Agent"

  struct ToolServerHandle
    getter id : String

    def initialize(@id : String, @resolver : ToolResolver? = nil)
    end

    def self.with_resolver(id : String, resolver : ToolResolver) : self
      new(id, resolver)
    end

    def call_tool(name : String, arguments : String) : String
      resolver = @resolver
      raise "Tool server handle '#{@id}' has no resolver" unless resolver

      resolver.call(name, arguments)
    end
  end

  struct NoToolConfig
  end

  struct WithBuilderTools
    getter static_tools : Array(Crig::Completion::ToolDefinition)

    def initialize(@static_tools : Array(Crig::Completion::ToolDefinition) = [] of Crig::Completion::ToolDefinition)
    end
  end

  struct WithToolServerHandle
    getter handle : ToolServerHandle

    def initialize(@handle : ToolServerHandle)
    end
  end

  struct DynamicContextSource
    getter sample : Int32

    def initialize(@sample : Int32, @resolver : Crig::VectorSearchRequest -> Crig::TopNResults)
    end

    def search(request : Crig::VectorSearchRequest) : Crig::TopNResults
      @resolver.call(request)
    end
  end

  alias DynamicContextStore = Array(DynamicContextSource)

  struct DynamicToolSource
    getter sample : Int32
    getter tools : Array(Crig::Completion::ToolDefinition)

    def initialize(
      @sample : Int32,
      @tools : Array(Crig::Completion::ToolDefinition),
      @resolver : Crig::VectorSearchRequest -> Crig::TopNResults,
    )
    end

    def search(request : Crig::VectorSearchRequest) : Crig::TopNResults
      @resolver.call(request)
    end
  end

  struct Agent(M)
    getter model : M
    getter name : String?
    getter description : String?
    getter preamble : String?
    getter static_context : Array(Crig::Completion::Request::Document)
    getter dynamic_context : Array(DynamicContextSource)
    getter static_tools : Array(Crig::Completion::ToolDefinition)
    getter dynamic_tools : Array(DynamicToolSource)
    getter tool_server_handle : ToolServerHandle?
    getter additional_params : JSON::Any?
    getter max_tokens : Int64?
    getter default_max_turns : Int32?
    getter temperature : Float64?
    getter tool_choice : Crig::Completion::ToolChoice?
    getter output_schema : JSON::Any?

    def initialize(
      @model : M,
      @name : String? = nil,
      @description : String? = nil,
      @preamble : String? = nil,
      @static_context : Array(Crig::Completion::Request::Document) = [] of Crig::Completion::Request::Document,
      @dynamic_context : Array(DynamicContextSource) = [] of DynamicContextSource,
      @static_tools : Array(Crig::Completion::ToolDefinition) = [] of Crig::Completion::ToolDefinition,
      @dynamic_tools : Array(DynamicToolSource) = [] of DynamicToolSource,
      @tool_server_handle : ToolServerHandle? = nil,
      @additional_params : JSON::Any? = nil,
      @max_tokens : Int64? = nil,
      @default_max_turns : Int32? = nil,
      @temperature : Float64? = nil,
      @tool_choice : Crig::Completion::ToolChoice? = nil,
      @output_schema : JSON::Any? = nil,
    )
    end

    def resolved_name : String
      @name || UNKNOWN_AGENT_NAME
    end

    def completion(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message) = [] of Crig::Completion::Message,
    ) : Crig::Completion::Request::CompletionRequestBuilder
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt

      builder = @model.completion_request(prompt_message)
        .messages(chat_history)
        .temperature_opt(@temperature)
        .max_tokens_opt(@max_tokens)
        .additional_params_opt(@additional_params)
        .output_schema_opt(@output_schema)
        .documents(@static_context)
        .tools(@static_tools)

      builder = if preamble = @preamble
                  builder.preamble(preamble)
                else
                  builder
                end

      builder = if tool_choice = @tool_choice
                  builder.tool_choice(tool_choice)
                else
                  builder
                end

      rag_text = prompt_message.rag_text || begin
        text = nil
        chat_history.reverse_each do |message|
          if candidate = message.rag_text
            text = candidate
            break
          end
        end
        text
      end
      return builder unless rag_text

      builder.documents(dynamic_context_documents(rag_text))
        .tools(dynamic_tool_definitions(rag_text))
    end

    def stream_completion(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message) = [] of Crig::Completion::Message,
    ) : Crig::Completion::Request::CompletionRequestBuilder
      completion(prompt, chat_history)
    end

    def prompt(prompt : Crig::Completion::Message | String) : Crig::PromptRequest(Crig::Standard, M)
      Crig::PromptRequest(Crig::Standard, M).from_agent(self, prompt)
    end

    def chat(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : String
      self.prompt(prompt).with_history(chat_history).send
    end

    def prompt_typed(type : T.class, prompt : Crig::Completion::Message | String) : Crig::TypedPromptRequest(T, Crig::Standard, M) forall T
      Crig::TypedPromptRequest(T, Crig::Standard, M).from_agent(self, prompt)
    end

    def stream_prompt(prompt : Crig::Completion::Message | String) : Crig::StreamingPromptRequest(M)
      Crig::StreamingPromptRequest(M).from_agent(self, prompt)
    end

    def stream_chat(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : Crig::StreamingPromptRequest(M)
      stream_prompt(prompt).with_history(chat_history)
    end

    private def dynamic_context_documents(text : String) : Array(Crig::Completion::Request::Document)
      @dynamic_context.flat_map do |source|
        request = Crig::VectorSearchRequest.new(text, source.sample.to_u64)
        source.search(request).map do |_, id, document|
          Crig::Completion::Request::Document.new(id, document.to_s)
        end
      end
    end

    private def dynamic_tool_definitions(text : String) : Array(Crig::Completion::ToolDefinition)
      tool_map = {} of String => Crig::Completion::ToolDefinition

      @dynamic_tools.each do |source|
        request = Crig::VectorSearchRequest.new(text, source.sample.to_u64)
        next if source.search(request).empty?

        source.tools.each do |tool|
          tool_map[tool.name] = tool
        end
      end

      tool_map.values
    end
  end

  struct AgentBuilder(M)
    getter model : M
    getter name_value : String?
    getter description_value : String?
    getter preamble_value : String?
    getter static_context_value : Array(Crig::Completion::Request::Document)
    getter dynamic_context_value : Array(DynamicContextSource)
    getter static_tools_value : Array(Crig::Completion::ToolDefinition)
    getter dynamic_tools_value : Array(DynamicToolSource)
    getter tool_server_handle_value : ToolServerHandle?
    getter additional_params_value : JSON::Any?
    getter max_tokens_value : Int64?
    getter default_max_turns_value : Int32?
    getter temperature_value : Float64?
    getter tool_choice_value : Crig::Completion::ToolChoice?
    getter output_schema_value : JSON::Any?

    def initialize(
      @model : M,
      @name_value : String? = nil,
      @description_value : String? = nil,
      @preamble_value : String? = nil,
      @static_context_value : Array(Crig::Completion::Request::Document) = [] of Crig::Completion::Request::Document,
      @dynamic_context_value : Array(DynamicContextSource) = [] of DynamicContextSource,
      @static_tools_value : Array(Crig::Completion::ToolDefinition) = [] of Crig::Completion::ToolDefinition,
      @dynamic_tools_value : Array(DynamicToolSource) = [] of DynamicToolSource,
      @tool_server_handle_value : ToolServerHandle? = nil,
      @additional_params_value : JSON::Any? = nil,
      @max_tokens_value : Int64? = nil,
      @default_max_turns_value : Int32? = nil,
      @temperature_value : Float64? = nil,
      @tool_choice_value : Crig::Completion::ToolChoice? = nil,
      @output_schema_value : JSON::Any? = nil,
    )
    end

    def name(name : String) : self
      self.class.new(@model, name, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def description(description : String) : self
      self.class.new(@model, @name_value, description, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def preamble(preamble : String) : self
      self.class.new(@model, @name_value, @description_value, preamble, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def without_preamble : self
      self.class.new(@model, @name_value, @description_value, nil, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def append_preamble(doc : String) : self
      current = @preamble_value || ""
      self.class.new(@model, @name_value, @description_value, "#{current}\n#{doc}", @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def context(doc : String) : self
      document = Crig::Completion::Request::Document.new(
        "static_doc_#{@static_context_value.size}",
        doc,
      )
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value + [document], @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def dynamic_context(sample : Int32, dynamic_context) : self
      resolver = ->(request : Crig::VectorSearchRequest) do
        dynamic_context.top_n_results(request)
      end
      source = DynamicContextSource.new(sample, resolver)
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value + [source], @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def tool(tool : Crig::Completion::ToolDefinition) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value + [tool], @dynamic_tools_value, nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def tools(tools : Array(Crig::Completion::ToolDefinition)) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value + tools, @dynamic_tools_value, nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def dynamic_tools(sample : Int32, dynamic_tools, tools : Array(Crig::Completion::ToolDefinition)) : self
      resolver = ->(request : Crig::VectorSearchRequest) do
        dynamic_tools.top_n_results(request)
      end
      source = DynamicToolSource.new(sample, tools, resolver)
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value + [source], nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def tool_server_handle(handle : ToolServerHandle) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, handle, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def additional_params(params : JSON::Any) : self
      merged = @additional_params_value ? Crig::JSONUtils.merge(@additional_params_value.as(JSON::Any), params) : params
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, merged, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def max_tokens(max_tokens : Int64) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, max_tokens, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def default_max_turns(default_max_turns : Int32) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, default_max_turns, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def temperature(temperature : Float64) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, temperature, @tool_choice_value, @output_schema_value)
    end

    def tool_choice(tool_choice : Crig::Completion::ToolChoice) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, tool_choice, @output_schema_value)
    end

    def output_schema(output_schema : JSON::Any) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, output_schema)
    end

    def build : Agent(M)
      Agent(M).new(
        @model,
        name: @name_value,
        description: @description_value,
        preamble: @preamble_value,
        static_context: @static_context_value,
        dynamic_context: @dynamic_context_value,
        static_tools: @static_tools_value,
        dynamic_tools: @dynamic_tools_value,
        tool_server_handle: @tool_server_handle_value,
        additional_params: @additional_params_value,
        max_tokens: @max_tokens_value,
        default_max_turns: @default_max_turns_value,
        temperature: @temperature_value,
        tool_choice: @tool_choice_value,
        output_schema: @output_schema_value,
      )
    end
  end
end
