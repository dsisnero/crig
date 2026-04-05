require "../src/crig"
require "./agent_with_default_max_turns"

module Crig::Examples::MultiTurnStreamingGemini
  PREAMBLE = "You are an calculator. You must use tools to get the user result"
  PROMPT   = "Calculate 2 * (3 + 5) / 9  = ?. Describe the result to me."
  TOOLS    = Crig::Examples::AgentWithDefaultMaxTurns::TOOLS

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_5_FLASH,
  ) : Crig::Agent(Crig::Providers::Gemini::CompletionModel)
    builder = client.agent(model).preamble(PREAMBLE)
    TOOLS.each do |tool|
      builder = builder.tool(tool)
    end
    builder.build
  end

  def self.run_stream(
    agent : Crig::Agent(M),
    prompt : String = PROMPT,
    max_turns : Int32 = 10,
  ) : Crig::MultiTurnStreamingResult(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).multi_turn(max_turns).send_items
  end

  def self.stream_to_stdout(result : Crig::MultiTurnStreamingResult(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    final_response = result.items.last.final_response || Crig::FinalResponse.empty
    raw_choices = result.items.compact_map do |item|
      if text = item.assistant_item.try(&.text).try(&.text)
        Crig::RawStreamingChoice(Crig::FinalResponse).message(text)
      elsif response = item.final_response
        Crig::RawStreamingChoice(Crig::FinalResponse).final_response(response)
      end
    end

    Crig.stream_to_stdout(Crig::StreamingCompletionResponse(Crig::FinalResponse).stream(raw_choices), io)
    final_response
  end
end
