module Crig
  struct HookAction
    enum Kind
      Continue
      Terminate
    end

    getter kind : Kind
    getter reason : String?

    def initialize(@kind : Kind, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Continue)
    end

    def self.terminate(reason : String) : self
      new(Kind::Terminate, reason)
    end
  end

  struct ToolCallHookAction
    enum Kind
      Continue
      Skip
      Terminate
    end

    getter kind : Kind
    getter reason : String?

    def initialize(@kind : Kind, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Continue)
    end

    def self.skip(reason : String) : self
      new(Kind::Skip, reason)
    end

    def self.terminate(reason : String) : self
      new(Kind::Terminate, reason)
    end
  end

  struct InvalidToolCallContext
    getter tool_name : String
    getter tool_call_id : String?
    getter internal_call_id : String?
    getter args : String?
    getter available_tools : Array(String)
    getter allowed_tools : Array(String)
    getter tool_choice : Crig::Completion::ToolChoice?
    getter chat_history : Array(Crig::Completion::Message)
    getter? is_streaming : Bool

    def initialize(
      @tool_name : String,
      @available_tools : Array(String),
      @allowed_tools : Array(String),
      @chat_history : Array(Crig::Completion::Message),
      @tool_call_id : String? = nil,
      @internal_call_id : String? = nil,
      @args : String? = nil,
      @tool_choice : Crig::Completion::ToolChoice? = nil,
      @is_streaming : Bool = false,
    )
    end
  end

  struct InvalidToolCallHookAction
    enum Kind
      Fail
      Retry
      Repair
      Skip
    end

    getter kind : Kind
    getter feedback : String?
    getter reason : String?
    getter tool_name : String?

    def initialize(@kind : Kind, @feedback : String? = nil, @reason : String? = nil, @tool_name : String? = nil)
    end

    def self.fail : self
      new(Kind::Fail)
    end

    def self.retry(feedback : String) : self
      new(Kind::Retry, feedback: feedback)
    end

    def self.repair(tool_name : String) : self
      new(Kind::Repair, tool_name: tool_name)
    end

    def self.skip(reason : String) : self
      new(Kind::Skip, reason: reason)
    end
  end

  abstract class PromptHook
    def on_completion_call(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Crig::HookAction
      Crig::HookAction.cont
    end

    def on_completion_response(
      prompt : Crig::Completion::Message,
      response,
    ) : Crig::HookAction
      _ = response
      Crig::HookAction.cont
    end

    def on_tool_call(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
    ) : Crig::ToolCallHookAction
      Crig::ToolCallHookAction.cont
    end

    def on_tool_result(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
      result : String,
    ) : Crig::HookAction
      Crig::HookAction.cont
    end

    def on_invalid_tool_call(context : Crig::InvalidToolCallContext) : Crig::InvalidToolCallHookAction
      _ = context
      Crig::InvalidToolCallHookAction.fail
    end

    def on_text_delta(text_delta : String, aggregated_text : String) : Crig::HookAction
      Crig::HookAction.cont
    end

    def on_tool_call_delta(
      tool_call_id : String,
      internal_call_id : String,
      tool_name : String?,
      tool_call_delta : String,
    ) : Crig::HookAction
      Crig::HookAction.cont
    end

    def on_stream_completion_response_finish(
      prompt : Crig::Completion::Message,
      response,
    ) : Crig::HookAction
      Crig::HookAction.cont
    end
  end

  module PromptType
  end

  struct Standard
    include PromptType
  end

  struct Extended
    include PromptType
  end

  struct CompletionCall
    include JSON::Serializable

    getter call_index : Int32
    getter usage : Crig::Completion::Usage?

    def initialize(@call_index : Int32, @usage : Crig::Completion::Usage?)
    end
  end

  struct PromptResponse
    getter output : String
    getter usage : Crig::Completion::Usage
    getter messages : Array(Crig::Completion::Message)?
    getter completion_calls : Array(CompletionCall)

    def initialize(
      @output : String,
      @usage : Crig::Completion::Usage,
      @messages : Array(Crig::Completion::Message)? = nil,
      @completion_calls : Array(CompletionCall) = [] of CompletionCall,
    )
    end

    def with_messages(messages : Array(Crig::Completion::Message)) : self
      self.class.new(@output, @usage, messages, @completion_calls)
    end

    def with_completion_calls(calls : Array(CompletionCall)) : self
      self.class.new(@output, @usage, @messages, calls)
    end

    def to_s(io : IO) : Nil
      io << @output
    end
  end

  struct TypedPromptResponse(T)
    include JSON::Serializable

    getter output : T
    getter usage : Crig::Completion::Usage
    getter completion_calls : Array(CompletionCall)

    def initialize(
      @output : T,
      @usage : Crig::Completion::Usage,
      @completion_calls : Array(CompletionCall) = [] of CompletionCall,
    )
    end

    def with_completion_calls(calls : Array(CompletionCall)) : self
      self.class.new(@output, @usage, calls)
    end
  end

  struct PromptRequest(S, M)
    getter prompt : Crig::Completion::Message
    getter chat_history : Array(Crig::Completion::Message)?
    getter max_turns : Int32
    getter concurrency : Int32
    getter agent : Crig::Agent(M)
    getter hook : Crig::PromptHook?
    getter memory : Crig::Memory::ConversationMemory?
    getter conversation_id : String?

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @chat_history : Array(Crig::Completion::Message)? = nil,
      @max_turns : Int32 = 0,
      @concurrency : Int32 = 1,
      @hook : Crig::PromptHook? = nil,
      @memory : Crig::Memory::ConversationMemory? = nil,
      @conversation_id : String? = nil,
    )
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      new(agent, prompt_message, nil, agent.default_max_turns || 0, hook: agent.hook, memory: agent.memory, conversation_id: agent.default_conversation_id)
    end

    def extended_details : PromptRequest(Crig::Extended, M)
      PromptRequest(Crig::Extended, M).new(@agent, @prompt, @chat_history, @max_turns, @concurrency, @hook, @memory, @conversation_id)
    end

    def max_turns(depth : Int) : self
      self.class.new(@agent, @prompt, @chat_history, depth.to_i32, @concurrency, @hook, @memory, @conversation_id)
    end

    def with_tool_concurrency(concurrency : Int) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, concurrency.to_i32, @hook, @memory, @conversation_id)
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      self.class.new(@agent, @prompt, history.dup, @max_turns, @concurrency, @hook, @memory, @conversation_id)
    end

    def with_hook(hook : Crig::PromptHook) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, @concurrency, hook, @memory, @conversation_id)
    end

    # Set the conversation id used to load and persist memory for this request.
    # Overrides any default conversation id set on the agent.
    def conversation(id : String) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, @concurrency, @hook, @memory, id)
    end

    # Disable conversation memory for this request.
    # History will neither be loaded from nor saved to the agent's memory backend.
    def without_memory : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, @concurrency, @hook, nil, nil)
    end

    private def reported_usage(usage : Crig::Completion::Usage) : Crig::Completion::Usage?
      usage.input_tokens == 0 && usage.output_tokens == 0 && usage.total_tokens == 0 ? nil : usage
    end

    def send
      {% if S == Crig::Extended %}
        chat_history = (@chat_history || [] of Crig::Completion::Message).dup
        chat_history << @prompt

        agent_name = @agent.name || "Unnamed Agent"
        preamble_text = @agent.preamble

        agent_span = Crig::Span.current.disabled? ? Crig::Span.for_tracer("crig", "invoke_agent") : Crig::Span.current
        agent_span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "invoke_agent")
        agent_span.set_attribute(Crig::Telemetry::GEN_AI_AGENT_NAME, agent_name)
        if preamble_text
          agent_span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble_text)
        end

        if prompt_text = @prompt.rag_text
          agent_span.set_attribute(Crig::Telemetry::GEN_AI_PROMPT, prompt_text)
        end

        current_max_turns = 0
        usage = Crig::Completion::Usage.new
        completion_calls = [] of Crig::CompletionCall
        zero_usage = Crig::Completion::Usage.new

        output = nil
        begin
          loop do
            prompt = chat_history.last

            if current_max_turns > @max_turns + 1
              raise Crig::Completion::PromptError.max_turns_exceeded(@max_turns, chat_history.dup, prompt)
            end

            current_max_turns += 1

            run_completion_call_hook(prompt, chat_history[0...-1])

            response = @agent.completion(prompt, chat_history[0...-1]).send(@agent.model)
            completion_calls << Crig::CompletionCall.new(completion_calls.size, reported_usage(response.usage))
            usage += response.usage

            run_completion_response_hook(prompt, response, chat_history)

            tool_calls = [] of Crig::Completion::AssistantContent
            text_parts = [] of String
            response.choice.each do |choice|
              if choice.kind.tool_call?
                tool_calls << choice
              elsif choice.kind.text?
                if text = choice.text
                  text_parts << text.text
                end
              end
            end

            chat_history << Crig::Completion::Message.new(
              Crig::Completion::Message::Role::Assistant,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                response.choice.to_a.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
              ),
              response.message_id,
            )

            unless tool_calls.empty?
              tool_content = execute_tool_calls(tool_calls, chat_history)
              chat_history << Crig::Completion::Message.from(Crig::OneOrMany(Crig::Completion::UserContent).many(tool_content))
              next
            end

            output = text_parts.join
            agent_span.set_attribute(Crig::Telemetry::GEN_AI_COMPLETION, output)
            agent_span.record_token_usage(usage)
            return Crig::PromptResponse.new(output, usage).with_messages(chat_history.dup).with_completion_calls(completion_calls)
          end
        ensure
          unless output
            agent_span.record_token_usage(usage)
          end
          agent_span.end_span
        end
      {% else %}
        extended_details.send.output
      {% end %}
    end

    private record ToolExecutionResult, index : Int32, content : Crig::Completion::UserContent

    private def run_completion_call_hook(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Nil
      if hook = @hook
        action = hook.on_completion_call(prompt, history)
        if action.kind.terminate?
          reason = action.reason || "terminated"
          raise Crig::Completion::PromptError.prompt_cancelled(history + [prompt], reason)
        end
      end
    end

    private def run_completion_response_hook(
      prompt : Crig::Completion::Message,
      response,
      chat_history : Array(Crig::Completion::Message),
    ) : Nil
      if hook = @hook
        action = hook.on_completion_response(prompt, response)
        if action.kind.terminate?
          reason = action.reason || "terminated"
          raise Crig::Completion::PromptError.prompt_cancelled(chat_history.dup, reason)
        end
      end
    end

    private def execute_tool_calls(
      tool_calls : Array(Crig::Completion::AssistantContent),
      chat_history : Array(Crig::Completion::Message),
    ) : Array(Crig::Completion::UserContent)
      return [] of Crig::Completion::UserContent if tool_calls.empty?

      indexed = tool_calls.map_with_index { |choice, index| {choice, index} }
      results = Crig::Concurrency.map_ordered(indexed) do |(choice, index)|
        execute_tool_call(choice, chat_history, index)
      end

      results.sort_by!(&.index)
      results.map(&.content)
    end

    private def execute_tool_call(
      choice : Crig::Completion::AssistantContent,
      chat_history : Array(Crig::Completion::Message),
      index : Int32,
    ) : ToolExecutionResult
      tool_call = choice.tool_call
      raise "Expected tool call assistant content" unless tool_call

      tool_name = tool_call.function.name
      args = tool_call.function.arguments.to_json
      internal_call_id = "tool-call-#{tool_call.id}"

      if hook = @hook
        action = hook.on_tool_call(tool_name, tool_call.call_id, internal_call_id, args)
        case action.kind
        in .terminate?
          reason = action.reason || "terminated"
          raise Crig::Completion::PromptError.prompt_cancelled(chat_history, reason)
        in .skip?
          return ToolExecutionResult.new(index, tool_result_user_content(tool_call.id, tool_call.call_id, action.reason || ""))
        in .continue?
        end
      end

      handle = @agent.tool_server_handle
      raise Crig::Completion::PromptError.new("Tool server handle is required for tool-calling prompts") unless handle

      output = begin
        handle.call_tool(tool_name, args)
      rescue ex
        ex.to_s
      end

      if hook = @hook
        action = hook.on_tool_result(tool_name, tool_call.call_id, internal_call_id, args, output)
        if action.kind.terminate?
          reason = action.reason || "terminated"
          raise Crig::Completion::PromptError.prompt_cancelled(chat_history, reason)
        end
      end

      ToolExecutionResult.new(index, tool_result_user_content(tool_call.id, tool_call.call_id, output))
    end

    private def tool_result_user_content(
      id : String,
      call_id : String?,
      output : String,
    ) : Crig::Completion::UserContent
      content = Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text(output)
      )
      if call_id
        Crig::Completion::UserContent.tool_result_with_call_id(id, call_id, content)
      else
        Crig::Completion::UserContent.tool_result(id, content)
      end
    end
  end

  struct TypedPromptRequest(T, S, M)
    getter inner : Crig::PromptRequest(S, M)

    def initialize(@inner : Crig::PromptRequest(S, M))
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      request = Crig::PromptRequest(Crig::Standard, M).from_agent(agent, prompt)
      schema = JSON.parse(%({"title":"#{T}"}))
      typed_agent = Crig::Agent(M).new(
        agent.model,
        name: agent.name,
        description: agent.description,
        preamble: agent.preamble,
        static_context: agent.static_context,
        dynamic_context: agent.dynamic_context,
        static_tools: agent.static_tools,
        dynamic_tools: agent.dynamic_tools,
        tool_server_handle: agent.tool_server_handle,
        additional_params: agent.additional_params,
        max_tokens: agent.max_tokens,
        default_max_turns: agent.default_max_turns,
        temperature: agent.temperature,
        tool_choice: agent.tool_choice,
        output_schema: schema,
      )

      new(Crig::PromptRequest(Crig::Standard, M).from_agent(typed_agent, request.prompt))
    end

    def extended_details : Crig::TypedPromptRequest(T, Crig::Extended, M)
      Crig::TypedPromptRequest(T, Crig::Extended, M).new(@inner.extended_details)
    end

    def max_turns(depth : Int) : self
      self.class.new(@inner.max_turns(depth))
    end

    def with_tool_concurrency(concurrency : Int) : self
      self.class.new(@inner.with_tool_concurrency(concurrency))
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      self.class.new(@inner.with_history(history))
    end

    def with_hook(hook : Crig::PromptHook) : self
      self.class.new(@inner.with_hook(hook))
    end

    def send
      {% if S == Crig::Extended %}
        response = @inner.send
        Crig::TypedPromptResponse(T).new(T.from_json(response.output), response.usage, response.completion_calls)
      {% else %}
        T.from_json(@inner.send)
      {% end %}
    end
  end
end
