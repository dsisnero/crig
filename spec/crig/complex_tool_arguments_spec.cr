require "../spec_helper"

# Model that drives the complex_tool_arguments scenario: one store_profile call
# carrying nested, escaped, Unicode-bearing arguments.
class ComplexArgsModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "prof_1", "prof_1", "store_profile",
                   JSON.parse(%q({"profile":{"name":"Zoë \"Z\"","tags":["rust","東京"]},"mode":"careful","note":"line one\nline two","quote":"path C:\\tmp and \"quoted\""}))
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("stored")
               )
             end
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("store_profile", "Store one profile", JSON.parse(%({"type":"object","properties":{}}))))
  end
end

module Crig
  describe "complex_tool_arguments conformance" do
    it "preserves nested, escaped, and Unicode argument values through the tool call" do
      calls = Atomic(Int32).new(0)
      captured = Mutex.new
      observed = JSON.parse(%({}))

      store_tool = DynamicTool.new("store_profile", "Store one profile", JSON.parse(%({"type":"object","properties":{}}))) do |args, ctx|
        calls.add(1)
        captured.synchronize { observed = JSON.parse(args) }
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON.parse(args)))
      end

      model = ComplexArgsModel.new
      ts = ToolServer.new
      ts.add_tool(store_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use store_profile exactly once with every value supplied by the user.",
        temperature: 0.0,
        tool_server_handle: ts.run,
        default_max_turns: 3,
      )

      response = agent.runner(Completion::Message.user("Call store_profile with profile.name exactly `Zoë \"Z\"`, profile.tags exactly [`rust`, `東京`], mode `careful`, note containing the two lines `line one` and `line two` separated by a newline, and quote exactly `path C:\\tmp and \"quoted\"`. Then confirm it was stored."))
        .max_turns(3)
        .run(Completion::Message.user("Call store_profile with profile.name exactly `Zoë \"Z\"`, profile.tags exactly [`rust`, `東京`], mode `careful`, note containing the two lines `line one` and `line two` separated by a newline, and quote exactly `path C:\\tmp and \"quoted\"`. Then confirm it was stored."))

      calls.get.should eq(1)

      observed = captured.synchronize { observed }
      observed["profile"]["name"].as_s.should eq(%(Zoë "Z"))
      observed["profile"]["tags"].as_a.map(&.as_s).should eq(["rust", "東京"])
      observed["mode"].as_s.should eq("careful")
      observed["note"].as_s.should eq("line one\nline two")
      observed["quote"].as_s.should eq(%q(path C:\tmp and "quoted"))

      history = response.messages || [] of Crig::Completion::Message
      Crig::Conformance.validate_tool_correlation("complex_tool_arguments", history)
    end
  end
end
