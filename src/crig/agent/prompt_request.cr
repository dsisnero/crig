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

  enum InvalidToolCallResolution
    Fail
    Retry
    Repair
    Skip
  end

  def self.resolve_invalid_tool_call(
    hook : Crig::PromptHook?,
    tool_name : String,
    tool_call_id : String?,
    internal_call_id : String?,
    args : String?,
    executable_tool_names : Set(String),
    allowed_tool_names : Set(String),
    tool_choice : Crig::Completion::ToolChoice?,
    chat_history : Array(Crig::Completion::Message),
    is_streaming : Bool = false,
  ) : {InvalidToolCallResolution, String?}
    # Build the error that would be raised on fail-fast
    unless hook
      return {InvalidToolCallResolution::Fail, nil}
    end

    context = Crig::InvalidToolCallContext.new(
      tool_name,
      executable_tool_names.to_a,
      allowed_tool_names.to_a,
      chat_history,
      tool_call_id: tool_call_id,
      internal_call_id: internal_call_id,
      args: args,
      tool_choice: tool_choice,
      is_streaming: is_streaming,
    )

    action = hook.on_invalid_tool_call(context)

    case action.kind
    in .fail?
      {InvalidToolCallResolution::Fail, nil}
    in .retry?
      {InvalidToolCallResolution::Retry, action.feedback}
    in .repair?
      repaired_name = action.tool_name || tool_name
      if allowed_tool_names.includes?(repaired_name)
        {InvalidToolCallResolution::Repair, repaired_name}
      else
        {InvalidToolCallResolution::Fail, nil}
      end
    in .skip?
      if tool_choice.try(&.none?)
        {InvalidToolCallResolution::Fail, nil}
      else
        {InvalidToolCallResolution::Skip, action.reason}
      end
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

  # Bridge that wraps an old-style PromptHook as a new-style AgentHook
  # so old hooks work transparently through AgentRunner.
  struct PromptHookAdapter
    include AgentHook

    # Wraps the response so PromptHook#on_completion_response
    # can access response.raw_response and response.choice without
    # needing the full model type.
    private struct RawResponse
      getter raw_response : String
      getter choice : Crig::OneOrMany(Crig::Completion::AssistantContent)

      def initialize(@raw_response : String, @choice : Crig::OneOrMany(Crig::Completion::AssistantContent))
      end
    end

    def initialize(@hook : PromptHook)
    end

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      case event.kind
      in .completion_call?
        msg = Completion::Message.user(event.prompt_text || "")
        action = @hook.on_completion_call(msg, [] of Completion::Message)
        map_hook_action(action)
      in .tool_call?
        action = @hook.on_tool_call(
          event.tool_name.not_nil!,
          event.tool_call_id,
          event.internal_call_id.not_nil!,
          event.args.not_nil!,
        )
        map_tool_call_action(action)
      in .tool_result?
        action = @hook.on_tool_result(
          event.tool_name.not_nil!,
          event.tool_call_id,
          event.internal_call_id.not_nil!,
          event.args.not_nil!,
          event.result.not_nil!,
        )
        map_hook_action(action)
      in .completion_response?
        if raw = event.raw_response
          msg = Completion::Message.user(event.prompt_text || "")
          choice = event.choice_text ? Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(event.choice_text.not_nil!)) : Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(raw))
          action = @hook.on_completion_response(msg, RawResponse.new(raw, choice))
          map_hook_action(action)
        else
          Flow.cont
        end
      in .model_turn_finished?
        Flow.cont
      in .invalid_tool_call?
        Flow.cont
      in .text_delta?
        Flow.cont
      in .tool_call_delta?
        Flow.cont
      in .stream_response_finish?
        Flow.cont
      end
    end

    private def map_hook_action(action : HookAction) : Flow
      case action.kind
      in .continue?
        Flow.cont
      in .terminate?
        Flow.terminate(action.reason || "terminated")
      end
    end

    private def map_tool_call_action(action : ToolCallHookAction) : Flow
      case action.kind
      in .continue?
        Flow.cont
      in .skip?
        Flow.skip(action.reason || "skipped")
      in .terminate?
        Flow.terminate(action.reason || "terminated")
      end
    end
  end

  struct PromptRequest(S, M)
    getter agent : Crig::Agent(M)
    getter prompt : Crig::Completion::Message
    getter runner : AgentRunner(M)
    getter memory : Crig::Memory::ConversationMemory?
    getter conversation_id : String?

    # Backward-compatible hook getter: stored for spec access.
    # The actual hook wrapping into the runner happens at construction/setter time.
    def hook : Crig::PromptHook?
      @hook
    end

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @runner : AgentRunner(M),
      @hook : Crig::PromptHook? = nil,
      @memory : Crig::Memory::ConversationMemory? = nil,
      @conversation_id : String? = nil,
    )
    end

    # -- Backward-compatible getters that delegate to the runner --

    def chat_history : Array(Crig::Completion::Message)?
      @runner.chat_history
    end

    def max_turns : Int32
      @runner.max_turns
    end

    def concurrency : Int32
      @runner.concurrency
    end

    # -- Construction --

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      runner = agent.runner(prompt_message)
        .max_turns(agent.default_max_turns || 0)
      # Wrap agent-level old-style PromptHook immediately
      if agent_hook = agent.hook
        runner.add_hook(PromptHookAdapter.new(agent_hook))
      end
      new(agent, prompt_message, runner, agent.hook, memory: agent.memory, conversation_id: agent.default_conversation_id)
    end

    def extended_details : PromptRequest(Crig::Extended, M)
      PromptRequest(Crig::Extended, M).new(@agent, @prompt, @runner, @hook, @memory, @conversation_id)
    end

    # -- Builder setters (mutate the runner in place) --

    def max_turns(depth : Int) : self
      @runner.max_turns(depth.to_i32)
      self
    end

    def with_tool_concurrency(concurrency : Int) : self
      @runner.tool_concurrency(concurrency.to_i32)
      self
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      @runner.chat_history(history.dup)
      self
    end

    def with_hook(hook : Crig::PromptHook) : self
      @runner.add_hook(PromptHookAdapter.new(hook))
      self.class.new(@agent, @prompt, @runner, hook, @memory, @conversation_id)
    end

    def conversation(id : String) : self
      self.class.new(@agent, @prompt, @runner, @hook, @memory, id)
    end

    def without_memory : self
      self.class.new(@agent, @prompt, @runner, @hook, nil, nil)
    end

    # -- Execution --

    def send
      {% if S == Crig::Extended %}
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

        # Apply request-level memory to runner
        effective_history = @runner.chat_history
        memory_handle = @memory
        conv_id = @conversation_id

        if memory_handle && conv_id
          loaded = memory_handle.load(conv_id)
          effective_history = (effective_history || [] of Crig::Completion::Message) + loaded
        end

        @runner.chat_history(effective_history) if effective_history

        result = @runner.run(@prompt)

        # Persist memory
        if memory_handle && conv_id
          if msgs = result.messages
            memory_handle.append(conv_id, msgs)
          end
        end

        agent_span.set_attribute(Crig::Telemetry::GEN_AI_COMPLETION, result.output)
        agent_span.record_token_usage(result.usage)
        agent_span.end_span
        result
      {% else %}
        extended_details.send.output
      {% end %}
    end

    def send_async
      {% if S == Crig::Extended %}
        Crig::Concurrency.run do
          send.as(Crig::PromptResponse)
        end
      {% else %}
        Crig::Concurrency.run do
          send.as(String)
        end
      {% end %}
    end
  end

  struct TypedPromptRequest(T, S, M)
    getter inner : Crig::PromptRequest(S, M)

    def initialize(@inner : Crig::PromptRequest(S, M))
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      schema = JSON.parse(%({"title":"#{T}"}))
      inner = Crig::PromptRequest(Crig::Standard, M).from_agent(agent, prompt)
      inner.runner.output_schema(schema)
      inner.runner.output_mode(Crig::OutputMode::Native)
      new(inner)
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

    def send_async
      {% if S == Crig::Extended %}
        Crig::Concurrency.run do
          send.as(Crig::TypedPromptResponse(T))
        end
      {% else %}
        Crig::Concurrency.run do
          send.as(T)
        end
      {% end %}
    end
  end
end
