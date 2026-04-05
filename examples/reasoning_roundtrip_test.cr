require "../src/crig"

module Crig::Examples::ReasoningRoundtripTest
  PREAMBLE      = "You are a helpful math tutor. Be concise."
  TURN_1_PROMPT = "A train leaves Station A at 60 km/h. Another train leaves Station B (300 km away) 30 minutes later at 90 km/h heading toward Station A. At what time do they meet, and how far from Station A? Show your work."
  TURN_2_PROMPT = "Now suppose both trains slow down by 10 km/h after traveling half the original distance. When do they meet now?"

  struct TestAgent(M)
    getter model : M
    getter preamble : String
    getter additional_params : JSON::Any?

    def initialize(@model : M, @preamble : String, @additional_params : JSON::Any? = nil)
    end
  end

  record TurnStats,
    assistant_content : Array(Crig::Completion::AssistantContent),
    reasoning_count : Int32,
    reasoning_delta_count : Int32,
    text_chunks : Int32,
    streamed_text : String,
    message_id : String?

  def self.build_anthropic(
    client : Crig::Providers::Anthropic::Client = Crig::Providers::Anthropic::Client.from_env,
  ) : TestAgent(Crig::Providers::Anthropic::CompletionModel)
    TestAgent(Crig::Providers::Anthropic::CompletionModel).new(
      client.completion_model(Crig::Providers::Anthropic::CLAUDE_4_SONNET),
      PREAMBLE,
      JSON.parse(%({"thinking":{"type":"enabled","budget_tokens":2048}})),
    )
  end

  def self.build_gemini(
    client : Crig::Providers::Gemini::Client = Crig::Providers::Gemini::Client.from_env,
  ) : TestAgent(Crig::Providers::Gemini::CompletionModel)
    TestAgent(Crig::Providers::Gemini::CompletionModel).new(
      client.completion_model(Crig::Providers::Gemini::GEMINI_2_5_FLASH),
      PREAMBLE,
      JSON.parse(%({"generationConfig":{"thinkingConfig":{"thinkingBudget":2048,"includeThoughts":true}}})),
    )
  end

  def self.build_openai(
    client : Crig::Providers::OpenAI::Client = Crig::Providers::OpenAI::Client.from_env,
  ) : TestAgent(Crig::Providers::OpenAI::ResponsesCompletionModel)
    TestAgent(Crig::Providers::OpenAI::ResponsesCompletionModel).new(
      client.completion_model("gpt-5.2"),
      PREAMBLE,
      JSON.parse(%({"reasoning":{"effort":"medium"}})),
    )
  end

  def self.build_openrouter(
    client : Crig::Providers::OpenRouter::Client = Crig::Providers::OpenRouter::Client.from_env,
  ) : TestAgent(Crig::Providers::OpenRouter::CompletionModel)
    TestAgent(Crig::Providers::OpenRouter::CompletionModel).new(
      client.completion_model("openai/gpt-5.2"),
      PREAMBLE,
      JSON.parse(%({"reasoning":{"effort":"medium"},"include_reasoning":true})),
    )
  end

  def self.turn_1_request(agent : TestAgent(M), prompt : String = TURN_1_PROMPT) : Crig::Completion::Request::CompletionRequest forall M
    build_request(agent, [Crig::Completion::Message.user(prompt)])
  end

  def self.turn_2_request(
    agent : TestAgent(M),
    turn_1_prompt : Crig::Completion::Message,
    turn_1_assistant : Crig::Completion::Message,
    prompt : String = TURN_2_PROMPT,
  ) : Crig::Completion::Request::CompletionRequest forall M
    build_request(agent, [turn_1_prompt, turn_1_assistant, Crig::Completion::Message.user(prompt)])
  end

  def self.consume_turn(
    stream : Crig::StreamingCompletionResponse(R),
    io : IO = IO::Memory.new,
  ) : TurnStats forall R
    assistant_content = [] of Crig::Completion::AssistantContent
    reasoning_count = 0
    reasoning_delta_count = 0
    text_chunks = 0
    streamed_text = ""
    reasoning_delta_text = ""

    stream.each_item do |chunk|
      case chunk.kind
      in .text?
        if text = chunk.text
          io.print(text.text)
          streamed_text += text.text
          text_chunks += 1
        end
      in .reasoning?
        if reasoning = chunk.reasoning
          assistant_content << Crig::Completion::AssistantContent.new(
            Crig::Completion::AssistantContent::Kind::Reasoning,
            reasoning: reasoning,
          )
          reasoning_count += 1
          io.print(reasoning.display_text)
        end
      in .reasoning_delta?
        if delta = chunk.reasoning_delta
          reasoning_delta_count += 1
          reasoning_delta_text += delta
          io.print(delta)
        end
      in .tool_call?
      in .tool_call_delta?
      in .final?
      end
    end

    if reasoning_count == 0 && !reasoning_delta_text.empty?
      reasoning = Crig::Completion::Reasoning.new(reasoning_delta_text)
      if message_id = stream.message_id
        reasoning = reasoning.with_id(message_id)
      end
      assistant_content << Crig::Completion::AssistantContent.new(
        Crig::Completion::AssistantContent::Kind::Reasoning,
        reasoning: reasoning,
      )
      reasoning_count = 1
    end

    assistant_content << Crig::Completion::AssistantContent.text(streamed_text) unless streamed_text.empty?

    TurnStats.new(
      assistant_content,
      reasoning_count,
      reasoning_delta_count,
      text_chunks,
      streamed_text,
      stream.message_id,
    )
  end

  def self.assistant_message(stats : TurnStats) : Crig::Completion::Message
    mixed = stats.assistant_content.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
    Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(mixed),
      stats.message_id,
    )
  end

  def self.run_test(agent : TestAgent(M), io : IO = IO::Memory.new) : {TurnStats, TurnStats} forall M
    turn_1_prompt = Crig::Completion::Message.user(TURN_1_PROMPT)
    turn_1_stream = agent.model.stream(turn_1_request(agent))
    turn_1 = consume_turn(turn_1_stream, io)
    turn_2_stream = agent.model.stream(
      turn_2_request(agent, turn_1_prompt, assistant_message(turn_1))
    )
    {turn_1, consume_turn(turn_2_stream, io)}
  end

  private def self.build_request(agent : TestAgent(M), chat_history : Array(Crig::Completion::Message)) : Crig::Completion::Request::CompletionRequest forall M
    Crig::Completion::Request::CompletionRequest.new(
      preamble: agent.preamble,
      chat_history: Crig::OneOrMany(Crig::Completion::Message).many(chat_history),
      documents: [] of Crig::Completion::Request::Document,
      tools: [] of Crig::Completion::ToolDefinition,
      temperature: nil,
      max_tokens: nil,
      tool_choice: nil,
      additional_params: agent.additional_params,
      model: nil,
      output_schema: nil,
    )
  end
end
