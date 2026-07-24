require "../../src/crig"

# Ported from vendor/rig/examples/tool_result_outcomes/src/main.rs
#
# Demonstrates steering an agent on structured tool outcomes:
#   - HttpFetch tool classifies failures into ToolFailureKind (Timeout, NotFound)
#   - OutcomePolicy hook counts timeouts in the Scratchpad, terminates after threshold
#   - A 404 (NotFound) flows back to the model as recoverable feedback
#   - A regular success just logs and continues
#
# Requires DEEPSEEK_API_KEY.

# A tool that classifies its own failures into structured ToolFailure kinds.
struct HttpFetch
  include Crig::ToolDyn

  def name : String
    "http_fetch"
  end

  def description : String
    "Fetch a URL and return its body. URLs containing 'slow' time out; URLs containing 'missing' return HTTP 404."
  end

  def parameters : JSON::Any
    JSON.parse(%({
      "type": "object",
      "properties": {
        "url": { "type": "string", "description": "The URL to fetch" }
      },
      "required": ["url"]
    }))
  end

  def call(args : String) : String
    parsed = JSON.parse(args)
    url = parsed["url"].as_s

    if url.includes?("slow")
      "TIMEOUT: request to #{url} timed out"
    elsif url.includes?("missing")
      "404 NOT FOUND: #{url}"
    else
      "200 OK: fetched #{url}"
    end
  end
end

# Run-scoped timeout tally stored in the shared Scratchpad.
class TimeoutCount
  include JSON::Serializable

  @[JSON::Field(default: 0)]
  property count : Int32

  def initialize(@count : Int32 = 0)
  end
end

# A hook that terminates after max_timeouts tool timeouts; lets 404 continue.
struct OutcomePolicy
  include Crig::AgentHook
  @max_timeouts : Int32

  def initialize(@max_timeouts : Int32 = 3)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    unless event.tool_result?
      return Crig::Flow.cont
    end

    tool_name = event.tool_name || "unknown"
    result = event.result || ""

    # Check if the tool result indicates a timeout
    if result.includes?("TIMEOUT")
      tc = ctx.scratchpad.update(TimeoutCount, initial: TimeoutCount.new(0)) { |c| c.count += 1 }
      puts "[policy] #{tool_name} timed out (#{tc.count}/#{@max_timeouts})"
      if tc.count >= @max_timeouts
        return Crig::Flow.terminate("aborting after #{tc.count} tool timeouts")
      end
      return Crig::Flow.cont
    end

    # A 404 is not fatal — let the model recover
    if result.includes?("404")
      puts "[policy] #{tool_name} returned 404; letting the model recover: #{result}"
      return Crig::Flow.cont
    end

    if result.includes?("200 OK")
      puts "[policy] #{tool_name} succeeded: #{result}"
    else
      puts "[policy] #{tool_name} failed: #{result}"
    end

    Crig::Flow.cont
  end
end

client = Crig::Providers::DeepSeek::Client.from_env
model = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

agent = client.agent(model)
  .preamble(
    "You are a web assistant. Use the `http_fetch` tool to retrieve any URL the user mentions. If a fetch fails, tell the user what went wrong.",
  )
  .tool(HttpFetch.new)
  .build

puts "Fetching a missing URL (404 recovery)..."
response = agent.runner(Crig::Completion::Message.user("Fetch https://example.com/missing-page and tell me what happened."))
  .max_turns(5)
  .add_hook(OutcomePolicy.new(max_timeouts: 3))
  .run(Crig::Completion::Message.user("Fetch https://example.com/missing-page and tell me what happened."))

puts
puts "Final response:"
puts response.output
