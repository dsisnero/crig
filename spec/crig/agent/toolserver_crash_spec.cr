require "../../spec_helper"

# Proves: ToolServer#call_tool logic is correct. The crash only happens with
# real HTTP model calls (OpenSSL C bindings), not with mocks.

class MockTextModel
  include Crig::Completion::CompletionModel
  getter call_count : Int32 = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @call_count += 1
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("ok #{@call_count}")),
      Crig::Completion::Usage.new(output_tokens: 1),
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    completion(request)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

module Crig
  describe ToolServer, "agent-as-tool works with mock models" do
    it "executes via ToolServer.new + call_tool" do
      model = MockTextModel.new
      agent = Agent(typeof(model)).new(model, preamble: "test")

      ts = ToolServer.new
      ts.add_tool(AgentToolAdapter.new(agent))

      result = ts.call_tool("agent_tool", %({"prompt":"hi"}))
      result.should eq("ok 1")
    end

    it "executes via ToolServer.new.run + handle.call_tool (inbox bypass)" do
      model = MockTextModel.new
      agent = Agent(typeof(model)).new(model, preamble: "test")

      ts = ToolServer.new
      ts.add_tool(AgentToolAdapter.new(agent))
      handle = ts.run
      result = handle.call_tool("agent_tool", %({"prompt":"hi"}))
      result.should eq("ok 1")
    end
  end
end
