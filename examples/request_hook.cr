require "../src/crig"

module Crig::Examples::RequestHook
  class SessionIdHook
    include Crig::AgentHook

    getter session_id : String
    getter events : Array(String)

    def initialize(@session_id : String)
      @events = [] of String
    end

    def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
      case event.kind
      in .tool_call?
        @events << "[Session #{@session_id}] Calling tool: #{event.tool_name} with call ID: #{event.tool_call_id || "<no call ID provided>"} (internal: #{event.internal_call_id}) with args: #{event.args}"
        Crig::Flow.cont
      in .tool_result?
        @events << "[Session #{@session_id}] Tool result for #{event.tool_name} (args: #{event.args}): #{event.result}"
        Crig::Flow.cont
      in .completion_call?
        @events << "[Session #{@session_id}] Sending prompt: #{event.prompt_text || ""}"
        Crig::Flow.cont
      in .completion_response?
        rendered = event.choice_text || event.raw_response || "<received>"
        @events << "[Session #{@session_id}] Received response: #{rendered}"
        Crig::Flow.cont
      in .model_turn_finished?
        Crig::Flow.cont
      in .invalid_tool_call?
        Crig::Flow.cont
      in .text_delta?
        Crig::Flow.cont
      in .tool_call_delta?
        Crig::Flow.cont
      in .stream_response_finish?
        Crig::Flow.cont
      end
    end
  end
end
