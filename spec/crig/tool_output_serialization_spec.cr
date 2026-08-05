require "../spec_helper"

MOTTO_OUTPUT = "steady hands\ncalm waters"

# Model that drives the tool_output_serialization scenario: calls both
# fetch_motto and fetch_config in one turn, then summarizes.
class FetchBothModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).many([
                 Crig::Completion::AssistantContent.tool_call_with_call_id("motto_1", "motto_1", "fetch_motto", JSON.parse(%({}))),
                 Crig::Completion::AssistantContent.tool_call_with_call_id("config_1", "config_1", "fetch_config", JSON.parse(%({}))),
               ])
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("done")
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("fetch_motto", "Fetch the motto", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
      .tool(Crig::Completion::ToolDefinition.new("fetch_config", "Fetch the service configuration object.", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
  end
end

module Crig
  describe "tool_output_serialization conformance" do
    it "does not double-encode string or JSON tool outputs" do
      motto_calls = Atomic(Int32).new(0)
      config_calls = Atomic(Int32).new(0)

      motto_tool = DynamicTool.new("fetch_motto", "Fetch the motto", JSON.parse(%({"type":"object","properties":{},"required":[]}))) do |args, ctx|
        motto_calls.add(1)
        Tool::ToolResult.success(Tool::ToolOutput.text(MOTTO_OUTPUT))
      end

      config_tool = DynamicTool.new("fetch_config", "Fetch the service configuration object.", JSON.parse(%({"type":"object","properties":{},"required":[]}))) do |args, ctx|
        config_calls.add(1)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON.parse(%({"service":"cassette-lab","max_retries":3}))))
      end

      model = FetchBothModel.new
      ts = ToolServer.new
      ts.add_tool(motto_tool)
      ts.add_tool(config_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "You must use the provided tools before answering.",
        temperature: 0.0,
        tool_server_handle: ts.run,
        default_max_turns: 3,
      )

      response = agent.runner(Completion::Message.user("Call fetch_motto and fetch_config, then summarize both outputs in one sentence."))
        .max_turns(3)
        .run(Completion::Message.user("Call fetch_motto and fetch_config, then summarize both outputs in one sentence."))

      motto_calls.get.should eq(1)
      config_calls.get.should eq(1)

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.validate_tool_correlation("tool_output_serialization", history)

      values = Crig::Conformance.tool_result_values(history)
      expected_config = JSON.parse(%({"service":"cassette-lab","max_retries":3}))

      motto_ok = values.any? { |v| v.as_s? == MOTTO_OUTPUT }
      config_ok = values.any? do |v|
        v == expected_config ||
          (str = v.as_s?) && begin
            JSON.parse(str) == expected_config
          rescue JSON::ParseException
            false
          end
      end

      motto_ok.should be_true
      config_ok.should be_true
    end
  end
end
