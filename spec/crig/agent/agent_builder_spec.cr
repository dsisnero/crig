require "../../spec_helper"
describe Crig::Agent(FakeCompletionClientModel), tags: %w[agent] do
  it "builds completion requests with static agent configuration" do
    model = FakeCompletionClientModel.new("gpt-4o")
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .name("assistant")
      .preamble("Be concise.")
      .context("Denver is cold.")
      .tool(weather_tool)
      .temperature(0.3)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .output_schema(JSON.parse(%({"title":"answer"})))
      .build

    agent.prompt("What is the weather?").send

    request = model.last_request

    agent.resolved_name.should eq("assistant")
    request.should_not be_nil
    built = request.not_nil!
    built.preamble.should eq("Be concise.")
    built.documents.map(&.text).should eq(["Denver is cold."])
    built.tools.map(&.name).should eq(["weather"])
    built.temperature.should eq(0.3)
    built.max_tokens.should eq(128)
    built.tool_choice.try(&.kind.required?).should be_true
    built.additional_params.try(&.["mode"].as_s).should eq("strict")
    built.output_schema.try(&.["title"].as_s).should eq("answer")
  end

  it "merges dynamic context and tools from rag text in chat history" do
    model = FakeCompletionClientModel.new("gpt-4o")
    embedding_model = FakeEmbeddingsClientModel.new("embed", 1)
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {
        "doc-1",
        StoredDoc.new("doc-1", "Denver"),
        vector_embedding("Denver weather", [1.0]),
      },
    ])
    index = store.index(embedding_model)
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .dynamic_context(1, index)
      .dynamic_tools(1, index, [weather_tool])
      .build

    prompt = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("How can I help?")
      ),
    )
    history = [Crig::Completion::Message.user("Please use weather retrieval for Denver")]

    request = agent.build_completion_request(prompt, history).build

    request.documents.map(&.id).should contain("doc-1")
    request.tools.map(&.name).should eq(["weather"])
  end

  it "queries dynamic context sources concurrently" do
    model = FakeCompletionClientModel.new("gpt-4o")
    started = Atomic(Int32).new(0)

    build_source = ->(id : String) do
      Crig::DynamicContextSource.new(
        1,
        ->(request : Crig::VectorSearchRequest) do
          request.query.should eq("retrieve Denver")
          started.add(1)
          deadline = Time.instant + 200.milliseconds
          until started.get == 2
            raise "dynamic context source did not overlap" if Time.instant >= deadline
            Fiber.yield
          end
          [{1.0, id, JSON.parse(%("payload-#{id}"))}]
        end
      )
    end

    agent = Crig::Agent(FakeCompletionClientModel).new(
      model,
      dynamic_context: [build_source.call("doc-1"), build_source.call("doc-2")]
    )

    request = agent.build_completion_request("retrieve Denver").build

    request.documents.map(&.id).should eq(["doc-1", "doc-2"])
  end

  it "queries dynamic tool sources concurrently" do
    model = FakeCompletionClientModel.new("gpt-4o")
    started = Atomic(Int32).new(0)

    build_source = ->(tool_name : String) do
      tool = Crig::Completion::ToolDefinition.new(
        tool_name,
        "Lookup #{tool_name}",
        JSON.parse(%({"type":"object"})),
      )

      Crig::DynamicToolSource.new(
        1,
        [tool],
        ->(request : Crig::VectorSearchRequest) do
          request.query.should eq("lookup Denver")
          started.add(1)
          deadline = Time.instant + 200.milliseconds
          until started.get == 2
            raise "dynamic tool source did not overlap" if Time.instant >= deadline
            Fiber.yield
          end
          [{1.0, "#{tool_name}-hit", JSON.parse(%("ok"))}]
        end
      )
    end

    agent = Crig::Agent(FakeCompletionClientModel).new(
      model,
      dynamic_tools: [build_source.call("weather"), build_source.call("calendar")]
    )

    request = agent.build_completion_request("lookup Denver").build

    request.tools.map(&.name).should eq(["weather", "calendar"])
  end

  it "falls back to the upstream unknown-agent name constant" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    agent.resolved_name.should eq("Unnamed Agent")
  end

  it "builds prompt requests with history and extended details" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    history = [Crig::Completion::Message.user("Earlier")]

    request = agent.prompt("Hello").max_turns(2).with_tool_concurrency(3).with_history(history)
    response = request.extended_details.send

    request.max_turns.should eq(2)
    request.concurrency.should eq(3)
    response.output.should eq("completion:gpt-4o")
    response.usage.output_tokens.should eq(1)
    response.messages.should_not be_nil
    response.messages.try(&.size).should eq(3)
  end

  it "applies per-request overrides through the prompt request builder" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .preamble("Be concise.")
      .temperature(0.3)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .build

    agent.prompt("Hello")
      .preamble("Override.")
      .temperature(0.7)
      .max_tokens(256)
      .tool_choice(Crig::Completion::ToolChoice.auto)
      .additional_params(JSON.parse(%({"mode":"relaxed"})))
      .send

    request = model.last_request
    request.should_not be_nil
    request.try(&.preamble).should eq("Override.")
    request.try(&.temperature).should eq(0.7)
    request.try(&.max_tokens).should eq(256)
    request.try(&.tool_choice).try(&.kind.auto?).should be_true
    request.try(&.additional_params).try(&.["mode"].as_s).should eq("relaxed")
  end

  it "clears agent configuration with without_* overrides" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .preamble("Be concise.")
      .temperature(0.3)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .build

    agent.prompt("Hello")
      .without_preamble
      .without_temperature
      .without_max_tokens
      .without_tool_choice
      .without_additional_params
      .send

    request = model.last_request
    request.should_not be_nil
    request.try(&.preamble).should be_nil
    request.try(&.temperature).should be_nil
    request.try(&.max_tokens).should be_nil
    request.try(&.tool_choice).should be_nil
    request.try(&.additional_params).should be_nil
  end

  it "forwards overrides and without_* through the typed prompt request" do
    model = FixedJSONCompletionModel.new(%("hello"))
    agent = Crig::AgentBuilder(FixedJSONCompletionModel).new(model)
      .preamble("Be concise.")
      .temperature(0.3)
      .build

    result = agent.prompt_typed(String, "Hello")
      .temperature(0.9)
      .without_preamble
      .max_tokens(64)
      .send

    result.should eq("hello")
    request = model.last_request
    request.should_not be_nil
    request.try(&.preamble).should be_nil
    request.try(&.temperature).should eq(0.9)
    request.try(&.max_tokens).should eq(64)
  end

  it "supports agent chat through the prompt-request path" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    history = [Crig::Completion::Message.user("Earlier")]

    response = agent.chat("Hello", history)

    response.should eq("completion:gpt-4o")
  end

  it "builds the upstream agent tool definition" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .name("sub-agent")
      .description("Handles delegated tasks")
      .preamble("Stay concise.")
      .build

    adapter = Crig::AgentToolAdapter.new(agent)
    definition = Crig.tool_definition(adapter)

    definition.name.should eq("sub-agent")
    definition.description.should contain("Prompt a sub-agent to do a task for you")
    definition.description.should contain("Agent name: sub-agent")
    definition.description.should contain("Agent description: Handles delegated tasks")
    definition.description.should contain("Agent system prompt: Stay concise.")
    definition.parameters["required"][0].as_s.should eq("prompt")
  end

  it "falls back to the upstream default agent tool name" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    adapter = Crig::AgentToolAdapter.new(agent)

    Crig.tool_definition(adapter).name.should eq("agent_tool")
  end

  it "can be called as a sub-agent tool" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    agent.call(Crig::AgentToolArgs.new("delegate this")).should eq("completion:gpt-4o")
  end
