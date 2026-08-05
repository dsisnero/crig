require "../spec_helper"

# Model that streams an add tool call on turn 1 and text "42" on turn 2.
class StreamingAddModel
  include Crig::Completion::CompletionModel

  getter turn_counter = 0

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("unused")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    turn = @turn_counter
    @turn_counter += 1

    choice = if turn == 0
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "add_1", "add_1", "add",
                   JSON.parse(%({"x":17,"y":25})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("42")
               )
             end

    usage = turn == 0 ? Crig::Completion::Usage.new(total_tokens: 4) : Crig::Completion::Usage.new(total_tokens: 6)
    Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).new(
      turn == 0 ? [] of String : ["42"],
      Crig::Client::FinalCompletionResponse.new(usage),
      choice: choice,
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))))
  end
end

module Crig
  describe "streaming_tool conformance" do
    it "streams a tool call, correlates streamed call/result ids, and accumulates usage" do
      calls = Atomic(Int32).new(0)

      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      model = StreamingAddModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use the add tool for arithmetic; do not calculate by hand.",
        tool_server_handle: ts.run,
        default_max_turns: 4,
      )

      result = agent.stream_prompt("Use add to calculate 17 + 25, then state the final number.")
        .max_turns(4)
        .with_history([] of Crig::Completion::Message)
        .send_items

      streamed_call_ids = [] of String
      streamed_result_ids = [] of String
      final_count = 0
      completion_usage = Crig::Completion::Usage.new
      final_response = nil.as(Crig::PromptResponse?)

      result.items.each do |item|
        case item.kind
        in .stream_assistant_item?
          if item.assistant_item.try(&.kind.tool_call?)
            streamed_call_ids << (item.assistant_item.try(&.internal_call_id) || "")
          end
        in .stream_user_item?
          if item.user_item.try(&.kind.tool_result?)
            streamed_result_ids << item.user_item.try(&.internal_call_id).to_s
          end
        in .completion_call?
          if usage = item.completion_call.try(&.usage)
            completion_usage += usage
          end
        in .final_response?
          final_count += 1
          final_response = item.final_response
        in .tool_execution_committed?
        end
      end

      final_response.should_not be_nil
      result = final_response.not_nil!

      result.output.should contain("42")
      calls.get.should be >= 1
      final_count.should eq(1)

      streamed_call_ids.sort.should eq(streamed_result_ids.sort)
      streamed_call_ids.should_not be_empty

      history = result.messages || [] of Crig::Completion::Message
      history.size.should be >= 4
      Crig::Conformance.validate_tool_correlation("streaming_tool", history)

      completion_usage.should eq(result.usage)
      result.completion_calls.should_not be_empty
    end
  end
end
