module Crig
  class ToolServerError < Exception
    def self.canceled : self
      new("Canceled")
    end

    def self.invalid_message(response : Crig::ToolServerResponse) : self
      new("InvalidMessage: #{response.kind}")
    end

    def self.toolset_error(error : Exception) : self
      new("ToolsetError: #{error.message || error.class.name}")
    end

    def self.send_error(error : Exception | String) : self
      message = error.is_a?(String) ? error : (error.message || error.class.name)
      new("SendError: #{message}")
    end
  end

  struct ToolServerRequest
    getter reply_channel : Channel(Crig::ToolServerResponse)?
    getter callback : (Crig::ToolServerResponse -> Nil)?
    getter data : ToolServerRequestMessageKind

    def initialize(
      @data : ToolServerRequestMessageKind,
      @reply_channel : Channel(Crig::ToolServerResponse)? = nil,
      @callback : (Crig::ToolServerResponse -> Nil)? = nil,
    )
    end
  end

  struct ToolServerResponse
    enum Kind
      ToolAdded
      ToolDeleted
      ToolExecuted
      ToolError
      ToolDefinitions
    end

    getter kind : Kind
    getter result : String?
    getter error : String?
    getter tool_definitions : Array(Crig::Completion::ToolDefinition)?

    def initialize(
      @kind : Kind,
      @result : String? = nil,
      @error : String? = nil,
      @tool_definitions : Array(Crig::Completion::ToolDefinition)? = nil,
    )
    end

    def self.tool_added : self
      new(Kind::ToolAdded)
    end

    def self.tool_deleted : self
      new(Kind::ToolDeleted)
    end

    def self.tool_executed(result : String) : self
      new(Kind::ToolExecuted, result: result)
    end

    def self.tool_error(error : String) : self
      new(Kind::ToolError, error: error)
    end

    def self.tool_definitions(definitions : Array(Crig::Completion::ToolDefinition)) : self
      new(Kind::ToolDefinitions, tool_definitions: definitions)
    end
  end

  struct ToolServerRequestMessageKind
    enum Kind
      AddTool
      AppendToolset
      RemoveTool
      CallTool
      GetToolDefs
    end

    getter kind : Kind
    getter tool : Crig::ToolDyn?
    getter toolset : Crig::ToolSet?
    getter tool_name : String?
    getter args : String?
    getter prompt : String?

    def initialize(
      @kind : Kind,
      @tool : Crig::ToolDyn? = nil,
      @toolset : Crig::ToolSet? = nil,
      @tool_name : String? = nil,
      @args : String? = nil,
      @prompt : String? = nil,
    )
    end

    def self.add_tool(tool : Crig::ToolDyn) : self
      new(Kind::AddTool, tool: tool)
    end

    def self.append_toolset(toolset : Crig::ToolSet) : self
      new(Kind::AppendToolset, toolset: toolset)
    end

    def self.remove_tool(tool_name : String) : self
      new(Kind::RemoveTool, tool_name: tool_name)
    end

    def self.call_tool(tool_name : String, args : String) : self
      new(Kind::CallTool, tool_name: tool_name, args: args)
    end

    def self.get_tool_defs(prompt : String?) : self
      new(Kind::GetToolDefs, prompt: prompt)
    end
  end

  class ToolServer
    getter static_tool_names : Array(String)
    getter toolset : Crig::ToolSet

    DEFAULT_TOOL_CONCURRENCY = {System.cpu_count, 1}.max

    def visible_tool_names : Array(String)
      @static_tool_names.dup
    end

    def initialize(
      @static_tool_names : Array(String) = [] of String,
      @dynamic_tools : Array(Tuple(Int32, Proc(Crig::VectorSearchRequest, Array(Tuple(Float64, String))))) = [] of Tuple(Int32, Proc(Crig::VectorSearchRequest, Array(Tuple(Float64, String)))),
      @toolset : Crig::ToolSet = Crig::ToolSet.new,
      @lock = Mutex.new,
      @max_concurrency : Int32 = DEFAULT_TOOL_CONCURRENCY,
    )
    end

    def self.new : self
      allocate.tap(&.initialize)
    end

    def static_tool_names(names : Array(String)) : self
      @static_tool_names = names.dup
      self
    end

    def add_tools(tools : Crig::ToolSet) : self
      @toolset = tools
      self
    end

    def add_dynamic_tools(
      dyn_tools : Array(Tuple(Int32, Proc(Crig::VectorSearchRequest, Array(Tuple(Float64, String))))),
    ) : self
      @dynamic_tools = dyn_tools.dup
      self
    end

    def tool(tool : T) : self forall T
      @toolset.add_tool(tool.as(Crig::ToolDyn))
      @static_tool_names << tool.name
      self
    end

    def rmcp_tool(tool : MCP::Protocol::Tool, client : MCP::Client::Client) : self
      @toolset.add_tool(Crig::McpTool.from_mcp_server(tool, client))
      @static_tool_names << tool.name
      self
    end

    def dynamic_tools(sample : Int, dynamic_tools, toolset : Crig::ToolSet) : self
      @dynamic_tools << {
        sample.to_i32,
        ->(request : Crig::VectorSearchRequest) {
          dynamic_tools.top_n_ids(request).map do |score, id|
            {score, id}
          end
        },
      }
      @toolset.add_tools(toolset)
      self
    end

    def with_max_concurrency(n : Int32) : self
      @max_concurrency = {n, 1}.max
      self
    end

    def run : Crig::ToolServerHandle
      inbox = Channel(Crig::ToolServerRequest).new(1000)
      slots = Channel(Bool).new(@max_concurrency)

      spawn do
        loop do
          message = inbox.receive
          if message.data.kind.call_tool?
            slots.send(true)
            spawn do
              begin
                handle_message(message)
              ensure
                slots.receive?
              end
            end
          else
            handle_message(message)
          end
        end
      rescue Channel::ClosedError
      end

      Crig::ToolServerHandle.new("tool-server", nil, self, inbox)
    end

    def handle_message(message : Crig::ToolServerRequest) : Crig::ToolServerResponse
      response = dispatch_message(message.data)

      if reply_channel = message.reply_channel
        reply_channel.send(response)
      end

      if callback = message.callback
        callback.call(response)
      end

      response
    end

    private def dispatch_message(data : Crig::ToolServerRequestMessageKind) : Crig::ToolServerResponse
      case data.kind
      when .add_tool?
        tool = data.tool || raise "missing tool"
        add_tool(tool)
      when .append_toolset?
        toolset = data.toolset || raise "missing toolset"
        append_toolset(toolset)
      when .remove_tool?
        tool_name = data.tool_name || raise "missing tool name"
        remove_tool(tool_name)
      when .call_tool?
        dispatch_tool_call(data)
      when .get_tool_defs?
        Crig::ToolServerResponse.tool_definitions(get_tool_definitions(data.prompt))
      else
        raise "unknown tool server request kind: #{data.kind}"
      end
    end

    private def dispatch_tool_call(data : Crig::ToolServerRequestMessageKind) : Crig::ToolServerResponse
      tool_name = data.tool_name || raise "missing tool name"
      args = data.args || raise "missing tool args"
      begin
        Crig::ToolServerResponse.tool_executed(call_tool(tool_name, args))
      rescue ex : Crig::ToolServerError
        Crig::ToolServerResponse.tool_error(ex.message || ex.class.name)
      end
    end

    def add_tool(tool : Crig::ToolDyn) : Crig::ToolServerResponse
      @lock.synchronize do
        @static_tool_names << tool.name
        @toolset.add_tool_boxed(tool)
      end
      Crig::ToolServerResponse.tool_added
    end

    def append_toolset(toolset : Crig::ToolSet) : Crig::ToolServerResponse
      @lock.synchronize do
        toolset.tools.each_key do |name|
          @static_tool_names << name unless @static_tool_names.includes?(name)
        end
        @toolset.add_tools(toolset)
      end
      Crig::ToolServerResponse.tool_added
    end

    def remove_tool(tool_name : String) : Crig::ToolServerResponse
      @lock.synchronize do
        @static_tool_names.reject! { |name| name == tool_name }
        @toolset.delete_tool(tool_name)
      end
      Crig::ToolServerResponse.tool_deleted
    end

    def call_tool(name : String, args : String) : String
      tool = @lock.synchronize do
        @toolset.get(name)
      end
      raise Crig::ToolServerError.toolset_error(Crig::ToolSetError.tool_not_found(name)) unless tool

      begin
        tool.call(args)
      rescue ex : Crig::ToolError
        raise Crig::ToolServerError.toolset_error(Crig::ToolSetError.tool_call_error(ex))
      end
    rescue ex : Crig::ToolSetError
      raise Crig::ToolServerError.toolset_error(ex)
    end

    def get_tool_definitions(text : String?) : Array(Crig::Completion::ToolDefinition)
      # Snapshot everything needed under one lock to avoid lock-storm.
      # The vector search runs outside the lock since it may involve I/O.
      dynamic_tools_snapshot, static_defs = @lock.synchronize do
        {
          @dynamic_tools.dup,
          @static_tool_names.map { |name| {name, @toolset.get(name)} }.to_a,
        }
      end

      tools = [] of Crig::Completion::ToolDefinition

      if query = text
        dynamic_tool_ids = Crig::Concurrency.flat_map_ordered(dynamic_tools_snapshot) do |sample, index|
          request = Crig::VectorSearchRequest.builder
            .query(query)
            .samples(sample.to_u64)
            .build
          index.call(request).map(&.[1])
        end

        dynamic_tool_ids.each do |id|
          # Re-check under lock since tool definitions may have changed during search.
          if tool = @lock.synchronize { @toolset.get(id) }
            tools << tool.definition(query)
          end
        end
      end

      static_defs.each do |_, tool|
        if tool
          tools << tool.definition("")
        end
      end

      tools
    end
  end
end