end

describe Crig::WithBuilderTools do
  it "stores static tool definitions" do
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )

    wrapper = Crig::WithBuilderTools.new([weather_tool])

    wrapper.static_tools.map(&.name).should eq(["weather"])
  end
end

describe Crig::WithToolServerHandle do
  it "stores the provided tool server handle" do
    handle = Crig::ToolServerHandle.new("shared-tools")

    wrapper = Crig::WithToolServerHandle.new(handle)

    wrapper.handle.id.should eq("shared-tools")
  end

  it "implements streaming traits" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    # Verify Agent includes streaming traits
    agent.should be_a(Crig::StreamingPrompt(FakeCompletionClientModel))
    agent.should be_a(Crig::StreamingChat(FakeCompletionClientModel))
  end
end

describe Crig::AgentToolArgs do
  it "round-trips the delegated prompt payload" do
    payload = Crig::AgentToolArgs.new("delegate this")
    roundtrip = Crig::AgentToolArgs.from_json(payload.to_json)

    roundtrip.prompt.should eq("delegate this")
  end
end

describe Crig::PromptResponse do
  it "stores output, usage, and optional messages" do
    response = Crig::PromptResponse.new("hello", Crig::Completion::Usage.new(total_tokens: 2))
      .with_messages([Crig::Completion::Message.user("hello")])

    response.to_s.should eq("hello")
    response.usage.total_tokens.should eq(2)
    response.messages.try(&.size).should eq(1)
  end
