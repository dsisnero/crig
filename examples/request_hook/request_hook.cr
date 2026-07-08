require "../../src/crig"

# Ported from vendor/rig/examples/request_hook/src/main.rs
#
# Demonstrates composing hooks with AgentHook. Multiple hooks are stacked
# via .add_hook() and ALL of them run — a request patch from one hook
# does NOT short-circuit the others:
#
#   - LoggingHook — observe-only, reads HookContext (run id, turn)
#   - ContextHook — injects extra context document via RequestPatch
#   - SamplingHook — lowers temperature via RequestPatch
#   - TurnCounterHook — counts calls using shared Scratchpad
#
# On each CompletionCall, patches merge in registration order.
#
# Requires DEEPSEEK_API_KEY.

# Hook 1: LoggingHook — observe-only. Reads run-scoped identity from context.
struct LoggingHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.completion_call?
      text = event.prompt_text || ""
      unless text.empty?
        puts "[run #{ctx.run_id} · turn #{ctx.turn}] sending prompt: #{text[0..80]}"
      end
    end
    Crig::Flow.cont
  end
end

# Hook 2: ContextHook — injects extra context for the turn via preamble patch.
struct ContextHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.completion_call?
      # Use preamble override as a simplified context injection
      patch = Crig::RequestPatch.new.preamble(
        "You are a comedian. House style: keep jokes short and family-friendly.",
      )
      return Crig::Flow.patch_request(patch)
    end
    Crig::Flow.cont
  end
end

# Hook 3: SamplingHook — lowers temperature for the turn.
struct SamplingHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.completion_call?
      return Crig::Flow.patch_request(Crig::RequestPatch.new.temperature(0.2))
    end
    Crig::Flow.cont
  end
end

# Hook 4: TurnCounterHook — counts completion calls via scratchpad.
class TurnCount
  include JSON::Serializable
  property count : Int32

  def initialize(@count : Int32 = 0)
  end
end

struct TurnCounterHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.completion_call?
      n = ctx.scratchpad.update(TurnCount, initial: TurnCount.new(0)) { |c| c.count += 1 }
      puts "[turn-counter] completion call ##{n.count} this run"
    end
    Crig::Flow.cont
  end
end

client = Crig::Providers::DeepSeek::Client.from_env
model = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

agent = client.agent(model)
  .preamble("You are a comedian here to entertain the user using humour and jokes.")
  .build

msg = Crig::Completion::Message.user("Entertain me!")
response = agent.runner(msg)
  .add_hook(LoggingHook.new)
  .add_hook(ContextHook.new)
  .add_hook(SamplingHook.new)
  .add_hook(TurnCounterHook.new)
  .run(msg)

puts
puts "Final response:"
puts response.output
