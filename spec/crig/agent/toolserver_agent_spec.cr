require "../../spec_helper"

# Mock model that returns simple text
class MockAgentModel
  include Crig::Completion::CompletionModel
  getter last_request : Crig::Completion::Request::CompletionRequest?

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @last_request = request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("mocked response")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

module Crig
  describe ToolServerHandle, "agent-as-tool" do
    it "calls agent tool through server.call_tool directly" do
      mock_model = MockAgentModel.new
      agent = Agent(typeof(mock_model)).new(mock_model, preamble: "calc")

      ts = ToolServer.new
      adapter = AgentToolAdapter.new(agent)
      ts.add_tool(adapter)

      result = ts.call_tool("agent_tool", %({"prompt": "What is 2 + 5?"}))
      result.should contain("mocked")
    end

    it "calls agent tool through handle.call_tool (server path)" do
      mock_model = MockAgentModel.new
      agent = Agent(typeof(mock_model)).new(mock_model, preamble: "calc")

      ts = ToolServer.new
      adapter = AgentToolAdapter.new(agent)
      ts.add_tool(adapter)
      handle = ts.run # returns handle with @server=ts

      result = handle.call_tool("agent_tool", %({"prompt": "What is 2 + 5?"}))
      result.should contain("mocked")
    end
  end
end