end

describe Crig::PromptResponse do
  it "supports the upstream empty helper and accessors" do
    response = Crig::PromptResponse.empty

    response.output.should eq("")
    response.usage.total_tokens.should eq(0)
    response.messages.should be_nil
  end
end

describe Crig::MultiTurnStreamItem(String) do
  it "builds final-response items without history" do
    item = Crig::MultiTurnStreamItem(String).final_response(
      "done",
      Crig::Completion::Usage.new(total_tokens: 1),
    )

    item.kind.final_response?.should be_true
    item.final_response.try(&.output).should eq("done")
    item.final_response.try(&.messages).should be_nil
  end

  it "builds final-response items with history" do
    history = [Crig::Completion::Message.user("hello")]
    item = Crig::MultiTurnStreamItem(String).final_response_with_history(
      "done",
      Crig::Completion::Usage.new(total_tokens: 2),
      history,
    )

    item.kind.final_response?.should be_true
    item.final_response.try(&.output).should eq("done")
    item.final_response.try(&.messages).should eq(history)
  end
end

describe Crig::StreamingError do
  it "builds parity-style streaming error wrappers" do
    completion = Crig::StreamingError.completion("boom")
    prompt = Crig::StreamingError.prompt("stop")
    tool = Crig::StreamingError.tool("missing")

    completion.message.should eq("CompletionError: boom")
    completion.kind.should eq(Crig::StreamingError::Kind::Completion)
    prompt.message.should eq("PromptError: stop")
    prompt.kind.should eq(Crig::StreamingError::Kind::Prompt)
    tool.message.should eq("ToolSetError: missing")
    tool.kind.should eq(Crig::StreamingError::Kind::Tool)
  end

  it "retains wrapped prompt error context in streaming errors" do
    prompt_error = Crig::Completion::PromptError.prompt_cancelled(
      [Crig::Completion::Message.user("hello")],
      "stop",
    )
    error = Crig::StreamingError.prompt(prompt_error)

    error.message.should eq("PromptError: PromptCancelled: stop")
    error.kind.should eq(Crig::StreamingError::Kind::Prompt)
    error.prompt_error.should eq(prompt_error)
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("hello")])
  end
end

describe Crig::StreamingPromptRequest(FakeCompletionClientModel) do
  it "builds requests from an agent with default max turns" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o"))
      .default_max_turns(2)
      .build
    request = Crig::StreamingPromptRequest(FakeCompletionClientModel).from_agent(agent, "hello")

    request.prompt.rag_text.should eq("hello")
    request.max_turns.should eq(2)
  end

  it "streams prompts through the agent model and packages a final response" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    response = agent.stream_prompt("hello").send

    response.chunks.should eq(["chunk:gpt-4o"])
    response.response.try(&.output).should eq("chunk:gpt-4o")
    response.response.try(&.messages).should be_nil
  end

  it "builds stream items for the one-shot streaming path" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    result = agent.stream_prompt("hello").send_items

    result.items.size.should eq(3)
    result.items[0].kind.stream_assistant_item?.should be_true
    result.items[0].assistant_item.try(&.text).try(&.text).should eq("chunk:gpt-4o")
    result.items[1].kind.stream_assistant_item?.should be_true
    result.items[1].assistant_item.try(&.kind.final?).should be_true
    result.items[1].assistant_item.try(&.final).try(&.output).should eq("chunk:gpt-4o")
    result.items[1].assistant_item.try(&.final).try(&.usage).try(&.total_tokens).should eq(3)
    result.items[2].kind.final_response?.should be_true
    result.items[2].final_response.try(&.output).should eq("chunk:gpt-4o")
    result.items[2].final_response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "supports streaming chat history" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    history = [Crig::Completion::Message.user("earlier")]

    response = agent.stream_chat("hello", history).send

    response.response.try(&.messages).try(&.size).should eq(3)
  end
end

