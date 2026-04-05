require "../src/crig"

module Crig::Examples::RequestHook
  class SessionIdHook < Crig::PromptHook
    getter session_id : String
    getter events : Array(String)

    def initialize(@session_id : String)
      @events = [] of String
    end

    def on_tool_call(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
    ) : Crig::ToolCallHookAction
      @events << "[Session #{@session_id}] Calling tool: #{tool_name} with call ID: #{tool_call_id || "<no call ID provided>"} (internal: #{internal_call_id}) with args: #{args}"
      Crig::ToolCallHookAction.cont
    end

    def on_tool_result(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
      result : String,
    ) : Crig::HookAction
      _ = tool_call_id
      _ = internal_call_id
      @events << "[Session #{@session_id}] Tool result for #{tool_name} (args: #{args}): #{result}"
      Crig::HookAction.cont
    end

    def on_completion_call(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Crig::HookAction
      _ = history
      @events << "[Session #{@session_id}] Sending prompt: #{message_text(prompt)}"
      Crig::HookAction.cont
    end

    def on_completion_response(
      prompt : Crig::Completion::Message,
      response,
    ) : Crig::HookAction
      _ = prompt
      rendered = if response.responds_to?(:choice)
                   response.choice.to_a.compact_map do |content|
                     case content
                     when Crig::Completion::AssistantContent
                       content.text.try(&.text)
                     end
                   end.join(" ")
                 else
                   "<received>"
                 end
      @events << "[Session #{@session_id}] Received response: #{rendered}"
      Crig::HookAction.cont
    end

    def on_text_delta(text_delta : String, aggregated_text : String) : Crig::HookAction
      @events << "[Session #{@session_id}] Text delta: '#{text_delta}' (aggregated: '#{aggregated_text}')"
      Crig::HookAction.cont
    end

    def on_tool_call_delta(
      tool_call_id : String,
      internal_call_id : String,
      tool_name : String?,
      tool_call_delta : String,
    ) : Crig::HookAction
      @events << "[Session #{@session_id}] Tool call delta for #{tool_name || "unknown"} (#{tool_call_id}/#{internal_call_id}): #{tool_call_delta}"
      Crig::HookAction.cont
    end

    private def message_text(prompt : Crig::Completion::Message) : String
      prompt.content.to_a.compact_map do |content|
        case content
        when Crig::Completion::UserContent
          content.text.try(&.text)
        when Crig::Completion::AssistantContent
          content.text.try(&.text)
        end
      end.join("\n")
    end
  end

  struct CalculatorArgs
    include JSON::Serializable

    getter operation : String
    getter x : Int32
    getter y : Int32

    def initialize(@operation : String, @x : Int32, @y : Int32)
    end
  end

  class CalculatorTool
    include Crig::Tool(CalculatorArgs, Int32)

    def name : String
      "calculator"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "calculator",
        "Perform basic arithmetic operations",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "operation":{"type":"string","description":"The arithmetic operation to perform (add, subtract, multiply, divide)","enum":["add","subtract","multiply","divide"]},
            "x":{"type":"number","description":"The first number"},
            "y":{"type":"number","description":"The second number"}
          },
          "required":["operation","x","y"]
        }))
      )
    end

    def call_typed(args : CalculatorArgs) : Int32
      case args.operation
      when "add"      then args.x + args.y
      when "subtract" then args.x - args.y
      when "multiply" then args.x * args.y
      when "divide"
        raise DivisionByZeroError.new("Cannot divide by zero") if args.y == 0
        args.x // args.y
      else
        raise ArgumentError.new("Unknown operation: #{args.operation}")
      end
    end
  end

  def self.build_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble("You are a helpful assistant that can perform calculations. Use the calculator tool when needed.")
      .tool(CalculatorTool.new)
      .build
  end

  def self.run_prompt(
    agent : Crig::Agent(M),
    hook : SessionIdHook,
    prompt : String,
  ) : String forall M
    agent.prompt(prompt).with_hook(hook).send
  end

  def self.run_stream(
    agent : Crig::Agent(M),
    hook : SessionIdHook,
    prompt : String,
  ) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).with_hook(hook).send
  end
end
