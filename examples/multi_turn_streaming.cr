require "../src/crig"
require "./agent_with_default_max_turns"

module Crig::Examples::MultiTurnStreaming
  PREAMBLE = Crig::Examples::AgentWithDefaultMaxTurns::PREAMBLE
  PROMPT   = "Calculate 2 * (3 + 5) / 9  = ?. Describe the result to me."
  TOOLS    = Crig::Examples::AgentWithDefaultMaxTurns::TOOLS

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    builder = client.agent(model)
      .preamble(PREAMBLE)

    TOOLS.each do |tool|
      builder = builder.tool(tool)
    end

    builder.build
  end

  def self.run_stream(
    agent : Crig::Agent(M),
    prompt : String = PROMPT,
    max_turns : Int32 = 10,
  ) : Crig::MultiTurnStreamingResult(Crig::PromptResponse) forall M
    agent.stream_prompt(prompt).max_turns(max_turns).send_items
  end

  def self.stream_to_stdout(result : Crig::MultiTurnStreamingResult(Crig::PromptResponse), io : IO = STDOUT) : Crig::PromptResponse
    final_response = result.items.last.final_response || Crig::PromptResponse.empty
    raw_choices = result.items.compact_map do |item|
      if text = item.assistant_item.try(&.text).try(&.text)
        Crig::RawStreamingChoice(Crig::PromptResponse).message(text)
      elsif response = item.final_response
        Crig::RawStreamingChoice(Crig::PromptResponse).final_response(response)
      end
    end

    assistant_stream = Crig::StreamingCompletionResponse(Crig::PromptResponse).stream(raw_choices)
    Crig.stream_to_stdout(assistant_stream, io)
    final_response
  end
end
