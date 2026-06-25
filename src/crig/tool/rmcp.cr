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
      channel = call_async(args)
      result = channel.receive
      if result.success?
        result.unwrap
      else
        raise (result.error || McpToolError.new("MCP async error")).as(Exception)
      end
    end

    def call_async(args : String) : Channel(MCP::Shared::AsyncResult(String))
      name = @mcp_definition.name
      parsed_args = parse_arguments(args)
      raw_ch = @client.call_tool_async(name, parsed_args)

      result_ch = Channel(MCP::Shared::AsyncResult(String)).new(1)
      spawn do
        result_ch.send(render_async_result(raw_ch))
      ensure
        result_ch.close
      end
      result_ch
    end

    private def render_async_result(raw_ch : Channel(MCP::Shared::AsyncResult(MCP::Protocol::Result))) : MCP::Shared::AsyncResult(String)
      raw = raw_ch.receive
      unless raw.success?
        return MCP::Shared::AsyncResult(String).new(
          error: Crig::ToolError.tool_call_error(
            McpToolError.new(raw.error.try(&.message) || "MCP async error")
          )
        )
      end

      raw_result = raw.unwrap
      tool_result = case raw_result
                    when MCP::Protocol::CallToolResult, MCP::Protocol::CompatibilityCallToolResult
                      raw_result
                    else
                      raise McpToolError.new("Unexpected MCP result type")
                    end
      content = tool_result.content

      if tool_result.is_error == true
        return MCP::Shared::AsyncResult(String).new(
          error: Crig::ToolError.tool_call_error(
            McpToolError.new(extract_error_message(content) || "No message returned")
          )
        )
      end

      rendered = String.build do |io|
        content.each do |block|
          io << render_content_block(block)
        end
      end

      MCP::Shared::AsyncResult(String).new(value: rendered)
    rescue ex : McpToolError
      MCP::Shared::AsyncResult(String).new(error: Crig::ToolError.tool_call_error(ex))
    rescue ex : Exception
      MCP::Shared::AsyncResult(String).new(error: Crig::ToolError.tool_call_error(
        McpToolError.new("Tool returned an error: #{ex.message || ex.class.name}")
      ))
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
