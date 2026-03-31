require "../src/crig"

module Crig::Examples::GeminiAgent
  MODEL    = "gemini-2.5-flash"
  PREAMBLE = "Be creative and concise. Answer directly and clearly."
  PROMPT   = "How much wood would a woodchuck chuck if a woodchuck could chuck wood? Infer an answer."

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
