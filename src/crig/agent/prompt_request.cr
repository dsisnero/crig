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

  abstract class PromptHook
    def on_completion_call(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Crig::HookAction
      Crig::HookAction.cont
    end

    def on_completion_response(
      prompt : Crig::Completion::Message,
      response : Crig::Completion::CompletionResponse(String),
    ) : Crig::HookAction
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

  struct PromptResponse
    getter output : String
    getter usage : Crig::Completion::Usage
    getter messages : Array(Crig::Completion::Message)?

    def initialize(
      @output : String,
      @usage : Crig::Completion::Usage,
      @messages : Array(Crig::Completion::Message)? = nil,
    )
    end

    def with_messages(messages : Array(Crig::Completion::Message)) : self
      self.class.new(@output, @usage, messages)
    end

    def to_s(io : IO) : Nil
      io << @output
    end
  end

  struct TypedPromptResponse(T)
    getter output : T
    getter usage : Crig::Completion::Usage

    def initialize(@output : T, @usage : Crig::Completion::Usage)
    end
  end

  struct PromptRequest(S, M)
    getter prompt : Crig::Completion::Message
    getter chat_history : Array(Crig::Completion::Message)?
    getter max_turns : Int32
    getter concurrency : Int32
    getter agent : Crig::Agent(M)
    getter hook : Crig::PromptHook?

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @chat_history : Array(Crig::Completion::Message)? = nil,
      @max_turns : Int32 = 0,
      @concurrency : Int32 = 1,
      @hook : Crig::PromptHook? = nil,
    )
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      new(agent, prompt_message, nil, agent.default_max_turns || 0)
    end

    def extended_details : PromptRequest(Crig::Extended, M)
      PromptRequest(Crig::Extended, M).new(@agent, @prompt, @chat_history, @max_turns, @concurrency, @hook)
    end

    def max_turns(depth : Int) : self
      self.class.new(@agent, @prompt, @chat_history, depth.to_i32, @concurrency, @hook)
    end

    def with_tool_concurrency(concurrency : Int) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, concurrency.to_i32, @hook)
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      self.class.new(@agent, @prompt, history.dup, @max_turns, @concurrency, @hook)
    end

    def with_hook(hook : Crig::PromptHook) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, @concurrency, hook)
    end

    def send
      {% if S == Crig::Extended %}
        history = (@chat_history || [] of Crig::Completion::Message).dup
        if hook = @hook
          action = hook.on_completion_call(@prompt, history)
          if action.kind.terminate?
            reason = action.reason || "terminated"
            raise Crig::Completion::PromptError.prompt_cancelled(history, reason)
          end
        end

        response = @agent.completion(@prompt, history).send(@agent.model)
        if hook = @hook
          action = hook.on_completion_response(@prompt, response)
          if action.kind.terminate?
            reason = action.reason || "terminated"
            raise Crig::Completion::PromptError.prompt_cancelled(history, reason)
          end
        end

        output = response.choice.to_a.compact_map do |content|
          next unless content.kind.text?
          content.text.try(&.text)
        end.join("\n")

        messages = history + [
          @prompt,
          Crig::Completion::Message.from(response.choice),
        ]

        Crig::PromptResponse.new(output, response.usage).with_messages(messages)
      {% else %}
        extended_details.send.output
      {% end %}
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
        Crig::TypedPromptResponse(T).new(T.from_json(response.output), response.usage)
      {% else %}
        T.from_json(@inner.send)
      {% end %}
    end
  end
end
