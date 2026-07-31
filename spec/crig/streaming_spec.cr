require "../spec_helper"

module Crig
  describe StreamingCompletionResponse(FinalCompletionResponse), tags: %w[streaming completion] do
    it "stores streaming chunks and an optional final response" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream(
        ["a", "b"],
        FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 2)),
      )

      response.chunks.should eq(["a", "b"])
      response.response.try(&.usage).try(&.total_tokens).should eq(2)
    end

    it "supports pause and resume state" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream(["a"])

      response.is_paused.should be_false
      response.pause
      response.is_paused.should be_true
      response.resume
      response.is_paused.should be_false
    end

    it "consumes channel-backed streaming choices and aggregates the final response" do
      source = Channel(Concurrency::Result(RawStreamingChoice(FinalCompletionResponse))).new(4)
      source.send(Concurrency::Result(RawStreamingChoice(FinalCompletionResponse)).success(
        RawStreamingChoice(FinalCompletionResponse).message("hello ")
      ))
      source.send(Concurrency::Result(RawStreamingChoice(FinalCompletionResponse)).success(
        RawStreamingChoice(FinalCompletionResponse).message("world")
      ))
      source.send(Concurrency::Result(RawStreamingChoice(FinalCompletionResponse)).success(
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 2))
        )
      ))
      source.close

      response = StreamingCompletionResponse(FinalCompletionResponse).stream(source)
      items = response.consume

      items.map(&.kind.to_s).should eq(["Text", "Text", "Final"])
      response.choice.to_a.first.text.try(&.text).should eq("hello world")
      response.response.try(&.usage).try(&.total_tokens).should eq(2)
    end

    it "aggregates reasoning content from raw streaming choices" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).reasoning(
          "rs_1",
          Completion::ReasoningContent.text("step one", "sig_1")
        ),
        RawStreamingChoice(FinalCompletionResponse).message("final answer"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 5))
        ),
      ])

      choice_items = response.choice.to_a
      choice_items.size.should eq(2)
      choice_items[0].kind.reasoning?.should be_true
      choice_items[0].reasoning.try(&.id).should eq("rs_1")
      choice_items[0].reasoning.try(&.content.first.text).should eq("step one")
      choice_items[0].reasoning.try(&.content.first.signature).should eq("sig_1")
      choice_items[1].kind.text?.should be_true
      choice_items[1].text.try(&.text).should eq("final answer")
    end

    it "does not inject empty text into reasoning-only streams" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).reasoning(
          "rs_only",
          Completion::ReasoningContent.summary("hidden summary")
        ),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 2))
        ),
      ])

      choice_items = response.choice.to_a
      choice_items.size.should eq(1)
      choice_items[0].kind.reasoning?.should be_true
      choice_items[0].reasoning.try(&.id).should eq("rs_only")
    end

    it "keeps assistant items in arrival order across reasoning text and tool calls" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).reasoning(
          "rs_interleaved",
          Completion::ReasoningContent.text("chain-of-thought")
        ),
        RawStreamingChoice(FinalCompletionResponse).message("final-text"),
        RawStreamingChoice(FinalCompletionResponse).tool_call(
          RawStreamingToolCall.new(
            "tool_1",
            "mock_tool",
            JSON.parse(%({"arg":1}))
          )
        ),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 3))
        ),
      ])

      choice_items = response.choice.to_a
      choice_items.size.should eq(3)
      choice_items[0].kind.reasoning?.should be_true
      choice_items[0].reasoning.try(&.id).should eq("rs_interleaved")
      choice_items[1].kind.text?.should be_true
      choice_items[1].text.try(&.text).should eq("final-text")
      choice_items[2].kind.tool_call?.should be_true
      choice_items[2].tool_call.try(&.id).should eq("tool_1")
    end

    it "keeps non contiguous text chunks split by tool calls" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message("first"),
        RawStreamingChoice(FinalCompletionResponse).tool_call(
          RawStreamingToolCall.new(
            "tool_split",
            "mock_tool",
            JSON.parse(%({"arg":"x"}))
          )
        ),
        RawStreamingChoice(FinalCompletionResponse).message("second"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 3))
        ),
      ])

      choice_items = response.choice.to_a
      choice_items.size.should eq(3)
      choice_items[0].kind.text?.should be_true
      choice_items[0].text.try(&.text).should eq("first")
      choice_items[1].kind.tool_call?.should be_true
      choice_items[1].tool_call.try(&.id).should eq("tool_split")
      choice_items[2].kind.text?.should be_true
      choice_items[2].text.try(&.text).should eq("second")
    end

    it "aggregates reasoning deltas into a single reasoning item" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
        RawStreamingChoice(FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 4))
        ),
      ])

      choice_items = response.choice.to_a
      choice_items.size.should eq(1)
      choice_items[0].kind.reasoning?.should be_true
      choice_items[0].reasoning.try(&.id).should eq("rs_delta")
      choice_items[0].reasoning.try(&.content.first.text).should eq("step one")
      choice_items[0].reasoning.try(&.content.first.signature).should be_nil
    end

    it "captures message ids and final responses from raw choices" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message_id("msg-raw-1"),
        RawStreamingChoice(FinalCompletionResponse).message("hello"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 7))
        ),
      ])

      response.message_id.should eq("msg-raw-1")
      response.response.try(&.usage).try(&.total_tokens).should eq(7)
    end

    it "yields tool call delta and reasoning delta items while aggregating state" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).tool_call_delta(
          "tool-1",
          "internal-1",
          ToolCallDeltaContent.delta("{")
        ),
        RawStreamingChoice(FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
        RawStreamingChoice(FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 9))
        ),
      ])

      item1 = response.next_item
      item2 = response.next_item
      item3 = response.next_item
      item4 = response.next_item
      item5 = response.next_item

      item1.should_not be_nil
      item1.try(&.kind.tool_call_delta?).should be_true
      item1.try(&.id).should eq("tool-1")
      item1.try(&.internal_call_id).should eq("internal-1")
      item2.should_not be_nil
      item2.try(&.kind.reasoning_delta?).should be_true
      item2.try(&.reasoning_delta).should eq("step")
      item3.should_not be_nil
      item3.try(&.kind.reasoning_delta?).should be_true
      item3.try(&.reasoning_delta).should eq(" one")
      item4.should_not be_nil
      item4.try(&.kind.final?).should be_true
      item5.should be_nil

      response.choice.to_a.size.should eq(1)
      response.choice.first.kind.reasoning?.should be_true
      response.choice.first.reasoning.try(&.content.first.text).should eq("step one")
      response.response.try(&.usage).try(&.total_tokens).should eq(9)
    end

    it "captures message ids silently during stateful iteration" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message_id("msg-live-1"),
        RawStreamingChoice(FinalCompletionResponse).message("hello"),
      ])

      first = response.next_item
      done = response.next_item

      first.should_not be_nil
      first.try(&.kind.text?).should be_true
      first.try(&.text).try(&.text).should eq("hello")
      done.should be_nil
      response.message_id.should eq("msg-live-1")
    end

    it "stops yielding after cancellation" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message("hello 1"),
        RawStreamingChoice(FinalCompletionResponse).message("hello 2"),
        RawStreamingChoice(FinalCompletionResponse).message("hello 3"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 15))
        ),
      ])

      response.next_item.should_not be_nil
      response.next_item.should_not be_nil
      response.cancel

      response.next_item.should be_nil
      response.choice.to_a.size.should eq(1)
      response.choice.first.kind.text?.should be_true
      response.choice.first.text.try(&.text).should eq("hello 1hello 2")
    end

    it "does not advance while paused and resumes iteration afterward" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message("hello 1"),
        RawStreamingChoice(FinalCompletionResponse).message("hello 2"),
      ])

      response.pause
      response.next_item.should be_nil
      response.chunks.should eq([] of String)

      response.resume
      first = response.next_item
      second = response.next_item
      done = response.next_item

      first.should_not be_nil
      first.try(&.kind.text?).should be_true
      first.try(&.text).try(&.text).should eq("hello 1")
      second.should_not be_nil
      second.try(&.kind.text?).should be_true
      second.try(&.text).try(&.text).should eq("hello 2")
      done.should be_nil
      response.choice.first.text.try(&.text).should eq("hello 1hello 2")
    end

    it "yields the final response only once during stateful iteration" do
      response = StreamingCompletionResponse(FinalCompletionResponse).stream_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 3))
        ),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 4))
        ),
      ])

      first = response.next_item
      second = response.next_item

      first.should_not be_nil
      first.try(&.kind.final?).should be_true
      second.should be_nil
      response.final_response_yielded?.should be_true
      response.response.try(&.usage).try(&.total_tokens).should eq(3)
    end

    it "converts into a completion response preserving raw response and message id" do
      response = StreamingCompletionResponse(FinalCompletionResponse).from_raw_choices([
        RawStreamingChoice(FinalCompletionResponse).message_id("msg-convert-1"),
        RawStreamingChoice(FinalCompletionResponse).message("hello"),
        RawStreamingChoice(FinalCompletionResponse).final_response(
          FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 5))
        ),
      ])
      converted = response.to_completion_response

      converted.choice.first.kind.text?.should be_true
      converted.choice.first.text.try(&.text).should eq("hello")
      converted.usage.should eq(Completion::Usage.new)
      converted.raw_response.try(&.usage).try(&.total_tokens).should eq(5)
      converted.message_id.should eq("msg-convert-1")
    end
  end

  describe PauseControl, tags: %w[streaming control] do
    it "tracks paused state" do
      control = PauseControl.new

      control.is_paused.should be_false
      control.pause
      control.is_paused.should be_true
      control.resume
      control.is_paused.should be_false
    end
  end

  describe RawStreamingToolCall, tags: %w[streaming tool_call] do
    it "supports builder-style metadata setters and conversion to tool calls" do
      tool_call = RawStreamingToolCall.new(
        "tool-1",
        "weather",
        JSON.parse(%({"city":"Denver"}))
      ).with_internal_call_id("internal-1")
        .with_call_id("call-1")
        .with_signature("sig")
        .with_additional_params(JSON.parse(%({"source":"test"})))

      converted = tool_call.to_tool_call

      converted.should be_a(Completion::ToolCall)
      converted.call_id.should_not be_nil
      converted.signature.should_not be_nil
      converted.additional_params.should_not be_nil
    end
  end

  describe ToolCallDeltaContent, tags: %w[streaming tool_delta] do
    it "supports name and delta variants" do
      name = ToolCallDeltaContent.name("weather")
      delta = ToolCallDeltaContent.delta("{\"city\":\"Denver\"}")

      name.kind.name?.should be_true
      name.value.should eq("weather")
      delta.kind.delta?.should be_true
      delta.value.should eq("{\"city\":\"Denver\"}")
    end
  end

  describe RawStreamingChoice(String), tags: %w[streaming choice] do
    it "supports message, tool-call, reasoning, final-response, and message-id variants" do
      tool_call = RawStreamingToolCall.new("tool-1", "weather", JSON.parse(%({"city":"Denver"})))
      message = RawStreamingChoice(String).message("hello")
      tool = RawStreamingChoice(String).tool_call(tool_call)
      delta = RawStreamingChoice(String).tool_call_delta("tool-1", "internal-1", ToolCallDeltaContent.delta("{}"))
      reasoning = RawStreamingChoice(String).reasoning("r1", Completion::ReasoningContent.summary("step"))
      reasoning_delta = RawStreamingChoice(String).reasoning_delta("r1", "step")
      final_response = RawStreamingChoice(String).final_response("done")
      message_id = RawStreamingChoice(String).message_id("msg-1")

      message.kind.message?.should be_true
      tool.tool_call.try(&.name).should eq("weather")
      delta.content.try(&.value).should eq("{}")
      reasoning.reasoning_content.try(&.summary).should eq("step")
      reasoning_delta.reasoning_delta.should eq("step")
      final_response.final_response.should eq("done")
      message_id.message_id.should eq("msg-1")
    end
  end

  describe StreamedAssistantContent(FinalCompletionResponse), tags: %w[streaming assistant] do
    it "supports text, tool-call, reasoning, delta, and final variants" do
      tool_call = Completion::ToolCall.new(
        "tool-1",
        Completion::ToolFunction.new("weather", JSON.parse(%({"city":"Denver"})))
      )
      reasoning = Completion::Reasoning.new([Completion::ReasoningContent.summary("step")], "r1")

      text = StreamedAssistantContent(FinalCompletionResponse).text("hello")
      tool = StreamedAssistantContent(FinalCompletionResponse).tool_call(tool_call, "internal-1")
      delta = StreamedAssistantContent(FinalCompletionResponse).tool_call_delta("tool-1", "internal-1", ToolCallDeltaContent.delta("{}"))
      reasoning_item = StreamedAssistantContent(FinalCompletionResponse).reasoning(reasoning)
      reasoning_delta = StreamedAssistantContent(FinalCompletionResponse).reasoning_delta("r1", "step")
      final_response = StreamedAssistantContent(FinalCompletionResponse).final_response(
        FinalCompletionResponse.new(Completion::Usage.new(total_tokens: 2))
      )

      text.text.try(&.text).should eq("hello")
      tool.kind.tool_call?.should be_true
      delta.content.try(&.value).should eq("{}")
      reasoning_item.reasoning.try(&.id).should eq("r1")
      reasoning_delta.reasoning_delta.should eq("step")
      final_response.final.try(&.usage).try(&.total_tokens).should eq(2)
    end
  end

  describe StreamedUserContent, tags: %w[streaming user] do
    it "supports tool-result streaming items" do
      tool_result = Completion::ToolResult.new(
        "tool-1",
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("done")),
        "call-1",
      )
      content = StreamedUserContent.tool_result(tool_result, "internal-1")

      content.kind.tool_result?.should be_true
      content.tool_result.try(&.id).should eq("tool-1")
      content.internal_call_id.should eq("internal-1")
    end
  end

  describe StreamingResult(String), tags: %w[streaming result] do
    it "stores raw streaming choices" do
      result = StreamingResult(String).new([
        RawStreamingChoice(String).message("hello"),
        RawStreamingChoice(String).final_response("done"),
      ])

      result.items.size.should eq(2)
      result.items.last.final_response.should eq("done")
    end
  end
end
