require "../../spec_helper"
describe Crig::ToolError do
  it "wraps tool-call errors with the upstream prefix" do
    error = Crig::ToolError.tool_call_error(Exception.new("boom"))

    error.message.should eq("ToolCallError: boom")
    error.kind.should eq(Crig::ToolError::Kind::ToolCallError)
  end

  it "does not double-wrap tool-call errors" do
    error = Crig::ToolError.tool_call_error(Exception.new("ToolCallError: boom"))

    error.message.should eq("ToolCallError: boom")
    error.kind.should eq(Crig::ToolError::Kind::ToolCallError)
  end

  it "wraps json errors with the upstream prefix" do
    error = Crig::ToolError.json_error(Exception.new("bad json"))

    error.message.should eq("JsonError: bad json")
    error.kind.should eq(Crig::ToolError::Kind::JsonError)
    error.source_error.should be_a(Exception)
  end
end

describe Crig::ToolDyn do
  it "serializes typed tool output from parsed json args" do
    tool = EchoTool.new

    tool.call(%({"value":"hello"})).should eq(%("hello"))
  end

  it "uses the default NAME-backed tool name when not overridden" do
    DefaultNamedTool.new.name.should eq("default-named")
  end

  it "wraps json parse failures as tool errors" do
    tool = EchoTool.new

    expect_raises(Crig::ToolError, "JsonError: Unexpected char") do
      tool.call("not-json")
    end
  end

  it "wraps tool call failures as tool errors" do
    tool = FailingEchoTool.new

    expect_raises(Crig::ToolError, "ToolCallError: boom") do
      tool.call(%({"value":"hello"}))
    end
  end

  it "preserves recursive tool call prefixes" do
    tool = RecursiveFailingTool.new

    expect_raises(Crig::ToolError, "ToolCallError: already wrapped") do
      tool.call(%({"value":"hello"}))
    end
  end

  it "lets agents act as dynamic tools" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeToolModel
        include Crig::Completion::CompletionModel

        property last_request : Crig::Completion::Request::CompletionRequest?
        getter model : String

        def initialize(@model : String)
        end

        def name : String
          @model
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.text("completion:#{@model}")
            ),
            Crig::Completion::Usage.new,
            "raw:#{@model}",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["chunk:#{@model}"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeToolModel.new("agent-tool")
      agent = Crig::AgentBuilder(ProbeToolModel).new(model).name("calculator_agent").build
      response = agent.call(%({"prompt":"Calculate 2 - 5"}))
      request = model.last_request.not_nil!

      puts(JSON.build do |json|
        json.object do
          json.field "name", agent.name
          json.field "definition_name", Crig.tool_definition(Crig::AgentToolAdapter.new(agent)).name
          json.field "response", response
          json.field "prompt", request.chat_history.last.rag_text
        end
      end)
    CRYSTAL

    result["name"].as_s.should eq("calculator_agent")
    result["definition_name"].as_s.should eq("calculator_agent")
    result["response"].as_s.should eq("completion:agent-tool")
    result["prompt"].as_s.should eq("Calculate 2 - 5")
  end
end

describe "Crig.rig_tool" do
  it "ports the calculator rig_tool test" do
    tool = Calculator.new
    definition = Crig.tool_definition(tool)

    tool.name.should eq("calculator")
    definition.name.should eq("calculator")
    definition.description.should eq("Perform basic arithmetic operations")
    definition.parameters["properties"]["x"]["description"].as_s.should eq("First number in the calculation")
    definition.parameters["required"].as_a.map(&.as_s).should eq(["x", "y", "operation"])

    [
      {CalculatorParameters.new(5, 3, "add"), 8},
      {CalculatorParameters.new(5, 3, "subtract"), 2},
      {CalculatorParameters.new(5, 3, "multiply"), 15},
      {CalculatorParameters.new(6, 2, "divide"), 3},
    ].each do |input, expected|
      tool.call(input.to_json).should eq(expected.to_json)
    end

    expect_raises(Crig::ToolError, "ToolCallError: Division by zero") do
      tool.call(CalculatorParameters.new(5, 0, "divide").to_json)
    end

    expect_raises(Crig::ToolError, "ToolCallError: Unknown operation: power") do
      tool.call(CalculatorParameters.new(5, 3, "power").to_json)
    end

    SyncCalculator.new.call(SyncCalculatorParameters.new(5, 3, "add").to_json).should eq("8")
    CALCULATOR.name.should eq("calculator")
    SYNC_CALCULATOR.name.should eq("sync_calculator")
  end

  it "uses the default description when one is not provided" do
    tool = CountRs.new
    definition = Crig.tool_definition(tool)

    definition.description.should eq("Function to count_rs")
    tool.call(CountRsParameters.new("Rig rocks").to_json).should eq("2")
  end
end

describe Crig::ThinkTool do
  it "exposes the think error as a normal crystal exception" do
    Crig::ThinkError.new("boom").message.should eq("boom")
  end

  it "builds the upstream think definition" do
    tool = Crig::ThinkTool.new
    definition = Crig.tool_definition(tool)

    definition.name.should eq("think")
    definition.description.should contain("Use the tool to think about something")
    definition.parameters["required"][0].as_s.should eq("thought")
  end

  it "echoes the thought content back" do
    tool = Crig::ThinkTool.new

    tool.call(%({"thought":"I should verify the user"})).should eq(%("I should verify the user"))
  end
end

describe Crig::ToolSet do
  it "builds from tools and returns definitions" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new])

    toolset.contains("echo").should be_true
    toolset.get_tool_definitions.map(&.name).should eq(["echo"])
  end

  it "adds tools, merges toolsets, and deletes tools" do
    toolset = Crig::ToolSet.new
    toolset.add_tool(EchoTool.new)
    toolset.contains("echo").should be_true

    extra = Crig::ToolSet.from_tools([Crig::ThinkTool.new])
    toolset.add_tools(extra)
    toolset.contains("think").should be_true

    toolset.delete_tool("echo")
    toolset.contains("echo").should be_false
    toolset.tools.size.should eq(1)
  end

  it "calls tools by name" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new])

    toolset.call("echo", %({"value":"hello"})).should eq(%("hello"))
  end

  it "raises not found errors for missing tools" do
    toolset = Crig::ToolSet.new

    error = expect_raises(Crig::ToolSetError, "ToolNotFoundError: missing") do
      toolset.call("missing", "{}")
    end

    error.kind.should eq(Crig::ToolSetError::Kind::ToolNotFoundError)
    error.source_error.should be_nil
  end

  it "wraps tool call errors as tool set errors" do
    toolset = Crig::ToolSet.from_tools([FailingEchoTool.new])

    error = expect_raises(Crig::ToolSetError, "ToolCallError: boom") do
      toolset.call("echo", %({"value":"hello"}))
    end

    error.kind.should eq(Crig::ToolSetError::Kind::ToolCallError)
    error.source_error.should be_a(Crig::ToolError)
  end

  it "returns schemas for embedding-backed tools only" do
    toolset = Crig::ToolSet.builder
      .static_tool(EchoTool.new)
      .dynamic_tool(EmbeddedEchoTool.new)
      .build

    schemas = toolset.schemas

    schemas.size.should eq(1)
    schemas.first.name.should eq("embedded-echo")
    schemas.first.context["category"].as_s.should eq("utility")
    schemas.first.embedding_docs.should eq(["Echo values back to the caller."])
  end

  it "initializes embedding-backed tools from runtime state and stored context" do
    tool = StatefulEmbeddedEchoTool.init("runtime", EmbeddedEchoContext.new("utility"))

    tool.call_typed(EchoArgs.new("hello")).should eq("runtime:utility:hello")
    tool.context["category"].as_s.should eq("utility")
    tool.embedding_docs.should eq(["runtime:utility"])
  end

  it "returns documents for all tools" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new, Crig::ThinkTool.new])
    documents = toolset.documents

    documents.size.should eq(2)
    documents.map(&.id).should contain("echo")
    documents.map(&.id).should contain("think")
    documents.each do |doc|
      doc.text.should contain("Tool: #{doc.id}")
      doc.text.should contain("Definition:")
    end
  end
