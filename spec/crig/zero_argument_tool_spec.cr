require "../spec_helper"

PING_OUTPUT = "pong-crimson-7423"

# Model that first emits a ping tool call, then a text response containing the
# ping marker, matching the upstream zero_argument_tool scenario.
class ZeroArgPingModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?
  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @last_request = request
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "call_1",
                   "call_1",
                   "ping",
                   JSON.parse(%({})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text(PING_OUTPUT)
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
    builder.tool(Crig::Completion::ToolDefinition.new("ping", "Return the current ping marker. Takes no arguments.", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
  end
end

module Crig
  describe "zero_argument_tool conformance" do
    it "calls a zero-argument tool once and surfaces its marker in the final output" do
      ping_calls = Atomic(Int32).new(0)
      ping = DynamicTool.new("ping", "Return the current ping marker. Takes no arguments.", JSON.parse(%({"type":"object","properties":{},"required":[]}))) do |args, ctx|
        ping_calls.add(1)
        Tool::ToolResult.success(Tool::ToolOutput.text(PING_OUTPUT))
      end

      model = ZeroArgPingModel.new
      ts = ToolServer.new
      ts.add_tool(ping)
      handle = ts.run
      agent = Agent(typeof(model)).new(model,
        preamble: "You must use the provided tools. Report tool outputs exactly as returned.",
        temperature: 0.0,
        tool_server_handle: handle,
        default_max_turns: 2,
      )

      response = agent.runner(Completion::Message.user("Call the ping tool, then report the exact marker it returns."))
        .max_turns(2)
        .run(Completion::Message.user("Call the ping tool, then report the exact marker it returns."))

      ping_calls.get.should eq(1)
      response.output.should contain(PING_OUTPUT)

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.validate_tool_correlation("zero_argument_tool", history)
    end
  end
end
