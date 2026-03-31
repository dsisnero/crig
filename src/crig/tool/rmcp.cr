require "mcp"

module Crig
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
      result = @client.call_tool(@mcp_definition.name, parse_arguments(args))
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
end
