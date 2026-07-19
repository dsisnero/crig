require "../../src/crig"

# Ported from vendor/rig/examples/agent_with_approval_policy/src/main.rs
#
# Policy-based tool-call approval: rules decided up front, evaluated per tool
# call by an AgentHook — no human prompt needed. Mirrors OpenAI SDK's
# needs_approval(fn) pattern.
#
#   - search_web is auto-approved (read-only, safe)
#   - transfer_funds is denied above $1000, approved below
#   - Anything else is denied (fail-closed)
#
# Requires DEEPSEEK_API_KEY.

struct SearchWeb
  include Crig::ToolDyn

  def name : String
    "search_web"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new("search_web", "Search the web (read-only).", JSON.parse(%({
      "type": "object",
      "properties": { "query": { "type": "string", "description": "Search query" } },
      "required": ["query"]
    })))
  end

  def call(args : String) : String
    query = JSON.parse(args)["query"].as_s
    puts "   🔎 [search_web] -> #{query}"
    "top result for '#{query}': $1000 is plenty."
  end
end

struct TransferFunds
  include Crig::ToolDyn

  def name : String
    "transfer_funds"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new("transfer_funds", "Transfer funds to an account.", JSON.parse(%({
      "type": "object",
      "properties": {
        "to": { "type": "string", "description": "Destination account id" },
        "amount": { "type": "integer", "description": "Amount in whole dollars" }
      },
      "required": ["to", "amount"]
    })))
  end

  def call(args : String) : String
    parsed = JSON.parse(args)
    to = parsed["to"].as_s
    amount = parsed["amount"].as_i
    puts "   🏦 [transfer_funds] -> $#{amount} to #{to}"
    "transferred $#{amount} to #{to}"
  end
end

# The approval policy, evaluated on every tool call.
struct ApprovalPolicy
  include Crig::AgentHook

  @auto_approve : Set(String)
  @max_auto_transfer : Int32

  def initialize(@auto_approve : Set(String) = Set{"search_web"}, @max_auto_transfer : Int32 = 1000)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    unless event.tool_call?
      return Crig::Flow.cont
    end

    tool_name = event.tool_name || "unknown"
    args = event.args || "{}"

    if @auto_approve.includes?(tool_name)
      puts "[policy] auto-approve `#{tool_name}` (safe)"
      return Crig::Flow.cont
    end

    if tool_name == "transfer_funds"
      begin
        parsed = JSON.parse(args)
        amount = parsed["amount"]?.try(&.as_i?) || 0
        if amount <= @max_auto_transfer
          puts "[policy] approve transfer $#{amount} (<= $#{@max_auto_transfer})"
          return Crig::Flow.cont
        else
          puts "[policy] DENY transfer $#{amount} (over $#{@max_auto_transfer})"
          return Crig::Flow.skip(
            "denied by policy: transfers over $# {@max_auto_transfer} require human approval; $#{amount} exceeds the limit",
          )
        end
      rescue
        return Crig::Flow.skip("denied by policy: could not read the transfer amount")
      end
    end

    puts "[policy] DENY `#{tool_name}` (not on the approved list)"
    Crig::Flow.skip("denied by policy: `#{tool_name}` is not on the approved tool list")
  end
end

client = Crig::Providers::DeepSeek::Client.from_env
model = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

agent = client.agent(model)
  .preamble("You are a banking assistant. Use the tools to carry out the user's request. If a tool is denied by policy, explain the limit to the user instead of retrying.")
  .tool(SearchWeb.new)
  .tool(TransferFunds.new)
  .build

prompt = "Look up how much I should send, then transfer $5000 to account B-2."
puts "User: #{prompt}"
puts

msg = Crig::Completion::Message.user(prompt)
response = agent.runner(msg)
  .max_turns(10)
  .add_hook(ApprovalPolicy.new)
  .run(msg)

puts
puts "Final response:"
puts response.output
