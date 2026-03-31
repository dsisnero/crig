require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::DeepSeekStreaming
  BASIC_PREAMBLE      = "You are a helpful assistant."
  CALCULATOR_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."
  PROMPT              = "Tell me a joke"
  CALCULATOR_PROMPT   = "Calculate 2 - 5"

  def self.build_basic_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  )
    client.agent(model)
      .preamble(BASIC_PREAMBLE)
      .build
  end

  def self.build_calculator_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  )
    client.agent(model)
      .preamble(CALCULATOR_PREAMBLE)
      .max_tokens(1024)
      .tools(Crig::Examples::AgentWithTools.tools)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.run_chat(agent : Crig::Agent(M), prompt : String = CALCULATOR_PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_chat(prompt, [] of Crig::Completion::Message).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
