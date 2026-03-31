require "../src/crig"

module Crig::Examples::AgentWithLoaders
  def self.load_examples(glob : String = "vendor/rig/rig/rig-core/examples/*.rs")
    Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError)
      .with_glob(glob)
      .read_with_path
      .ignore_errors
      .to_a
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
    glob : String = "vendor/rig/rig/rig-core/examples/*.rs",
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    builder = client.agent(model)
    load_examples(glob).each do |path, content|
      builder = builder.context(%(Rust Example #{path.inspect}:\n#{content}))
    end
    builder.build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Which rust example is best suited for the operation 1 + 2") : String forall M
    agent.prompt(prompt).send
  end
end
