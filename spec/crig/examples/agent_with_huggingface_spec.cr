require "../../spec_helper"
require "../../../examples/agent_with_huggingface"

describe Crig::Examples::AgentWithHuggingFace, tags: %w[examples agent_with_huggingface] do
  it "builds the upstream huggingface partial and basic agent helpers" do
    client = Crig::Providers::HuggingFace::Client.new("test-key")
    builder = Crig::Examples::AgentWithHuggingFace.build_partial_agent(client)
    agent = Crig::Examples::AgentWithHuggingFace.build_basic_agent(client)

    builder.model.model.should eq(Crig::Examples::AgentWithHuggingFace::MODEL)
    agent.model.model.should eq(Crig::Examples::AgentWithHuggingFace::MODEL)
    agent.preamble.should eq(Crig::Examples::AgentWithHuggingFace::BASIC_PREAMBLE)
  end

  it "builds the upstream huggingface tools agent helper" do
    client = Crig::Providers::HuggingFace::Client.new("test-key")
    agent = Crig::Examples::AgentWithHuggingFace.build_tools_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithHuggingFace::TOOLS_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "loads upstream rust examples for the huggingface loader helper" do
    loaded = Crig::Examples::AgentWithHuggingFace.load_examples("vendor/rig/examples/agent/src/main.rs")
    entry = loaded.first.as(Tuple(String, String))

    loaded.size.should eq(1)
    entry[1].includes?("comedian").should be_true
  end

  it "builds the upstream huggingface context agent helper and prompts through a provided agent" do
    client = Crig::Providers::HuggingFace::Client.new("test-key")
    context_agent = Crig::Examples::AgentWithHuggingFace.build_context_agent(client)
    prompt_agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("deepseek-r1")).build

    context_agent.static_context.size.should eq(3)
    Crig::Examples::AgentWithHuggingFace.run_prompt(prompt_agent, "Entertain me!").should eq("completion:deepseek-r1")
  end
end
