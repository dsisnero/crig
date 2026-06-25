module Crig
  alias ToolResolver = String, String -> String

  UNKNOWN_AGENT_NAME = "Unnamed Agent"
  AGENT_TOOL_NAME    = "agent_tool"

  struct AgentToolArgs
    include JSON::Serializable

    getter prompt : String

    def initialize(@prompt : String)
    end
  end

  struct ToolServerHandle
    getter id : String

    def initialize(
      @id : String,
      @resolver : ToolResolver? = nil,
      @server : Crig::ToolServer? = nil,
      @inbox : Channel(Crig::ToolServerRequest)? = nil,
    )
    end

    def close : Nil
      @inbox.try(&.close)
    end

    def self.with_resolver(id : String, resolver : ToolResolver) : self
      new(id, resolver)
    end

    def call_tool(name : String, arguments : String) : String
      if response = request(Crig::ToolServerRequestMessageKind.call_tool(name, arguments))
        if response.kind.tool_executed?
          result = response.result
          return result if result
        end
        if response.kind.tool_error? && (error = response.error)
          raise Crig::ToolServerError.toolset_error(Crig::ToolSetError.tool_call_error(Exception.new(error)))
        end
        raise Crig::ToolServerError.invalid_message(response)
      end

      resolver = @resolver
      raise Crig::ToolServerError.send_error("Tool server handle '#{@id}' has no resolver") unless resolver

      resolver.call(name, arguments)
    end

    def add_tool(tool : Crig::ToolDyn) : Nil
      if server = @server
        response = server.add_tool(tool)
        raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_added?
        return
      end

      response = request(Crig::ToolServerRequestMessageKind.add_tool(tool)) ||
                 raise Crig::ToolServerError.send_error("Tool server handle '#{@id}' is not attached to a server")
      raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_added?
    end

    def append_toolset(toolset : Crig::ToolSet) : Nil
      if server = @server
        response = server.append_toolset(toolset)
        raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_added?
        return
      end

      response = request(Crig::ToolServerRequestMessageKind.append_toolset(toolset)) ||
                 raise Crig::ToolServerError.send_error("Tool server handle '#{@id}' is not attached to a server")
      raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_added?
    end

    def remove_tool(tool_name : String) : Nil
      if server = @server
        response = server.remove_tool(tool_name)
        raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_deleted?
        return
      end

      response = request(Crig::ToolServerRequestMessageKind.remove_tool(tool_name)) ||
                 raise Crig::ToolServerError.send_error("Tool server handle '#{@id}' is not attached to a server")
      raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_deleted?
    end

    def get_tool_defs(prompt : String?) : Array(Crig::Completion::ToolDefinition)
      response = request(Crig::ToolServerRequestMessageKind.get_tool_defs(prompt)) ||
                 raise Crig::ToolServerError.send_error("Tool server handle '#{@id}' is not attached to a server")
      definitions = response.tool_definitions
      raise Crig::ToolServerError.invalid_message(response) unless response.kind.tool_definitions? && definitions
      definitions
    end

    private def request(kind : Crig::ToolServerRequestMessageKind) : Crig::ToolServerResponse?
      if inbox = @inbox
        reply_channel = Channel(Crig::ToolServerResponse).new(1)
        begin
          inbox.send(Crig::ToolServerRequest.new(kind, reply_channel))
        rescue Channel::ClosedError
          raise Crig::ToolServerError.send_error("Tool server inbox is closed")
        end

        begin
          return reply_channel.receive
        rescue Channel::ClosedError
          raise Crig::ToolServerError.canceled
        end
      end

      if server = @server
        return server.handle_message(Crig::ToolServerRequest.new(kind))
      end

      nil
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

  struct OutputSchemaBuilder(T)
    def self.build : JSON::Any
      JSON.parse(
        JSON.build do |json|
          json.object do
            {% begin %}
              Crig::ToolMacro.json_schema_for({{ @type.type_vars[0] }})
            {% end %}
          end
        end
      )
    end
  end

  struct Agent(M)
    include StreamingPrompt(M)
    include StreamingChat(M)
    include StreamingCompletion(M)

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
    getter memory : Crig::Memory::ConversationMemory?
    getter default_conversation_id : String?
    getter hook : Crig::PromptHook?

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
      @memory : Crig::Memory::ConversationMemory? = nil,
      @default_conversation_id : String? = nil,
      @hook : Crig::PromptHook? = nil,
    )
    end

    def resolved_name : String
      @name || UNKNOWN_AGENT_NAME
    end

    def name : String
      @name || AGENT_TOOL_NAME
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name,
        "Prompt a sub-agent to do a task for you.\n\nAgent name: #{resolved_name}\nAgent description: #{@description || ""}\nAgent system prompt: #{@preamble || ""}",
        JSON.parse(%({"type":"object","properties":{"prompt":{"type":"string","description":"The prompt for the agent to call."}},"required":["prompt"]})),
      )
    end

    def call(args : Crig::AgentToolArgs) : String
      prompt(args.prompt).send
    end

    def call(args : String) : String
      parsed = Crig::AgentToolArgs.from_json(args)
      call(parsed)
    rescue ex : JSON::ParseException | JSON::SerializableError
      raise Crig::ToolError.json_error(ex)
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

    def prompt(prompt : Crig::Completion::Image | Crig::Completion::Audio | Crig::Completion::Document | Crig::Completion::UserContent) : Crig::PromptRequest(Crig::Standard, M)
      prompt(Crig::Completion::Message.from(prompt))
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

    def stream_prompt(prompt : Crig::Completion::Image | Crig::Completion::Audio | Crig::Completion::Document | Crig::Completion::UserContent) : Crig::StreamingPromptRequest(M)
      stream_prompt(Crig::Completion::Message.from(prompt))
    end

    def stream_chat(
      prompt : Crig::Completion::Message | String,
      chat_history : Array(Crig::Completion::Message),
    ) : Crig::StreamingPromptRequest(M)
      stream_prompt(prompt).with_history(chat_history)
    end

    private def dynamic_context_documents(text : String) : Array(Crig::Completion::Request::Document)
      Crig::Concurrency.flat_map_ordered(@dynamic_context) do |source|
        request = Crig::VectorSearchRequest.new(text, source.sample.to_u64)
        source.search(request).map do |_, id, document|
          Crig::Completion::Request::Document.new(id, document.to_s)
        end
      end
    end

    private def dynamic_tool_definitions(text : String) : Array(Crig::Completion::ToolDefinition)
      tool_map = {} of String => Crig::Completion::ToolDefinition

      matches = Crig::Concurrency.map_ordered(@dynamic_tools) do |source|
        request = Crig::VectorSearchRequest.new(text, source.sample.to_u64)
        source.search(request).empty? ? nil : source.tools
      end

      matches.each do |tools|
        next unless tools
        tools.each do |tool|
          tool_map[tool.name] = tool
        end
      end

      tool_map.values
    end
  end

  struct AgentToolAdapter(M)
    include Crig::ToolDyn

    getter agent : Agent(M)

    def initialize(@agent : Agent(M))
    end

    def name : String
      @agent.name
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      @agent.definition(prompt)
    end

    def call(args : String) : String
      @agent.call(args)
    end
  end

  # Builder for the core agent runtime.
  # AgentBuilder is the main ergonomic surface for composing preambles, context,
  # tools, dynamic retrieval, output schemas, and generation parameters before
  # producing a concrete Agent.
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
    getter memory_value : Crig::Memory::ConversationMemory?
    getter default_conversation_id_value : String?
    getter hook_value : Crig::PromptHook?

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
      @memory_value : Crig::Memory::ConversationMemory? = nil,
      @default_conversation_id_value : String? = nil,
      @hook_value : Crig::PromptHook? = nil,
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

    # Add static context that will be normalized into request documents.
    def context(doc : String) : self
      document = Crig::Completion::Request::Document.new(
        "static_doc_#{@static_context_value.size}",
        doc,
      )
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value + [document], @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    # Register a dynamic context source queried at prompt time.
    def dynamic_context(sample : Int32, dynamic_context) : self
      resolver = ->(request : Crig::VectorSearchRequest) do
        dynamic_context.top_n_results(request)
      end
      source = DynamicContextSource.new(sample, resolver)
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value + [source], @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    # Add a tool definition directly without an executable runtime implementation.
    def tool(tool : Crig::Completion::ToolDefinition) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value + [tool], @dynamic_tools_value, nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    # Add an executable tool and route it through the shared tool server runtime.
    def tool(tool : Crig::ToolDyn) : self
      handle = tool_server_handle_for_builder
      handle.add_tool(tool)
      self.class.new(
        @model,
        @name_value,
        @description_value,
        @preamble_value,
        @static_context_value,
        @dynamic_context_value,
        @static_tools_value + [tool.definition("")],
        @dynamic_tools_value,
        handle,
        @additional_params_value,
        @max_tokens_value,
        @default_max_turns_value,
        @temperature_value,
        @tool_choice_value,
        @output_schema_value,
      )
    end

    # Add a nested agent as a callable tool.
    def tool(tool : Crig::Agent(T)) : self forall T
      adapter = Crig::AgentToolAdapter(T).new(tool)
      handle = tool_server_handle_for_builder
      handle.add_tool(adapter)
      self.class.new(
        @model,
        @name_value,
        @description_value,
        @preamble_value,
        @static_context_value,
        @dynamic_context_value,
        @static_tools_value + [adapter.definition("")],
        @dynamic_tools_value,
        handle,
        @additional_params_value,
        @max_tokens_value,
        @default_max_turns_value,
        @temperature_value,
        @tool_choice_value,
        @output_schema_value,
      )
    end

    def tools(tools : Array(Crig::Completion::ToolDefinition)) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value + tools, @dynamic_tools_value, nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def tools(tools : Array(Crig::ToolDyn)) : self
      handle = tool_server_handle_for_builder
      tools.each { |tool| handle.add_tool(tool) }
      self.class.new(
        @model,
        @name_value,
        @description_value,
        @preamble_value,
        @static_context_value,
        @dynamic_context_value,
        @static_tools_value + tools.map(&.definition("")),
        @dynamic_tools_value,
        handle,
        @additional_params_value,
        @max_tokens_value,
        @default_max_turns_value,
        @temperature_value,
        @tool_choice_value,
        @output_schema_value,
      )
    end

    def tools(tools : Array(Crig::Agent(T))) : self forall T
      handle = tool_server_handle_for_builder
      adapters = tools.map { |tool| Crig::AgentToolAdapter(T).new(tool) }
      adapters.each { |tool| handle.add_tool(tool) }
      self.class.new(
        @model,
        @name_value,
        @description_value,
        @preamble_value,
        @static_context_value,
        @dynamic_context_value,
        @static_tools_value + adapters.map(&.definition("")),
        @dynamic_tools_value,
        handle,
        @additional_params_value,
        @max_tokens_value,
        @default_max_turns_value,
        @temperature_value,
        @tool_choice_value,
        @output_schema_value,
      )
    end

    def rmcp_tool(tool : MCP::Protocol::Tool, client : MCP::Client::Client) : self
      handle = tool_server_handle_for_builder
      handle.add_tool(Crig::McpTool.from_mcp_server(tool, client))
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, handle, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    def rmcp_tools(tools : Array(MCP::Protocol::Tool), client : MCP::Client::Client) : self
      handle = tool_server_handle_for_builder
      tools.each do |tool|
        handle.add_tool(Crig::McpTool.from_mcp_server(tool, client))
      end
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, handle, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    # Register a dynamic tool source queried from vector search at prompt time.
    def dynamic_tools(sample : Int32, dynamic_tools, tools : Array(Crig::Completion::ToolDefinition)) : self
      resolver = ->(request : Crig::VectorSearchRequest) do
        dynamic_tools.top_n_results(request)
      end
      source = DynamicToolSource.new(sample, tools, resolver)
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value + [source], nil, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    # Register a dynamic tool source queried from vector search at prompt time
    # using the same ToolSet-oriented surface as the upstream Rust builder.
    def dynamic_tools(sample : Int32, dynamic_tools, toolset : Crig::ToolSet) : self
      dynamic_tools(sample, dynamic_tools, toolset.get_tool_definitions)
    end

    def tool_server_handle(handle : ToolServerHandle) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, handle, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value)
    end

    private def tool_server_handle_for_builder : ToolServerHandle
      @tool_server_handle_value || Crig::ToolServer.new.run
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

    # Build a JSON schema from a Crystal type for structured output requests.
    def output_schema(type : T.class) : self forall T
      _ = type
      output_schema(Crig::OutputSchemaBuilder(T).build)
    end

    # Attach a ConversationMemory backend.
    # When set, the agent will automatically load prior conversation history before
    # sending a prompt and append new messages after a successful turn. A
    # conversation_id must be supplied either via #conversation_id on the builder
    # or per-request via PromptRequest#conversation. If neither is set, memory is
    # silently bypassed.
    def memory(memory : Crig::Memory::ConversationMemory) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value, memory, @default_conversation_id_value)
    end

    # Set a default conversation id used when none is provided per-request.
    # Can be overridden per-request via PromptRequest#conversation.
    def conversation_id(id : String) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value, @memory_value, id)
    end

    def hook(hook : Crig::PromptHook) : self
      self.class.new(@model, @name_value, @description_value, @preamble_value, @static_context_value, @dynamic_context_value, @static_tools_value, @dynamic_tools_value, @tool_server_handle_value, @additional_params_value, @max_tokens_value, @default_max_turns_value, @temperature_value, @tool_choice_value, @output_schema_value, @memory_value, @default_conversation_id_value, hook)
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
        memory: @memory_value,
        default_conversation_id: @default_conversation_id_value,
        hook: @hook_value,
      )
    end
  end
end
