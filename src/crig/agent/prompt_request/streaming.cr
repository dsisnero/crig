module Crig
  class StreamingError < Exception
    enum Kind
      Completion
      Prompt
      Tool
      Other
    end

    getter kind : Kind
    getter completion_error : Crig::Completion::CompletionError?
    getter prompt_error : Crig::Completion::PromptError?
    getter tool_error : Exception?

    def initialize(
      message : String,
      @kind : Kind = Kind::Other,
      @completion_error : Crig::Completion::CompletionError? = nil,
      @prompt_error : Crig::Completion::PromptError? = nil,
      @tool_error : Exception? = nil,
    )
      super(message)
    end

    def self.completion(message : String) : self
      new("CompletionError: #{message}", Kind::Completion)
    end

    def self.completion(error : Crig::Completion::CompletionError) : self
      new("CompletionError: #{error.message}", Kind::Completion, completion_error: error)
    end

    def self.prompt(message : String) : self
      new("PromptError: #{message}", Kind::Prompt)
    end

    def self.prompt(error : Crig::Completion::PromptError) : self
      new("PromptError: #{error.message}", Kind::Prompt, prompt_error: error)
    end

    def self.tool(message : String) : self
      new("ToolSetError: #{message}", Kind::Tool)
    end

    def self.tool(error : Exception) : self
      new("ToolSetError: #{error.message || error.class.name}", Kind::Tool, tool_error: error)
    end
  end

  struct MultiTurnStreamingResult(R)
    getter items : Array(Crig::MultiTurnStreamItem(R))

    def initialize(@items : Array(Crig::MultiTurnStreamItem(R)))
    end
  end

  struct MultiTurnStreamItem(R)
    enum Kind
      StreamAssistantItem
      StreamUserItem
      ToolExecutionCommitted
      FinalResponse
    end

    getter kind : Kind
    getter assistant_item : Crig::StreamedAssistantContent(R)?
    getter user_item : Crig::StreamedUserContent?
    getter tool_results : Array(Crig::Completion::UserContent)?
    getter final_response : Crig::PromptResponse?

    def initialize(
      @kind : Kind,
      @assistant_item : Crig::StreamedAssistantContent(R)? = nil,
      @user_item : Crig::StreamedUserContent? = nil,
      @tool_results : Array(Crig::Completion::UserContent)? = nil,
      @final_response : Crig::PromptResponse? = nil,
    )
    end

    def self.stream_item(item : Crig::StreamedAssistantContent(R)) : self
      new(Kind::StreamAssistantItem, assistant_item: item)
    end

    def self.tool_execution_committed(results : Array(Crig::Completion::UserContent)) : self
      new(Kind::ToolExecutionCommitted, tool_results: results)
    end

    def self.stream_user_item(item : Crig::StreamedUserContent) : self
      new(Kind::StreamUserItem, user_item: item)
    end

    def self.final_response(response : String, aggregated_usage : Crig::Completion::Usage) : self
      content = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(response))
      new(Kind::FinalResponse, final_response: Crig::PromptResponse.new(response, aggregated_usage, content: content))
    end

    def self.final_response_with_history(
      response : String,
      aggregated_usage : Crig::Completion::Usage,
      history : Array(Crig::Completion::Message)?,
    ) : self
      content = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(response))
      new(Kind::FinalResponse, final_response: Crig::PromptResponse.new(response, aggregated_usage, history, content: content))
    end
  end

  # Deprecated: use `agent.runner(prompt).stream()` instead.
  struct StreamingPromptRequest(M)
    getter agent : Crig::Agent(M)
    getter prompt : Crig::Completion::Message
    getter chat_history : Array(Crig::Completion::Message)?
    getter max_turns : Int32
    getter memory : Crig::Memory::ConversationMemory?
    getter conversation_id : String?
    @hooks : Array(AgentHook)?

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @chat_history : Array(Crig::Completion::Message)? = nil,
      @max_turns : Int32 = 1,
      @memory : Crig::Memory::ConversationMemory? = nil,
      @conversation_id : String? = nil,
    )
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      new(agent, prompt_message, nil, agent.default_max_turns || 1, memory: agent.memory, conversation_id: agent.default_conversation_id)
    end

    def max_turns(turns : Int) : self
      self.class.new(@agent, @prompt, @chat_history, turns.to_i32, @memory, @conversation_id)
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      self.class.new(@agent, @prompt, history.dup, @max_turns, @memory, @conversation_id)
    end

    def with_hook(hook : AgentHook) : self
      @hooks = (@hooks || [] of AgentHook).tap(&.<<(hook))
      self
    end

    # Set the conversation id used to load and persist memory for this request.
    def conversation(id : String) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, @memory, id)
    end

    # Disable conversation memory for this request.
    def without_memory : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, nil, nil)
    end

    def send_items : Crig::MultiTurnStreamingResult(Crig::PromptResponse)
      history = (@chat_history || [] of Crig::Completion::Message).dup
      has_history = !@chat_history.nil?
      items = [] of Crig::MultiTurnStreamItem(Crig::PromptResponse)
      aggregated_usage = Crig::Completion::Usage.new
      current_prompt = @prompt
      current_turn = 0

      loop do
        if current_turn >= @max_turns
          error = Crig::Completion::PromptError.max_turns_exceeded(@max_turns, history, current_prompt)
          raise Crig::StreamingError.prompt(error)
        end

        current_turn += 1
        maybe_run_completion_hook(current_prompt, history)

        stream = @agent.build_completion_request(current_prompt, history).stream(@agent.model)
        history << current_prompt

        turn_result = process_stream_turn(stream, current_prompt, history, items)
        aggregated_usage += turn_result.usage

        if turn_result.saw_tool_call
          append_tool_turn_history(history, turn_result.reasoning, turn_result.tool_calls, turn_result.tool_results)
          current_prompt = history.pop || current_prompt
          next
        end

        final_history = history.dup
        final_history << Crig::Completion::Message.assistant(turn_result.response_text) unless turn_result.response_text.empty?
        content = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(turn_result.response_text))
        final_response = Crig::PromptResponse.new(
          turn_result.response_text,
          aggregated_usage,
          has_history ? final_history : nil,
          content: content,
        )

        items << Crig::MultiTurnStreamItem(Crig::PromptResponse).final_response_with_history(
          final_response.output,
          final_response.usage,
          final_response.messages,
        )
        return Crig::MultiTurnStreamingResult(Crig::PromptResponse).new(items)
      end
    end

    def send : Crig::StreamingCompletionResponse(Crig::PromptResponse)
      items = send_items
      final_response = items.items.last.final_response || Crig::PromptResponse.empty
      chunks = items.items.compact_map do |item|
        item.assistant_item.try(&.text).try(&.text)
      end
      Crig::StreamingCompletionResponse(Crig::PromptResponse).new(chunks, final_response)
    end

    def send_async : Channel(Crig::Concurrency::Result(Crig::StreamingCompletionResponse(Crig::PromptResponse)))
      Crig::Concurrency.run do
        send
      end
    end

    private record StreamTurnResult,
      response_text : String,
      saw_tool_call : Bool,
      tool_calls : Array(Crig::Completion::AssistantContent),
      tool_results : Array(Tuple(String, String?, String)),
      reasoning : Array(Crig::Completion::Reasoning),
      usage : Crig::Completion::Usage

    private def maybe_run_completion_hook(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Nil
      return unless hooks = @hooks
      ctx = HookContext.new(is_streaming: true, agent_name: @agent.name)
      event = StepEvent.completion_call(prompt.rag_text || "", history.size)
      hooks.each do |hook|
        flow = hook.on_event(ctx, event)
        if flow.kind.terminate?
          raise Crig::StreamingError.prompt(Crig::Completion::PromptError.prompt_cancelled(history.dup, flow.reason || "terminated"))
        end
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    private def process_stream_turn(
      stream,
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
      items : Array(Crig::MultiTurnStreamItem(Crig::PromptResponse)),
    ) : StreamTurnResult
      response_text = ""
      saw_text = false
      saw_tool_call = false
      tool_calls = [] of Crig::Completion::AssistantContent
      tool_results = [] of Tuple(String, String?, String)
      pending_tool_calls = [] of Tuple(Crig::Completion::ToolCall, String)
      reasoning = [] of Crig::Completion::Reasoning
      turn_usage = Crig::Completion::Usage.new
      pending_reasoning_delta_text = ""
      pending_reasoning_delta_id = nil.as(String?)

      stream.each_item do |item|
        case item.kind
        in .text?
          if text = item.text
            saw_text = true
            response_text += text.text

            items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::PromptResponse).text(text.text)
            )
          end
        in .reasoning?
          if reasoning_item = item.reasoning
            Crig.merge_reasoning_blocks(reasoning, reasoning_item)
            items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::PromptResponse).reasoning(reasoning_item)
            )
          end
        in .reasoning_delta?
          if delta = item.reasoning_delta
            pending_reasoning_delta_text += delta
            pending_reasoning_delta_id ||= item.id
            items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::PromptResponse).reasoning_delta(item.id, delta)
            )
          end
        in .tool_call_delta?
        in .tool_call?
          if tool_call = item.tool_call
            internal_call_id = item.internal_call_id || tool_call.call_id || tool_call.id
            saw_tool_call = true

            items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::PromptResponse).tool_call(tool_call, internal_call_id)
            )

            tool_calls << Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::ToolCall,
              tool_call: tool_call,
            )

            pending_tool_calls << {tool_call, internal_call_id}
          end
        in .final?
          if final = item.final
            turn_usage += final.token_usage || Crig::Completion::Usage.new
            if saw_text
              items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_item(
                Crig::StreamedAssistantContent(Crig::PromptResponse).final_response(
                  Crig::PromptResponse.new(response_text, turn_usage)
                )
              )
            end
          end
        end
      end

      if reasoning.empty? && !pending_reasoning_delta_text.empty?
        assembled = Crig::Completion::Reasoning.new(pending_reasoning_delta_text)
        assembled = assembled.with_id(pending_reasoning_delta_id) if pending_reasoning_delta_id
        reasoning << assembled
      end

      unless pending_tool_calls.empty?
        executed_tool_results = Crig::Concurrency.map_ordered(pending_tool_calls) do |tool_call, internal_call_id|
          {tool_call, internal_call_id, execute_tool_call(tool_call, internal_call_id, history)}
        end

        committed_user_contents = executed_tool_results.map do |tool_call, _internal_call_id, tool_result|
          Crig::Completion::UserContent.tool_result_with_call_id(
            tool_call.id,
            tool_call.call_id || tool_call.id,
            Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
              Crig::Completion::ToolResultContent.text(tool_result)
            ),
          )
        end

        items << Crig::MultiTurnStreamItem(Crig::PromptResponse).tool_execution_committed(committed_user_contents)

        executed_tool_results.each do |tool_call, internal_call_id, tool_result|
          tool_results << {tool_call.id, tool_call.call_id, tool_result}
          items << Crig::MultiTurnStreamItem(Crig::PromptResponse).stream_user_item(
            Crig::StreamedUserContent.tool_result(
              Crig::Completion::ToolResult.new(
                tool_call.id,
                Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
                  Crig::Completion::ToolResultContent.text(tool_result)
                ),
                tool_call.call_id,
              ),
              internal_call_id,
            )
          )
        end
      end

      StreamTurnResult.new(response_text, saw_tool_call, tool_calls, tool_results, reasoning, turn_usage)
    end

    # ameba:enable Metrics/CyclomaticComplexity

    private def execute_tool_call(
      tool_call : Crig::Completion::ToolCall,
      internal_call_id : String,
      history : Array(Crig::Completion::Message),
    ) : String
      args = tool_call.function.arguments.to_json

      ctx = HookContext.new(is_streaming: true, agent_name: @agent.name)
      if hs = @hooks
        evt = StepEvent.tool_call(tool_call.function.name, tool_call.call_id, internal_call_id, args)
        hs.each do |hook|
          flow = hook.on_event(ctx, evt)
          if flow.kind.terminate?
            raise Crig::StreamingError.prompt(Crig::Completion::PromptError.prompt_cancelled(history.dup, flow.reason || "terminated"))
          end
          if flow.kind.skip?
            return flow.reason || ""
          end
        end
      end

      handle = @agent.tool_server_handle
      raise Crig::StreamingError.tool("No tool server handle configured") unless handle

      result = begin
        handle.call_tool(tool_call.function.name, args)
      rescue ex
        raise Crig::StreamingError.tool(ex)
      end

      if hs = @hooks
        evt = StepEvent.tool_result(tool_call.function.name, tool_call.call_id, internal_call_id, args, result)
        hs.each do |hook|
          flow = hook.on_event(ctx, evt)
          if flow.kind.terminate?
            raise Crig::StreamingError.prompt(Crig::Completion::PromptError.prompt_cancelled(history.dup, flow.reason || "terminated"))
          end
        end
      end

      result
    end

    private def append_tool_turn_history(
      history : Array(Crig::Completion::Message),
      reasoning : Array(Crig::Completion::Reasoning),
      tool_calls : Array(Crig::Completion::AssistantContent),
      tool_results : Array(Tuple(String, String?, String)),
    ) : Nil
      if !reasoning.empty? || !tool_calls.empty?
        assistant_items = [] of Crig::Completion::AssistantContent
        reasoning.each do |item|
          assistant_items << Crig::Completion::AssistantContent.new(
            Crig::Completion::AssistantContent::Kind::Reasoning,
            reasoning: item,
          )
        end
        assistant_items.concat(tool_calls)
        history << Crig::Completion::Message.from(
          Crig::OneOrMany(Crig::Completion::AssistantContent).many(assistant_items)
        )
      end

      tool_results.each do |id, call_id, tool_result|
        history << Crig.tool_result_to_user_message(id, call_id, tool_result)
      end
    end
  end

  def self.merge_reasoning_blocks(
    accumulated_reasoning : Array(Crig::Completion::Reasoning),
    incoming : Crig::Completion::Reasoning,
  ) : Array(Crig::Completion::Reasoning)
    if incoming_id = incoming.id
      if index = accumulated_reasoning.rindex { |existing| existing.id == incoming_id }
        merged_content = accumulated_reasoning[index].content + incoming.content
        accumulated_reasoning[index] = Crig::Completion::Reasoning.new(
          merged_content,
          accumulated_reasoning[index].id,
        )
        return accumulated_reasoning
      end
    end

    accumulated_reasoning << incoming
    accumulated_reasoning
  end

  def self.tool_result_to_user_message(
    id : String,
    call_id : String?,
    tool_result : String,
  ) : Crig::Completion::Message
    content = Crig::Completion::ToolResultContent.from_tool_output(tool_result)
    user_content = if call_id
                     Crig::Completion::UserContent.tool_result_with_call_id(id, call_id, content)
                   else
                     Crig::Completion::UserContent.tool_result(id, content)
                   end

    Crig::Completion::Message.from(user_content)
  end

  def self.stream_to_stdout(stream : Crig::MultiTurnStreamingResult(R), io : IO = STDOUT) : Crig::PromptResponse forall R
    final_res = Crig::PromptResponse.empty
    io.print("Response: ")
    stream.items.each do |content|
      case content.kind
      in .stream_assistant_item?
        if assistant_item = content.assistant_item
          case assistant_item.kind
          in .text?
            if text = assistant_item.text
              io.print(text.text)
              io.flush
            end
          in .tool_call?
          in .tool_call_delta?
          in .reasoning?
            if reasoning = assistant_item.reasoning
              io.print(reasoning.display_text)
              io.flush
            end
          in .reasoning_delta?
          in .final?
          end
        end
      in .tool_execution_committed?
      in .stream_user_item?
      in .final_response?
        final_res = content.final_response || final_res
      end
    end

    final_res
  end
end
