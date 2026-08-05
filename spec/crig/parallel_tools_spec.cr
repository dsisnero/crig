require "../spec_helper"

PARALLEL_PROMPT = "Compute 3 + 4 and 10 - 2. You MUST call the add tool and the subtract tool together in your first response, as two parallel function calls, then report both results."

# Model that emits both add and subtract calls in a single assistant turn,
# then returns the final text answer.
class ParallelCallsModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).many([
                 Crig::Completion::AssistantContent.tool_call_with_call_id("add_1", "add_1", "add", JSON.parse(%({"x":3,"y":4}))),
                 Crig::Completion::AssistantContent.tool_call_with_call_id("sub_1", "sub_1", "subtract", JSON.parse(%({"x":10,"y":2}))),
               ])
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("7 and 8")
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
      .tool(Crig::Completion::ToolDefinition.new("subtract", "Subtract y from x", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))))
  end
end

module Crig
  describe "parallel_tools conformance" do
    it "executes two tool calls from one turn and correlates both results" do
      add_calls = Atomic(Int32).new(0)
      subtract_calls = Atomic(Int32).new(0)

      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        add_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      subtract_tool = DynamicTool.new("subtract", "Subtract y from x", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        subtract_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i - parsed["y"].as_i)))
      end

      model = ParallelCallsModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      ts.add_tool(subtract_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "You are a calculator assistant. You MUST use the provided tools for every arithmetic operation instead of computing results yourself. Once you have all the tool results you need, reply with the final numeric answer in plain text.",
        temperature: 0.0,
        tool_server_handle: ts.run,
        default_max_turns: 3,
      )

      response = agent.runner(Completion::Message.user(PARALLEL_PROMPT))
        .max_turns(3)
        .run(Completion::Message.user(PARALLEL_PROMPT))

      add_calls.get.should eq(1)
      subtract_calls.get.should eq(1)

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.validate_tool_correlation("parallel_tools", history)

      # Find an assistant turn with exactly two tool calls (add + subtract).
      parallel_turn = history.find do |m|
        next false unless m.role.assistant?
        m.content.count { |item| (item.as?(Completion::AssistantContent)).try(&.kind.tool_call?) || false } == 2
      end
      parallel_turn.should_not be_nil

      # The following user message holds both results: 7 and 8.
      idx = history.index(parallel_turn.not_nil!)
      results_message = history[idx.not_nil! + 1]
      results_message.role.should eq(Completion::Message::Role::User)

      values = [] of JSON::Any
      results_message.content.each do |item|
        uc = item.as?(Completion::UserContent)
        if uc && (result = uc.tool_result)
          result.content.each do |content|
            if (json = content.as?(Completion::ToolResultContent))
              if (v = json.as_json?)
                values << v
              elsif (t = json.as_text?)
                values << JSON::Any.new(t)
              end
            end
          end
        end
      end

      values.size.should eq(2)
      values.any? { |v| Crig::Conformance.value_matches_integer(v, 7) }.should be_true
      values.any? { |v| Crig::Conformance.value_matches_integer(v, 8) }.should be_true
    end
  end
end
