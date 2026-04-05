require "../src/crig"

module Crig::Examples::DiscordBot
  PREAMBLE = "You are a helpful assistant."
  MODEL    = Crig::Providers::OpenAI::GPT_4O

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.build_bot(
    agent : Crig::Agent(M),
    token : String,
  ) forall M
    agent.into_discord_bot(token)
  end

  def self.build_bot_from_env(
    agent : Crig::Agent(M),
  ) forall M
    agent.into_discord_bot_from_env
  end
end
