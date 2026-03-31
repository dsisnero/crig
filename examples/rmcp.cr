require "../src/crig"
require "mcp"
require "http/server"

module Crig::Examples::RMCP
  def self.build_client(uri : String) : MCP::Client::Client
    client = MCP::Client::Client.new(
      client_info: MCP::Protocol::Implementation.new("crig", "0.1.0"),
      client_options: MCP::Client::ClientOptions.new(
        capabilities: MCP::Protocol::ClientCapabilities.new
      )
    )
    client.connect(MCP::Client::StreamableHttpClientTransport.from_uri(uri))
    client
  end

  def self.build_agent(completion_client, model : String, uri : String)
    mcp_client = build_client(uri)
    tools = mcp_client.list_tools.not_nil!.tools

    completion_client
      .agent(model)
      .preamble("You are a helpful assistant who has access to a number of tools from an MCP server designed to be used for incrementing and decrementing a counter.")
      .rmcp_tools(tools, mcp_client)
      .build
  end

  def self.run_prompt(completion_client, model : String, uri : String, prompt : String, max_turns : Int32 = 2) : String
    build_agent(completion_client, model, uri)
      .prompt(prompt)
      .max_turns(max_turns)
      .send
  end

  struct StructRequest
    include JSON::Serializable

    getter a : Int32
    getter b : Int32

    def initialize(@a : Int32, @b : Int32)
    end
  end

  class Counter
    getter counter : Int32
    getter server : MCP::Server::Server

    def initialize
      @mutex = Mutex.new
      @counter = 0
      @server = build_server
    end

    def create_resource_text(uri : String, name : String) : MCP::Protocol::Resource
      MCP::Protocol::Resource.new(name, uri)
    end

    def sum(request : StructRequest) : MCP::Protocol::CallToolResult
      result = request.a + request.b
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new(result.to_s)] of MCP::Protocol::ContentBlock)
    end

    def list_resources : MCP::Protocol::ListResourcesResult
      MCP::Protocol::ListResourcesResult.new(
        resources: [
          create_resource_text("str:////Users/to/some/path/", "cwd"),
          create_resource_text("memo://insights", "memo-name"),
        ]
      )
    end

    def read_resource(uri : String) : MCP::Protocol::ReadResourceResult
      case uri
      when "str:////Users/to/some/path/"
        cwd = "/Users/to/some/path/"
        MCP::Protocol::ReadResourceResult.new(
          contents: [MCP::Protocol::TextResourceContents.new(uri, cwd)] of MCP::Protocol::ResourceContents
        )
      when "memo://insights"
        memo = "Business Intelligence Memo\n\nAnalysis has revealed 5 key insights ..."
        MCP::Protocol::ReadResourceResult.new(
          contents: [MCP::Protocol::TextResourceContents.new(uri, memo)] of MCP::Protocol::ResourceContents
        )
      else
        raise "resource_not_found: #{uri}"
      end
    end

    def list_resource_templates : MCP::Protocol::ListResourceTemplatesResult
      MCP::Protocol::ListResourceTemplatesResult.new(resource_templates: [] of MCP::Protocol::ResourceTemplate)
    end

    private def build_server : MCP::Server::Server
      server = MCP::Server::Server.new(
        MCP::Protocol::Implementation.new(name: "counter", version: "1.0.0"),
        MCP::Server::ServerOptions.new(
          capabilities: MCP::Protocol::ServerCapabilities.new.with_tools.with_resources
        )
      )

      server.add_tool(
        "sum",
        "Calculate the sum of two numbers",
        MCP::Protocol::Tool::Input.new(
          properties: {
            "a" => JSON::Any.new({"type" => JSON::Any.new("number")}),
            "b" => JSON::Any.new({"type" => JSON::Any.new("number")}),
          },
          required: ["a", "b"]
        )
      ) do |request|
        args = request.arguments || raise "missing arguments"
        sum(StructRequest.new(args["a"].as_i, args["b"].as_i))
      end

      server.request_handler(MCP::Protocol::ResourcesList) do |_request, _|
        list_resources
      end

      server.request_handler(MCP::Protocol::ResourcesRead) do |request, _|
        read_resource(request.as(MCP::Protocol::ReadResourceRequestParams).uri)
      end

      server.request_handler(MCP::Protocol::ResourcesTemplatesList) do |_request, _|
        list_resource_templates
      end

      server
    end
  end

  class StreamableServer
    getter endpoint : String

    def initialize(@endpoint : String = "/mcp", &@server_factory : -> MCP::Server::Server)
      @transports = {} of String => MCP::Server::StreamableHttpServerTransport
      @mutex = Mutex.new
    end

    def self.from_counter(endpoint : String = "/mcp") : self
      new(endpoint) { Counter.new.server }
    end

    def http_server : HTTP::Server
      HTTP::Server.new do |context|
        handle_request(context)
      end
    end

    def self.start(port : Int32 = 8080, endpoint : String = "/mcp") : self
      server = from_counter(endpoint)
      http_server = server.http_server
      http_server.bind_tcp("127.0.0.1", port)
      spawn do
        http_server.listen
      end
      server
    end

    def handle_request(context : HTTP::Server::Context) : Nil
      case {context.request.method, context.request.path}
      when {"POST", @endpoint}
        handle_post_rpc(context)
      when {"GET", @endpoint}
        handle_sse_stream(context)
      when {"DELETE", @endpoint}
        handle_delete_session(context)
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
      end
    end

    def active_session_ids : Array(String)
      @mutex.synchronize { @transports.keys.sort! }
    end

    private def handle_post_rpc(context : HTTP::Server::Context) : Nil
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?
      transport = if existing = session_id.try { |sid| @mutex.synchronize { @transports[sid]? } }
                    existing
                  elsif session_id.nil?
                    MCP::Server::StreamableHttpServerTransport.new(true, true)
                  else
                    context.response.status_code = HTTP::Status::BAD_REQUEST.code
                    context.response.print("Invalid request or session")
                    return
                  end

      transport.on_close do
        if sid = transport.session_id
          @mutex.synchronize { @transports.delete(sid) }
        end
      end

      server = @server_factory.call
      server.connect(transport)
      transport.handle_post_request(context)
      if sid = transport.session_id
        @mutex.synchronize { @transports[sid] = transport }
      end
    end

    private def handle_sse_stream(context : HTTP::Server::Context) : Nil
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?
      transport = session_id ? @mutex.synchronize { @transports[session_id]? } : nil

      unless transport
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.print("Invalid session")
        return
      end

      MCP::SSE.upgrade_response(context.response) do |conn|
        session = MCP::Server::ServerSSESession.new(conn)
        transport.handle_get_request(context, session)
      end
    end

    private def handle_delete_session(context : HTTP::Server::Context) : Nil
      session_id = context.request.headers[MCP::Server::StreamableHttpServerTransport::MCP_SESSION_ID]?

      unless session_id
        context.response.status_code = HTTP::Status::BAD_REQUEST.code
        context.response.print("Missing session")
        return
      end

      transport = @mutex.synchronize { @transports.delete(session_id) }

      if transport
        transport.handle_delete_request(context)
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Session not found")
      end
    end
  end
end