end

describe Crig::ToolSetBuilder do
  it "builds static and dynamic tools into a toolset" do
    toolset = Crig::ToolSet.builder
      .static_tool(EchoTool.new)
      .dynamic_tool(EmbeddedEchoTool.new)
      .build

    toolset.contains("echo").should be_true
    toolset.contains("embedded-echo").should be_true
  end

  it "keeps multiple embedding-backed tools addressable through the builder" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct OperationArgs
        include JSON::Serializable

        getter x : Int32
        getter y : Int32

        def initialize(@x : Int32, @y : Int32)
        end
      end

      module ArithmeticTool
        def self.parameters(label : String) : JSON::Any
          JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"description":"#{label}"}))
        end
      end

      struct Add
        include Crig::ToolEmbedding(OperationArgs, Int32, Nil)
        def self.init(state, context : Nil) : self; _ = state; _ = context; new; end
        def name : String; "add"; end
        def description : String; "Add x and y together"; end
        def parameters : JSON::Any; ArithmeticTool.parameters("add"); end
        def call_typed(args : OperationArgs) : Int32; args.x + args.y; end
        def embedding_docs : Array(String); ["Add x and y together"]; end
        def typed_context : Nil; nil; end
      end

      struct Subtract
        include Crig::ToolEmbedding(OperationArgs, Int32, Nil)
        def self.init(state, context : Nil) : self; _ = state; _ = context; new; end
        def name : String; "subtract"; end
        def description : String; "Subtract y from x"; end
        def parameters : JSON::Any; ArithmeticTool.parameters("subtract"); end
        def call_typed(args : OperationArgs) : Int32; args.x - args.y; end
        def embedding_docs : Array(String); ["Subtract y from x"]; end
        def typed_context : Nil; nil; end
      end

      struct Multiply
        include Crig::ToolEmbedding(OperationArgs, Int32, Nil)
        def self.init(state, context : Nil) : self; _ = state; _ = context; new; end
        def name : String; "multiply"; end
        def description : String; "Multiply x and y"; end
        def parameters : JSON::Any; ArithmeticTool.parameters("multiply"); end
        def call_typed(args : OperationArgs) : Int32; args.x * args.y; end
        def embedding_docs : Array(String); ["Multiply x and y"]; end
        def typed_context : Nil; nil; end
      end

      struct Divide
        include Crig::ToolEmbedding(OperationArgs, Int32, Nil)
        def self.init(state, context : Nil) : self; _ = state; _ = context; new; end
        def name : String; "divide"; end
        def description : String; "Divide x by y"; end
        def parameters : JSON::Any; ArithmeticTool.parameters("divide"); end
        def call_typed(args : OperationArgs) : Int32; args.x // args.y; end
        def embedding_docs : Array(String); ["Divide x by y"]; end
        def typed_context : Nil; nil; end
      end

      toolset = Crig::ToolSet.builder
        .dynamic_tool(Add.new)
        .dynamic_tool(Subtract.new)
        .dynamic_tool(Multiply.new)
        .dynamic_tool(Divide.new)
        .build

      puts(JSON.build do |json|
        json.object do
          json.field "names" do
            json.array do
              toolset.tools.keys.sort.each { |name| json.string(name) }
            end
          end
          json.field "schemas" do
            json.array do
              toolset.schemas.map(&.name).sort.each { |name| json.string(name) }
            end
          end
        end
      end)
    CRYSTAL

    result["names"].as_a.map(&.as_s).should eq(%w[add divide multiply subtract])
    result["schemas"].as_a.map(&.as_s).should eq(%w[add divide multiply subtract])
  end
