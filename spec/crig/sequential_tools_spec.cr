require "../spec_helper"

# Model that drives the sequential_tools scenario: turn 1 calls add(4,6),
# turn 2 calls multiply(10,2), turn 3 returns the text result "20".
class SequentialCalcModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = case @calls
             when 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "add_1", "add_1", "add",
                   JSON.parse(%({"a":4,"b":6}))
                 )
               )
             when 2
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "mul_1", "mul_1", "multiply",
                   JSON.parse(%({"a":10,"b":2}))
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("20")
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("add", "Add two integers a and b.", JSON.parse(%({"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}},"required":["a","b"]}))))
      .tool(Crig::Completion::ToolDefinition.new("multiply", "Multiply two integers a and b.", JSON.parse(%({"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}},"required":["a","b"]}))))
  end
end

module Crig
  describe "sequential_tools conformance" do
    it "calls add then multiply and surfaces the final number" do
      add_calls = Atomic(Int32).new(0)
      multiply_calls = Atomic(Int32).new(0)

      add_tool = DynamicTool.new("add", "Add two integers a and b.", JSON.parse(%({"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}},"required":["a","b"]}))) do |args, ctx|
        add_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["a"].as_i + parsed["b"].as_i)))
      end

      multiply_tool = DynamicTool.new("multiply", "Multiply two integers a and b.", JSON.parse(%({"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}},"required":["a","b"]}))) do |args, ctx|
        multiply_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["a"].as_i * parsed["b"].as_i)))
      end

      model = SequentialCalcModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      ts.add_tool(multiply_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "You are a calculator. Use the add and multiply tools for arithmetic; never compute by hand.",
        tool_server_handle: ts.run,
        default_max_turns: 6,
      )

      response = agent.runner(Completion::Message.user("Compute (4 + 6) * 2. First call the add tool, then call the multiply tool on the result. Tell me the final number."))
        .run(Completion::Message.user("Compute (4 + 6) * 2. First call the add tool, then call the multiply tool on the result. Tell me the final number."))

      add_calls.get.should be >= 1
      multiply_calls.get.should be >= 1
      response.output.should contain("20")

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.has_tool_roundtrip(history).should be_true
    end
  end
end
