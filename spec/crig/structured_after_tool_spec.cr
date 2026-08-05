require "../spec_helper"

struct ConformanceArithmeticResult
  include JSON::Serializable

  getter answer : Int32
  getter explanation : String?

  def initialize(@answer : Int32, @explanation : String?)
  end
end

# Model that calls add on turn 1, then the synthetic output tool on turn 2.
class StructuredAfterToolModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "add_1", "add_1", "add",
                   JSON.parse(%({"x":19,"y":23})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "out_1", "out_1", "final_result",
                   JSON.parse(%({"answer":42,"explanation":"short"})),
                 )
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))))
  end
end

module Crig
  describe "structured_after_tool conformance" do
    it "finalizes structured output via the output tool after a real tool call" do
      calls = Atomic(Int32).new(0)

      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      model = StructuredAfterToolModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      agent = AgentBuilder(typeof(model)).new(model)
        .preamble("Use add for arithmetic, then finish by calling the structured output tool exactly once.")
        .tool_server_handle(ts.run)
        .default_max_turns(5)
        .output_schema(ConformanceArithmeticResult)
        .build

      response = agent.runner(Completion::Message.user("Use add to calculate 19 + 23. Return answer=42 and a short optional explanation."))
        .max_turns(5)
        .run(Completion::Message.user("Use add to calculate 19 + 23. Return answer=42 and a short optional explanation."))

      parsed = ConformanceArithmeticResult.from_json(response.output)

      calls.get.should be >= 1
      parsed.answer.should eq(42)
      parsed.explanation.should eq("short")

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.has_tool_roundtrip(history).should be_true
    end
  end
end
