require "../../spec_helper"
require "../../../examples/agent_with_loaders"

describe Crig::Examples::AgentWithLoaders, tags: %w[examples agent_with_loaders] do
  it "loads upstream rust example files through the file loader helper" do
    loaded = Crig::Examples::AgentWithLoaders.load_examples("vendor/rig/examples/agent/src/main.rs")
    entry = loaded.first.as(Tuple(String, String))

    loaded.size.should eq(1)
    entry[0].ends_with?("vendor/rig/examples/agent/src/main.rs").should be_true
    entry[1].includes?("comedian").should be_true
  end

  it "builds the upstream loader-backed context agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithLoaders.build_agent(
      client,
      glob: "vendor/rig/examples/agent/src/main.rs"
    )

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.static_context.size.should eq(1)
    agent.static_context.first.text.includes?("Rust Example").should be_true
  end

  it "runs the loader-backed example prompt through a provided agent" do
    Crig::Examples::AgentWithLoaders.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    ).should eq("completion:gpt-4o")
  end
end