describe Crig::StreamingPromptRequest(FakeStreamingAgentModel) do
  it "passes through reasoning assistant items" do
    agent = Crig::AgentBuilder(FakeStreamingAgentModel).new(
      FakeStreamingAgentModel.new(FakeStreamingAgentModel::Mode::Reasoning)
    ).build

    result = agent.stream_prompt("hello").send_items

    result.items.size.should eq(2)
    result.items[0].kind.stream_assistant_item?.should be_true
    result.items[0].assistant_item.try(&.kind.reasoning?).should be_true
    result.items[0].assistant_item.try(&.reasoning).try(&.id).should eq("r1")
    result.items[0].assistant_item.try(&.reasoning).try(&.display_text).should eq("step one")
    result.items[1].kind.final_response?.should be_true
    result.items[1].final_response.try(&.usage).try(&.total_tokens).should eq(1)
  end
end

describe Crig::StreamingPromptRequest(FakeMultiTurnStreamingModel) do
  it "continues after a streamed tool call turn" do
    model = FakeMultiTurnStreamingModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    result = agent.stream_prompt("do tool work").max_turns(3).send_items

    saw_tool_call = false
    saw_tool_result = false
    saw_final_response = false
    final_text = ""

    result.items.each do |item|
      case item.kind
      in .stream_assistant_item?
        assistant_item = item.assistant_item
        next unless assistant_item

        if assistant_item.kind.tool_call?
          saw_tool_call = true
        elsif assistant_item.kind.text?
          final_text += assistant_item.text.try(&.text) || ""
        end
      in .stream_user_item?
        saw_tool_result = true if item.user_item.try(&.kind.tool_result?)
      in .tool_execution_committed?
        item.tool_results
      in .final_response?
        saw_final_response = true
      end
    end

    saw_tool_call.should be_true
    saw_tool_result.should be_true
    saw_final_response.should be_true
    final_text.should eq("done")
    model.turn_counter.should eq(2)
  end

  it "raises after consecutive tool-call turns exceed max turns" do
    model = FakeMultiTurnStreamingModel.new(2)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    expect_raises(Crig::StreamingError, "PromptError: MaxTurnsExceeded: 1") do
      agent.stream_prompt("do tool work").max_turns(1).send_items
    end
  end
end

describe Crig::StreamingPromptRequest(FakeConcurrentToolTurnStreamingModel) do
  it "executes streamed tool calls concurrently within a turn" do
    started = Atomic(Int32).new(0)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(name : String, _args : String) do
      started.add(1)
      deadline = Time.instant + 200.milliseconds
      until started.get == 2
        raise "streamed tool call did not overlap" if Time.instant >= deadline
        Fiber.yield
      end
      "#{name}-result"
    end)

    agent = Crig::AgentBuilder(FakeConcurrentToolTurnStreamingModel).new(FakeConcurrentToolTurnStreamingModel.new)
      .tool_server_handle(handle)
      .build

    result = agent.stream_prompt("do tool work").max_turns(2).send_items

    tool_result_texts = result.items.compact_map do |item|
      next unless user_item = item.user_item
      next unless tool_result = user_item.tool_result
      tool_result.content.first?.try(&.text).try(&.text)
    end

    tool_result_texts.should eq(["tool_one-result", "tool_two-result"])
  end

  it "sustains repeated multi-tool streaming turns under load" do
    iterations = 25

    iterations.times do
      started = Atomic(Int32).new(0)
      handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(name : String, _args : String) do
        started.add(1)
        deadline = Time.instant + 200.milliseconds
        until started.get == 2
          raise "streamed tool call did not overlap" if Time.instant >= deadline
          Fiber.yield
        end
        "#{name}-result"
      end)

      agent = Crig::AgentBuilder(FakeConcurrentToolTurnStreamingModel).new(FakeConcurrentToolTurnStreamingModel.new)
        .tool_server_handle(handle)
        .build

      result = agent.stream_prompt("do tool work").max_turns(2).send_items

      tool_result_texts = result.items.compact_map do |item|
        next unless user_item = item.user_item
        next unless tool_result = user_item.tool_result
        tool_result.content.first?.try(&.text).try(&.text)
      end

      tool_result_texts.should eq(["tool_one-result", "tool_two-result"])
      result.items.any? { |item| item.final_response.try(&.output) == "done" }.should be_true
    end
  end
end

