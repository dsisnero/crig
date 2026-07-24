require "../../src/crig"

# Ported from vendor/rig/examples/agent_with_human_in_the_loop/src/main.rs
#
# Human-in-the-loop tool-call approval. An agent has two side-effecting tools
# (send_email, delete_file). Before any tool runs, ApprovalHook pauses and
# asks a human on stdin:
#
#   [a]pprove — tool runs as requested
#   [d]eny   — tool skipped, reason fed back to model
#   [e]dit   — tool runs with human-supplied JSON args instead
#   a[b]ort  — whole run terminates
#
# Requires DEEPSEEK_API_KEY.

# Two side-effecting tools worth gating behind human approval.

struct SendEmail
  include Crig::ToolDyn

  def name : String
    "send_email"
  end

  def description : String
    "Send an email to a recipient."
  end

  def parameters : JSON::Any
    JSON.parse(%({
      "type": "object",
      "properties": {
        "to": { "type": "string", "description": "Recipient email address" },
        "subject": { "type": "string", "description": "Email subject line" },
        "body": { "type": "string", "description": "Email body" }
      },
      "required": ["to", "subject", "body"]
    }))
  end

  def call(args : String) : String
    parsed = JSON.parse(args)
    to = parsed["to"].as_s
    subject = parsed["subject"].as_s
    body = parsed["body"].as_s
    puts "   📧 [send_email] -> #{to} (subject: #{subject.inspect}, #{body.size} chars)"
    "email sent to #{to}"
  end
end

struct DeleteFile
  include Crig::ToolDyn

  def name : String
    "delete_file"
  end

  def description : String
    "Permanently delete a file at the given path."
  end

  def parameters : JSON::Any
    JSON.parse(%({
      "type": "object",
      "properties": {
        "path": { "type": "string", "description": "Absolute path of the file to delete" }
      },
      "required": ["path"]
    }))
  end

  def call(args : String) : String
    path = JSON.parse(args)["path"].as_s
    puts "   🗑️  [delete_file] -> #{path}"
    "deleted #{path}"
  end
end

# Helper: print a prompt and read one trimmed line from stdin.
private def ask(prompt : String) : String?
  print prompt
  STDOUT.flush
  line = STDIN.gets
  line.try(&.strip).try { |s| s.empty? ? nil : s }
end

# Gates every tool call behind interactive human approval.
struct ApprovalHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    unless event.tool_call?
      return Crig::Flow.cont
    end

    tool_name = event.tool_name || "unknown"
    args = event.args || "{}"

    puts
    puts "⏸  The agent wants to run a tool — your approval is required:"
    puts "     tool: #{tool_name}"
    puts "     args: #{args}"

    choice = ask("     [a]pprove / [d]eny / [e]dit args / a[b]ort run? ")
    unless choice
      puts "     → no input (stdin closed); aborting (fail-closed)"
      return Crig::Flow.terminate("no reviewer input available (stdin closed)")
    end

    case choice.downcase
    when "a", "approve"
      puts "     → approved"
      Crig::Flow.cont
    when "d", "deny", "n", "no"
      reason = ask("     reason (shown to the model): ") || "denied by the human reviewer"
      puts "     → denied"
      Crig::Flow.skip(reason)
    when "e", "edit"
      input = ask("     replacement JSON args (single line): ")
      begin
        value = input ? JSON.parse(input) : nil
        if value
          puts "     → running with edited arguments"
          Crig::Flow.rewrite_args(value)
        else
          puts "     ! no input; denying instead"
          Crig::Flow.skip("the reviewer tried to edit the arguments but supplied no input")
        end
      rescue ex : JSON::ParseException
        puts "     ! no valid JSON (#{ex.message}); denying instead"
        Crig::Flow.skip("the reviewer tried to edit the arguments but supplied no valid JSON")
      end
    when "b", "abort", "q", "quit"
      puts "     → aborting the run"
      Crig::Flow.terminate("run aborted by the human reviewer")
    when ""
      puts "     → empty input; denying (fail-closed)"
      Crig::Flow.skip("denied: the reviewer gave no decision")
    else
      puts "     ! unrecognized choice '#{choice}'; denying (fail-closed)"
      Crig::Flow.skip("denied: unrecognized reviewer input '#{choice}'")
    end
  end
end

client = Crig::Providers::DeepSeek::Client.from_env
model = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

agent = client.agent(model)
  .preamble("You are an operations assistant. Use the available tools to carry out the user's request. Call one tool at a time and wait for its result before the next step.")
  .tool(SendEmail.new)
  .tool(DeleteFile.new)
  .build

prompt = "Email alice@example.com a reminder that the budget review is at 3pm, then delete the stale file /tmp/old_report.csv."
puts "User: #{prompt}"

msg = Crig::Completion::Message.user(prompt)
response = agent.runner(msg)
  .max_turns(10)
  .add_hook(ApprovalHook.new)
  .run(msg)

puts
puts "Final response:"
puts response.output
