require "../spec_helper"

# Model that drives the optional_argument scenario: turn 1 calls
# repeat_text(text="banana", times=3), turn 2 returns the text result.
class OptionalRepeatModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "rep_1", "rep_1", "repeat_text",
                   JSON.parse(%({"text":"banana","times":3}))
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("banana banana banana")
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new(
        "repeat_text",
        "Repeat `text`. `times` is optional and defaults to 2.",
        JSON.parse(%({"type":"object","properties":{"text":{"type":"string"},"times":{"type":"integer"}},"required":["text"]}))
      ))
  end
end

module Crig
  describe "optional_argument conformance" do
    it "runs the repeat_text scenario end to end" do
      calls = Atomic(Int32).new(0)

      repeat_tool = DynamicTool.new(
        "repeat_text",
        "Repeat `text`. `times` is optional and defaults to 2.",
        JSON.parse(%({"type":"object","properties":{"text":{"type":"string"},"times":{"type":"integer"}},"required":["text"]}))
      ) do |args, ctx|
        calls.add(1)
        parsed = JSON.parse(args)
        text = parsed["text"].as_s
        times = parsed["times"]?.try(&.as_i) || 2
        Tool::ToolResult.success(Tool::ToolOutput.text(Array.new(times) { text }.join(" ")))
      end

      model = OptionalRepeatModel.new
      ts = ToolServer.new
      ts.add_tool(repeat_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use the repeat_text tool whenever asked to repeat text.",
        tool_server_handle: ts.run,
        default_max_turns: 4,
      )

      response = agent.runner(Completion::Message.user("Use the repeat_text tool to repeat the word \"banana\" 3 times, then show me the exact result."))
        .run(Completion::Message.user("Use the repeat_text tool to repeat the word \"banana\" 3 times, then show me the exact result."))

      calls.get.should be >= 1
      response.output.should contain("banana")

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.has_tool_roundtrip(history).should be_true
    end

    it "defaults the optional times argument to 2" do
      repeat_tool = DynamicTool.new(
        "repeat_text",
        "Repeat `text`. `times` is optional and defaults to 2.",
        JSON.parse(%({"type":"object","properties":{"text":{"type":"string"},"times":{"type":"integer"}},"required":["text"]}))
      ) do |args, ctx|
        parsed = JSON.parse(args)
        text = parsed["text"].as_s
        times = parsed["times"]?.try(&.as_i) || 2
        Tool::ToolResult.success(Tool::ToolOutput.text(Array.new(times) { text }.join(" ")))
      end

      result = repeat_tool.call(%({"text":"banana"}))
      result.should eq("banana banana")
    end
  end
end