end

describe Crig::ToolType do
  it "returns the wrapped tool name for embedding tools" do
    Crig::ToolType.embedding(EmbeddedEchoTool.new).name.should eq("embedded-echo")
  end
end

describe Crig::ToolServer do
  it "handles append_toolset requests and exposes tools via the server handle" do
    handle = Crig::ToolServer.new.run
    handle.append_toolset(Crig::ToolSet.from_tools([EchoTool.new]))

    handle.call_tool("echo", %({"value":"hello"})).should eq(%("hello"))
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
  end

  it "adds tools, returns definitions, calls them, and removes them through the handle" do
    server = Crig::ToolServer.new
    handle = server.run

    handle.add_tool(EchoTool.new)
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.call_tool("echo", %({"value":"hello"})).should eq(%("hello"))

    handle.remove_tool("echo")
    handle.get_tool_defs(nil).should eq([] of Crig::Completion::ToolDefinition)
  end

  it "returns static and dynamic tool definitions for prompted lookup" do
    dynamic_toolset = Crig::ToolSet.from_tools([DefaultNamedTool.new])
    server = Crig::ToolServer.new
      .tool(EchoTool.new)
      .dynamic_tools(1, MockToolIndex.new(["default-named"]), dynamic_toolset)
    handle = server.run

    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.get_tool_defs("find extra").map(&.name).sort.should eq(["default-named", "echo"])
  end

  it "queries dynamic tool indexes concurrently when resolving definitions" do
    started = Atomic(Int32).new(0)
    dynamic_toolset = Crig::ToolSet.from_tools([EchoTool.new, DefaultNamedTool.new])

    dynamic_a = {
      1_i32,
      ->(request : Crig::VectorSearchRequest) do
        request.query.should eq("find extra")
        started.add(1)
        deadline = Time.instant + 200.milliseconds
        until started.get == 2
          raise "dynamic tool index did not overlap" if Time.instant >= deadline
          Fiber.yield
        end
        [{1.0, "echo"}]
      end,
    }

    dynamic_b = {
      1_i32,
      ->(request : Crig::VectorSearchRequest) do
        request.query.should eq("find extra")
        started.add(1)
        deadline = Time.instant + 200.milliseconds
        until started.get == 2
          raise "dynamic tool index did not overlap" if Time.instant >= deadline
          Fiber.yield
        end
        [{1.0, "default-named"}]
      end,
    }

    server = Crig::ToolServer.new
      .add_tools(dynamic_toolset)
      .add_dynamic_tools([dynamic_a, dynamic_b])

    handle = server.run
    handle.get_tool_defs("find extra").map(&.name).sort.should eq(["default-named", "echo"])
  end

  it "ignores missing dynamic tool implementations when building tool definitions" do
    server = Crig::ToolServer.new
      .tool(EchoTool.new)
      .dynamic_tools(1, MockToolIndex.new(["missing-tool"]), Crig::ToolSet.new)
    handle = server.run

    handle.get_tool_defs("find extra").map(&.name).should eq(["echo"])
  end

  it "supports Rust-style builder helpers for static names, toolsets, and dynamic tools" do
    dynamic = {
      1_i32,
      ->(request : Crig::VectorSearchRequest) {
        request.query.should eq("find extra")
        [{1.0, "default-named"}]
      },
    }

    server = Crig::ToolServer.new
      .static_tool_names(["echo"])
      .add_tools(Crig::ToolSet.from_tools([EchoTool.new, DefaultNamedTool.new]))
      .add_dynamic_tools([dynamic])

    handle = server.run
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.get_tool_defs("find extra").map(&.name).sort.should eq(["default-named", "echo"])
  end

  it "handles request callbacks and returns tagged responses" do
    callback_response = nil.as(Crig::ToolServerResponse?)
    server = Crig::ToolServer.new.tool(EchoTool.new)

    response = server.handle_message(
      Crig::ToolServerRequest.new(
        Crig::ToolServerRequestMessageKind.get_tool_defs(nil),
        nil,
        ->(result : Crig::ToolServerResponse) {
          callback_response = result
          nil
        }
      )
    )

    response.kind.tool_definitions?.should be_true
    response.tool_definitions.not_nil!.map(&.name).should eq(["echo"])
    callback_response.should eq(response)
  end

  it "exposes parity-style tool server error helpers" do
    Crig::ToolServerError.canceled.message.should eq("Canceled")
    Crig::ToolServerError.invalid_message(
      Crig::ToolServerResponse.tool_added
    ).message.should eq("InvalidMessage: ToolAdded")
  end

  it "executes tool calls concurrently through the running server handle" do
    sleep_ms = 100
    num_calls = 3
    handle = Crig::ToolServer.new.tool(SleeperTool.new(sleep_ms)).run
    results = Channel(String).new(num_calls)

    started_at = Time.instant

    num_calls.times do
      spawn do
        results.send(handle.call_tool("sleeper", "{}"))
      end
    end

    collected = Array(String).new(num_calls) { results.receive }
    elapsed = Time.instant - started_at

    collected.should eq([sleep_ms.to_s] * num_calls)
    elapsed.should be < (sleep_ms * 2).milliseconds
  end

  it "handles high concurrent call volume without loss" do
    total_calls = 100
    handle = Crig::ToolServer.new.tool(EchoTool.new).run
    results = Channel(String).new(total_calls)

    total_calls.times do |index|
      spawn do
        results.send(handle.call_tool("echo", %({"value":"#{index}"})))
      end
    end

    collected = Array(String).new(total_calls) { results.receive }

    collected.size.should eq(total_calls)
    collected.map { |item| JSON.parse(item).as_s.to_i }.sort.should eq((0...total_calls).to_a)
  end
