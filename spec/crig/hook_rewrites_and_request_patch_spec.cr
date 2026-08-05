require "../spec_helper"

# Hook that patches only the first completion call with active_tools + tool_choice.
class FirstTurnPatchHook
  include Crig::AgentHook

  def initialize(@patch : Crig::RequestPatch)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_completion_call(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::CompletionCallAction
    if ctx.turn == 1
      Crig::CompletionCallAction.patch_request(@patch)
    else
      Crig::CompletionCallAction.cont
    end
  end
end

# Hook that rewrites a single field of an add tool-call's arguments.
class RewriteArgumentHook
  include Crig::AgentHook

  def initialize(@key : String, @value : Int32)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_tool_call(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::ToolCallAction
    if event.tool_name == "add"
      args = JSON.parse(event.args || %q({}))
      updated = JSON.parse(%({})).as_h
      args.as_h.each { |k, v| updated[k] = v }
      updated[@key] = JSON::Any.new(@value)
      Crig::ToolCallAction.rewrite(JSON::Any.new(updated))
    else
      Crig::ToolCallAction.cont
    end
  end
end

# Hook that records the observed tool-call arguments.
class ObserveArgumentsHook
  include Crig::AgentHook

  getter observations = [] of JSON::Any
  getter lock = Mutex.new

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_tool_call(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::ToolCallAction
    if event.tool_name == "add"
      @lock.synchronize { @observations << JSON.parse(event.args || %q({})) }
    end
    Crig::ToolCallAction.cont
  end
end

# Hook that replaces the add tool result with a fixed redacted marker.
class ReplaceResultHook
  include Crig::AgentHook

  def initialize(@marker : String)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_tool_result(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::ToolResultAction
    if event.tool_name == "add"
      Crig::ToolResultAction.rewrite(Crig::Tool::ToolOutput.text(@marker))
    else
      Crig::ToolResultAction.cont
    end
  end
end

# Hook that wraps the add tool result as [rendered].
class WrapResultHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_tool_result(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::ToolResultAction
    if event.tool_name == "add"
      rendered = event.result || ""
      Crig::ToolResultAction.rewrite(Crig::Tool::ToolOutput.text("[#{rendered}]"))
    else
      Crig::ToolResultAction.cont
    end
  end
end

# Model: turn 1 calls add(x=1,y=1); turn 2 reports the tool result.
class RewritePatchModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = if @calls == 1
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id("add_1", "add_1", "add", JSON.parse(%({"x":1,"y":1})))
               )
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
      .tool(Crig::Completion::ToolDefinition.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))))
  end
end

module Crig
  describe "hook_rewrites_and_request_patch conformance" do
    it "rewrites args, replaces and wraps results, and patches the first request" do
      calls = Atomic(Int32).new(0)

      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      model = RewritePatchModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use add for arithmetic and report only the tool result.",
        temperature: 0.0,
        tool_server_handle: ts.run,
        default_max_turns: 3,
      )

      observed = ObserveArgumentsHook.new
      response = agent.runner(Completion::Message.user("Use add once for x=1 and y=1, then report what the tool returns."))
        .max_turns(3)
        .add_hook(FirstTurnPatchHook.new(
          Crig::RequestPatch.new
            .active_tools(["add"])
            .tool_choice(Crig::Completion::ToolChoice.required)
        ))
        .add_hook(RewriteArgumentHook.new("x", 7))
        .add_hook(RewriteArgumentHook.new("y", 8))
        .add_hook(observed)
        .add_hook(ReplaceResultHook.new("portable-redacted"))
        .add_hook(WrapResultHook.new)
        .run(Completion::Message.user("Use add once for x=1 and y=1, then report what the tool returns."))

      Conformance.validate_rewritten_arguments(
        "hook_rewrites_and_request_patch",
        observed.observations,
        JSON.parse(%({"x":7,"y":8})),
      )

      calls.get.should eq(1)

      history = response.messages || [] of Crig::Completion::Message
      results = Crig::Conformance.tool_result_values(history)
      results.any? { |v| v.as_s? == "[portable-redacted]" }.should be_true

      response.completion_calls.size.should eq(2)
    end
  end
end
