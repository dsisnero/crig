module Crig
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
    getter content : Crig::OneOrMany(Crig::Completion::AssistantContent)

    def initialize(
      @output : String,
      @usage : Crig::Completion::Usage,
      @messages : Array(Crig::Completion::Message)? = nil,
      @completion_calls : Array(CompletionCall) = [] of CompletionCall,
      @content : Crig::OneOrMany(Crig::Completion::AssistantContent) = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("")),
    )
    end

    def with_messages(messages : Array(Crig::Completion::Message)) : self
      self.class.new(@output, @usage, messages, @completion_calls, @content)
    end

    def with_completion_calls(calls : Array(CompletionCall)) : self
      self.class.new(@output, @usage, @messages, calls, @content)
    end

    def with_content(content : Crig::OneOrMany(Crig::Completion::AssistantContent)) : self
      self.class.new(@output, @usage, @messages, @completion_calls, content)
    end

    def self.empty : self
      new("", Crig::Completion::Usage.new)
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
    getter agent : Crig::Agent(M)
    getter prompt : Crig::Completion::Message
    getter runner : AgentRunner(M)
    getter memory : Crig::Memory::ConversationMemory?
    getter conversation_id : String?

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @runner : AgentRunner(M),
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
        .max_turns(agent.default_max_turns || 1)
      new(agent, prompt_message, runner, memory: agent.memory, conversation_id: agent.default_conversation_id)
    end

    def extended_details : PromptRequest(Crig::Extended, M)
      PromptRequest(Crig::Extended, M).new(@agent, @prompt, @runner, @memory, @conversation_id)
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

    def with_hook(hook : AgentHook) : self
      @runner.add_hook(hook)
      self
    end

    def conversation(id : String) : self
      self.class.new(@agent, @prompt, @runner, @memory, id)
    end

    def without_memory : self
      self.class.new(@agent, @prompt, @runner, nil, nil)
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

    def with_hook(hook : AgentHook) : self
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