end

describe Crig::McpTool do
  it "converts MCP tool definitions into completion tool definitions" do
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x"]
      )
    )

    converted = Crig::McpTool.to_tool_definition(definition)

    converted.name.should eq("sum")
    converted.description.should eq("Add numbers")
    converted.parameters["properties"].as_h["x"].as_h["type"].as_s.should eq("number")
  end

  it "builds tool definitions from MCP tools and calls text tools through an MCP client" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    tool.name.should eq("sum")
    tool.call(%({"x":2,"y":5})).should eq("7")
  end

  it "stringifies image and resource content blocks like the Rust MCP adapter" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "render",
      description: "Render content",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("render", "Render content", definition.input_schema) do |_request|
      blocks = [
        MCP::Protocol::TextContentBlock.new("prefix "),
        MCP::Protocol::ImageContentBlock.new("abc123", "image/png"),
        MCP::Protocol::EmbeddedResourceBlock.new(MCP::Protocol::TextResourceContents.new("file:///memo", "body", "text/plain")),
      ] of MCP::Protocol::ContentBlock
      MCP::Protocol::CallToolResult.new(blocks)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)
    tool.call("{}").should eq("prefix data:image/png;base64,abc123data:text/plain;file:///memo:body")
  end

  it "wraps MCP error results as tool call errors" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "fail",
      description: "Fail tool",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("fail", "Fail tool", definition.input_schema) do |_request|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("boom")] of MCP::Protocol::ContentBlock, is_error: true)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    expect_raises(Crig::ToolError, "ToolCallError: MCP tool error: boom") do
      tool.call("{}")
    end
  end

  it "raises on unsupported audio MCP content" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "audio",
      description: "Audio tool",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("audio", "Audio tool", definition.input_schema) do |_request|
      MCP::Protocol::CallToolResult.new([
        MCP::Protocol::AudioContentBlock.new("abc123", "audio/wav"),
      ] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    expect_raises(Crig::ToolError, "ToolCallError: MCP tool error: Tool returned an error: Support for audio results from an MCP tool is currently unimplemented. Come back later!") do
      tool.call("{}")
    end
  end

  it "registers MCP tools through ToolServer#rmcp_tool" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    handle = Crig::ToolServer.new.rmcp_tool(definition, client).run

    handle.get_tool_defs(nil).map(&.name).should eq(["sum"])
    handle.call_tool("sum", %({"x":3,"y":4})).should eq("7")
  end

  it "registers MCP tools with a per-call timeout through ToolServer#rmcp_tool_with_timeout" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    handle = Crig::ToolServer.new
      .rmcp_tool_with_timeout(definition, client, 1.second)
      .run

    handle.get_tool_defs(nil).map(&.name).should eq(["sum"])
    handle.call_tool("sum", %({"x":3,"y":4})).should eq("7")
  end

  it "registers MCP tools through AgentBuilder#rmcp_tool_with_timeout" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .rmcp_tool_with_timeout(definition, client, 1.second)
      .build

    handle = agent.tool_server_handle
    handle.should_not be_nil
    handle.try(&.get_tool_defs(nil).map(&.name)).should eq(["sum"])
  end

  it "defaults ToolServer MCP tools to the upstream 300s timeout" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    ts = Crig::ToolServer.new
    ts.rmcp_tool(definition, client)
    tool = ts.toolset.get("sum").as(Crig::McpTool)
    tool.timeout.should eq(Crig::DEFAULT_MCP_TOOL_TIMEOUT)
  end

  it "calls an MCP tool asynchronously using call_tool_async" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)
    channel = tool.call_async(%({"x":2,"y":5}))
    result = channel.receive
    result.success?.should be_true
    result.unwrap.should eq("7")
  end

  it "applies a per-call timeout to MCP tool calls" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "slow",
      description: "Hangs",
      input_schema: MCP::Protocol::Tool::Input.new,
    )

    server.add_tool("slow", "Hangs", definition.input_schema) do |_request|
      sleep(5.seconds)
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("late")] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)
      .with_timeout(20.milliseconds)

    tool.timeout.should eq(20.milliseconds)

    error = expect_raises(Crig::ToolError) do
      tool.call("{}")
    end

    error.to_s.should contain("timed out")
  end

  it "defaults MCP tool calls to the upstream 300s timeout" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new,
    )

    tool = Crig::McpTool.from_mcp_server(definition, client)

    tool.timeout.should eq(Crig::DEFAULT_MCP_TOOL_TIMEOUT)
  end
end
