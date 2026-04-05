require "../src/crig"
require "./agent_with_default_max_turns"

module Crig::Examples::ReasoningLoop
  CHAIN_OF_THOUGHT_PROMPT = <<-TEXT
  You are an assistant that extracts reasoning steps from a given prompt.
  Do not return text, only return a tool call.
  TEXT

  EXECUTOR_PREAMBLE = <<-TEXT
  You are an assistant here to help the user select which tool is most appropriate to perform arithmetic operations.
  Follow these instructions closely.
  1. Consider the user's request carefully and identify the core elements of the request.
  2. Select which tool among those made available to you is appropriate given the context.
  3. This is very important: never perform the operation yourself.
  4. When you think you've finished calling tools for the operation, present the final result from the series of tool calls you made.
  TEXT

  PROMPT = "Calculate ((15 + 25) * (100 - 50)) / (200 / (10 + 10))"

  struct ChainOfThoughtSteps
    include JSON::Serializable

    getter steps : Array(String)

    def initialize(@steps : Array(String))
    end
  end

  struct ReasoningAgent(M)
    getter chain_of_thought_extractor : Crig::Extractor(M, ChainOfThoughtSteps)
    getter executor : Crig::Agent(M)

    def initialize(
      @chain_of_thought_extractor : Crig::Extractor(M, ChainOfThoughtSteps),
      @executor : Crig::Agent(M),
    )
    end

    def prompt(prompt : Crig::Completion::Message | String) : String
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      chat_history = [prompt_message]
      extracted = @chain_of_thought_extractor.extract(prompt_message)
      return "No reasoning steps provided." if extracted.steps.empty?

      reasoning_prompt = extracted.steps.each_with_index.map { |step, index| "Step #{index + 1}: #{step}" }.join('\n')
      @executor.prompt(reasoning_prompt).with_history(chat_history).max_turns(20).send
    end
  end

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : ReasoningAgent(Crig::Providers::Anthropic::CompletionModel)
    extractor = client.extractor(ChainOfThoughtSteps, model)
      .preamble(CHAIN_OF_THOUGHT_PROMPT)
      .build

    builder = client.agent(model).preamble(EXECUTOR_PREAMBLE)
    Crig::Examples::AgentWithDefaultMaxTurns::TOOLS.each do |tool|
      builder = builder.tool(tool)
    end

    ReasoningAgent(Crig::Providers::Anthropic::CompletionModel).new(extractor, builder.build)
  end

  def self.run_prompt(
    agent : ReasoningAgent(M),
    prompt : Crig::Completion::Message | String = PROMPT,
  ) : String forall M
    agent.prompt(prompt)
  end
end
