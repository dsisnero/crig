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
    include JSON::Serializable

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
      new(agent, prompt_message, nil, agent.default_max_turns || 0, memory: agent.memory, conversation_id: agent.default_conversation_id)
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

    def send
      {% if S == Crig::Extended %}
        chat_history = (@chat_history || [] of Crig::Completion::Message).dup
        chat_history << @prompt

        current_max_turns = 0
        usage = Crig::Completion::Usage.new

        last_prompt = loop do
          prompt = chat_history.last

          if current_max_turns > @max_turns + 1
            break prompt
          end

          current_max_turns += 1

          run_completion_call_hook(prompt, chat_history[0...-1])

          response = @agent.completion(prompt, chat_history[0...-1]).send(@agent.model)
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

          if tool_calls.empty?
            output = text_parts.join("\n")
            return Crig::PromptResponse.new(output, usage).with_messages(chat_history.dup)
          end

          tool_content = execute_tool_calls(tool_calls, chat_history)
          chat_history << Crig::Completion::Message.from(Crig::OneOrMany(Crig::Completion::UserContent).many(tool_content))
        end

        raise Crig::Completion::PromptError.max_turns_exceeded(@max_turns, chat_history.dup, last_prompt)
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
      results = [] of ToolExecutionResult
      limit = Math.max(@concurrency, 1)

      tool_calls.each_slice(limit) do |batch|
        channels = batch.each_with_index.map do |choice, index|
          global_index = (results.size + index).to_i32
          Crig::Concurrency.run do
            execute_tool_call(choice, chat_history.dup, global_index)
          end
        end

        batch_results = channels.map do |channel|
          channel.receive.unwrap
        end
        results.concat(batch_results)
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
        Crig::TypedPromptResponse(T).new(T.from_json(response.output), response.usage)
      {% else %}
        T.from_json(@inner.send)
      {% end %}
    end
  end
end
