require "../src/crig"

module Crig::Examples::PerplexityAgent
  PREAMBLE = "Be precise and concise."
  PROMPT   = "When and where and what type is the next solar eclipse?"

  def self.build_agent(
    client : Crig::Providers::Perplexity::Client,
    model : String = Crig::Providers::Perplexity::SONAR,
  ) : Crig::Agent(Crig::Providers::Perplexity::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .additional_params(
        JSON.parse(%({
          "return_related_questions": true,
          "return_images": true
        }))
      )
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
