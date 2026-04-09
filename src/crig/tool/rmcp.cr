require "mcp"

module Crig
  class McpClientError < Exception
    enum Kind
      ConnectionError
      ToolFetchError
      ToolServerError
    end

    getter kind : Kind

    def initialize(message : String, @kind : Kind = Kind::ConnectionError)
      super(message)
    end

    def self.connection_error(message : String) : self
      new("MCP connection error: #{message}", Kind::ConnectionError)
    end

    def self.tool_fetch_error(message : String) : self
      new("Failed to fetch MCP tool list: #{message}", Kind::ToolFetchError)
    end

    def self.tool_server_error(message : String) : self
      new("Tool server error: #{message}", Kind::ToolServerError)
    end
  end

  class McpToolError < Exception
    def initialize(message : String)
      super("MCP tool error: #{message}")
    end
  end

  class McpClientDispatcher
    alias ToolResult = MCP::Protocol::CallToolResult | MCP::Protocol::CompatibilityCallToolResult

    record Request,
      name : String,
      arguments : Hash(String, JSON::Any),
      compatibility : Bool,
      reply : Channel(ToolResult | Exception)

    @@dispatchers = {} of UInt64 => McpClientDispatcher
    @@dispatchers_lock = Mutex.new

    def self.for(client : MCP::Client::Client) : self
      key = client.object_id
      @@dispatchers_lock.synchronize do
        @@dispatchers[key] ||= new(client)
      end
    end

    def initialize(@client : MCP::Client::Client)
      @inbox = Channel(Request).new

      spawn do
        loop do
          request = @inbox.receive
          begin
            result = @client.call_tool(request.name, request.arguments, request.compatibility)
            request.reply.send(result)
          rescue ex : Exception
            request.reply.send(ex)
          end
        end
      end
    end

    def call_tool(
      name : String,
      arguments : Hash(String, JSON::Any),
      compatibility : Bool = false,
    ) : ToolResult
      reply = Channel(ToolResult | Exception).new(1)
      @inbox.send(Request.new(name, arguments, compatibility, reply))
      result = reply.receive
      raise result if result.is_a?(Exception)
      result.as(ToolResult)
    end
  end

  struct McpTool
    include Crig::ToolDyn

    getter mcp_definition : MCP::Protocol::Tool
    getter client : MCP::Client::Client

    def initialize(@mcp_definition : MCP::Protocol::Tool, @client : MCP::Client::Client)
    end

    def self.from_mcp_server(definition : MCP::Protocol::Tool, client : MCP::Client::Client) : self
      new(definition, client)
    end

    def self.to_tool_definition(definition : MCP::Protocol::Tool) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        definition.name,
        definition.description || "",
        JSON.parse(definition.input_schema.to_json)
      )
    end

    def name : String
      @mcp_definition.name
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      self.class.to_tool_definition(@mcp_definition)
    end

    def call(args : String) : String
      result = McpClientDispatcher.for(@client).call_tool(@mcp_definition.name, parse_arguments(args))
      tool_result = case result
                    when MCP::Protocol::CallToolResult, MCP::Protocol::CompatibilityCallToolResult
                      result
                    else
                      raise McpToolError.new("No message returned")
                    end
      content = tool_result.content

      if tool_result.is_error == true
        raise McpToolError.new(extract_error_message(content) || "No message returned")
      end

      String.build do |io|
        content.each do |block|
          io << render_content_block(block)
        end
      end
    rescue ex : McpToolError
      raise Crig::ToolError.tool_call_error(ex)
    rescue ex : Exception
      raise Crig::ToolError.tool_call_error(McpToolError.new("Tool returned an error: #{ex.message || ex.class.name}"))
    end

    private def parse_arguments(args : String) : Hash(String, JSON::Any)
      parsed = JSON.parse(args)
      parsed.as_h? || Hash(String, JSON::Any).new
    rescue JSON::ParseException
      Hash(String, JSON::Any).new
    end

    private def extract_error_message(content : Array(MCP::Protocol::ContentBlock)) : String?
      messages = content.map do |block|
        block.as?(MCP::Protocol::TextContentBlock).try(&.text)
      end

      return unless messages.all?(&.itself)

      messages.compact.join('\n')
    end

    private def render_content_block(block : MCP::Protocol::ContentBlock) : String
      case block
      when MCP::Protocol::TextContentBlock
        block.text
      when MCP::Protocol::ImageContentBlock
        "data:#{block.mime_type};base64,#{block.data}"
      when MCP::Protocol::EmbeddedResourceBlock
        render_resource(block.resource)
      when MCP::Protocol::AudioContentBlock
        raise "Support for audio results from an MCP tool is currently unimplemented. Come back later!"
      else
        raise "Unsupported type found: #{block.class}"
      end
    end

    private def render_resource(resource : MCP::Protocol::ResourceContents) : String
      mime_type_prefix = resource.mime_type.try { |mime_type| "data:#{mime_type};" } || ""

      case resource
      when MCP::Protocol::TextResourceContents
        "#{mime_type_prefix}#{resource.uri}:#{resource.text}"
      when MCP::Protocol::BlobResourceContents
        "#{mime_type_prefix}#{resource.uri}:#{resource.blob}"
      else
        raise "Unsupported resource type found: #{resource.class}"
      end
    end
  end

  class McpClientHandler
    getter client_info : MCP::Protocol::Implementation
    getter tool_server_handle : Crig::ToolServerHandle

    def initialize(@client_info : MCP::Protocol::Implementation, @tool_server_handle : Crig::ToolServerHandle)
    end

    def connect(transport : MCP::Shared::Transport) : MCP::Client::Client
      client = MCP::Client::Client.new(@client_info)
      client.connect(transport)

      tools = client.list_tools
      raise McpClientError.tool_fetch_error("No tool list returned") unless tools

      tools.tools.each do |tool|
        begin
          @tool_server_handle.add_tool(McpTool.from_mcp_server(tool, client))
        rescue ex
          raise McpClientError.tool_server_error(ex.message || ex.class.name)
        end
      end

      client
    rescue ex : McpClientError
      raise ex
    rescue ex
      raise McpClientError.connection_error(ex.message || ex.class.name)
    end
  end
end
