require "../src/crig"

module Crig::Examples::AnthropicThinkTool
  NAME     = "Anthropic Thinker"
  PREAMBLE = <<-TEXT
    You are a helpful assistant that can solve complex problems.
    Use the 'think' tool to reason through complex problems step by step.
    When faced with a multi-step problem or when analyzing tool results,
    use the 'think' tool to organize your thoughts before responding.
  TEXT
  PROMPT = "I need to plan a dinner party for 8 people, including 2 vegetarians and 1 person with a gluten allergy. Can you help me create a menu that everyone can enjoy? Consider appetizers, main courses, and desserts."

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_7_SONNET,
  )
    client.agent(model)
      .name(NAME)
      .preamble(PREAMBLE)
      .tool(Crig::ThinkTool.new)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).max_turns(10).send
  end
end
