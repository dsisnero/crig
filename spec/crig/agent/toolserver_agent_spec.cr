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

    it "into_tool returns a DynamicTool with the agent name" do
      mock_model = MockAgentModel.new
      agent = Agent(typeof(mock_model)).new(mock_model, preamble: "calc", name: "researcher")

      tool = agent.into_tool

      tool.should be_a(DynamicTool)
      tool.name.should eq("researcher")
      tool.description.should contain("Prompt a sub-agent to do a task for you")
      tool.parameters["required"][0].as_s.should eq("prompt")
    end

    it "into_tool falls back to the default agent tool name" do
      mock_model = MockAgentModel.new
      agent = Agent(typeof(mock_model)).new(mock_model, preamble: "calc")

      agent.into_tool.name.should eq("agent_tool")
    end

    it "into_tool invokes the sub-agent with the prompt" do
      mock_model = MockAgentModel.new
      agent = Agent(typeof(mock_model)).new(mock_model, preamble: "calc")

      tool = agent.into_tool
      result = tool.call(%({"prompt": "What is 2 + 5?"}))

      result.should contain("mocked")
      mock_model.last_request.not_nil!.chat_history.last.rag_text.should eq("What is 2 + 5?")
    end

    it "into_tool propagates inbound context values into the sub-agent" do
      observed = Atomic(String?).new(nil)
      probe = DynamicTool.new("context_probe", "Reads context", JSON.parse(%({"type":"object"}))) do |args, ctx|
        observed.set(ctx.get(String))
        Tool::ToolResult.success(Tool::ToolOutput.text("probed"))
      end

      inner_model = ToolCallThenTextModel.new("context_probe")
      inner_ts = ToolServer.new
      inner_ts.add_tool(probe)
      inner_handle = inner_ts.run
      inner = Agent(typeof(inner_model)).new(inner_model,
        preamble: "probe",
        tool_server_handle: inner_handle,
        default_max_turns: 5,
      )

      tool = inner.into_tool
      context = Tool::ToolContext.new
      context.insert("abc-123")

      result = tool.execute(%({"prompt": "do research"}), context)

      result.success?.should be_true
      observed.get.should eq("abc-123")
    end
  end
end

# Model that first emits a tool call, then a text response.
class ToolCallThenTextModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?
  getter calls = 0

  def initialize(@tool_name : String)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @last_request = request
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "call_1",
                   @tool_name,
                   JSON.parse(%({})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("inner done")
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
    builder.tool(Crig::Completion::ToolDefinition.new(@tool_name, "Probe", JSON.parse(%({"type":"object"}))))
  end
end