describe Crig::StreamingPromptRequest(FakeDeltaStreamingModel) do
  it "passes through reasoning delta stream items and assembles them into the next-turn assistant history" do
    agent = Crig::AgentBuilder(FakeDeltaStreamingModel).new(
      FakeDeltaStreamingModel.new(FakeDeltaStreamingModel::Mode::ReasoningDeltaAndToolCall)
    ).tool_server_handle(
      Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    ).default_max_turns(2).build

    result = agent.stream_prompt("hello").with_history([] of Crig::Completion::Message).send_items

    result.items.size.should eq(8)
    result.items[0].assistant_item.try(&.kind.reasoning_delta?).should be_true
    result.items[0].assistant_item.try(&.reasoning_delta).should eq("step")
    result.items[1].assistant_item.try(&.kind.reasoning_delta?).should be_true
    result.items[1].assistant_item.try(&.reasoning_delta).should eq(" one")
    result.items[2].assistant_item.try(&.kind.tool_call?).should be_true
    result.items[3].kind.tool_execution_committed?.should be_true
    result.items[4].user_item.try(&.kind.tool_result?).should be_true
    result.items[5].assistant_item.try(&.kind.text?).should be_true
    result.items[5].assistant_item.try(&.text).try(&.text).should eq("done")
    result.items[6].assistant_item.try(&.kind.final?).should be_true
    result.items[6].assistant_item.try(&.final).try(&.output).should eq("done")
    result.items[6].assistant_item.try(&.final).try(&.usage).try(&.total_tokens).should eq(4)
    final_history = result.items.last.final_response.try(&.messages)
    final_history.should_not be_nil
    assistant_message = final_history.try(&.find do |message|
      message.role.assistant? && message.content.any? do |content|
        content.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          .as(Crig::Completion::AssistantContent).kind.reasoning?
      end
    end)
    assistant_message.should_not be_nil
    assistant_content = assistant_message.try(&.content.first).try(&.as(Crig::Completion::AssistantContent))
    assistant_content.should_not be_nil
    assistant_content.try(&.kind.reasoning?).should be_true
    assistant_content.try(&.reasoning).try(&.content.first.text).should eq("step one")
  end
end

describe "Crig streaming helpers" do
  it "merges reasoning blocks preserving order and signatures for matching ids" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new(
      [Crig::Completion::ReasoningContent.text("step-1", "sig-1")],
      "rs_1",
    )
    second = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("step-2", "sig-2"),
        Crig::Completion::ReasoningContent.summary("summary"),
      ],
      "rs_1",
    )

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, second)

    accumulated.size.should eq(1)
    merged = accumulated.first
    merged.id.should eq("rs_1")
    merged.content.size.should eq(3)
    merged.content[0].text.should eq("step-1")
    merged.content[0].signature.should eq("sig-1")
    merged.content[1].text.should eq("step-2")
    merged.content[1].signature.should eq("sig-2")
  end

  it "keeps distinct reasoning ids as separate items" do
    accumulated = [
      Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("step-1")], "rs_a"),
    ]
    incoming = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("step-2")], "rs_b")

    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should eq("rs_a")
    accumulated[1].id.should eq("rs_b")
  end

  it "keeps nil reasoning ids as separate items" do
    accumulated = [
      Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("first")]),
    ]
    incoming = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("second")])

    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should be_nil
    accumulated[1].id.should be_nil
    accumulated[0].content[0].text.should eq("first")
    accumulated[1].content[0].text.should eq("second")
  end

  it "converts tool results to user messages with optional call ids" do
    message = Crig.tool_result_to_user_message("tool-1", "call-1", "done")

    message.role.user?.should be_true
    content = message.content.first
    content.should be_a(Crig::Completion::UserContent)
    user_content = content.as(Crig::Completion::UserContent)
    user_content.kind.tool_result?.should be_true
    result = user_content.tool_result
    result.should_not be_nil
    result.try(&.id).should eq("tool-1")
    result.try(&.call_id).should eq("call-1")
    result.try(&.content.first.text).try(&.text).should eq("done")
  end

  it "streams assistant chunks to an io and returns the final response" do
    items = Crig::MultiTurnStreamingResult(Crig::PromptResponse).new([
      Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
        Crig::StreamedAssistantContent(Crig::PromptResponse).text("hello ")
      ),
      Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
        Crig::StreamedAssistantContent(Crig::PromptResponse).text("world")
      ),
      Crig::MultiTurnStreamItem(Crig::PromptResponse).final_response_with_history(
        "hello world",
        Crig::Completion::Usage.new(total_tokens: 2),
        [Crig::Completion::Message.user("hello")],
      ),
    ])
    io = IO::Memory.new

    final_response = Crig.stream_to_stdout(items, io)

    io.to_s.should eq("Response: hello world")
    final_response.output.should eq("hello world")
    final_response.usage.total_tokens.should eq(2)
  end
end
