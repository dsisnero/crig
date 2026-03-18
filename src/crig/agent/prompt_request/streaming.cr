module Crig
  class StreamingError < Exception
    def self.completion(message : String) : self
      new("CompletionError: #{message}")
    end

    def self.prompt(message : String) : self
      new("PromptError: #{message}")
    end

    def self.tool(message : String) : self
      new("ToolSetError: #{message}")
    end
  end

  struct MultiTurnStreamingResult(R)
    getter items : Array(Crig::MultiTurnStreamItem(R))

    def initialize(@items : Array(Crig::MultiTurnStreamItem(R)))
    end
  end

  struct FinalResponse
    getter response : String
    getter aggregated_usage : Crig::Completion::Usage
    getter history : Array(Crig::Completion::Message)?

    def initialize(
      @response : String,
      @aggregated_usage : Crig::Completion::Usage,
      @history : Array(Crig::Completion::Message)? = nil,
    )
    end

    def self.empty : self
      new("", Crig::Completion::Usage.new)
    end

    def usage : Crig::Completion::Usage
      @aggregated_usage
    end
  end

  struct MultiTurnStreamItem(R)
    enum Kind
      StreamAssistantItem
      StreamUserItem
      FinalResponse
    end

    getter kind : Kind
    getter assistant_item : Crig::StreamedAssistantContent(R)?
    getter user_item : Crig::StreamedUserContent?
    getter final_response : Crig::FinalResponse?

    def initialize(
      @kind : Kind,
      @assistant_item : Crig::StreamedAssistantContent(R)? = nil,
      @user_item : Crig::StreamedUserContent? = nil,
      @final_response : Crig::FinalResponse? = nil,
    )
    end

    def self.stream_item(item : Crig::StreamedAssistantContent(R)) : self
      new(Kind::StreamAssistantItem, assistant_item: item)
    end

    def self.stream_user_item(item : Crig::StreamedUserContent) : self
      new(Kind::StreamUserItem, user_item: item)
    end

    def self.final_response(response : String, aggregated_usage : Crig::Completion::Usage) : self
      new(Kind::FinalResponse, final_response: Crig::FinalResponse.new(response, aggregated_usage))
    end

    def self.final_response_with_history(
      response : String,
      aggregated_usage : Crig::Completion::Usage,
      history : Array(Crig::Completion::Message)?,
    ) : self
      new(Kind::FinalResponse, final_response: Crig::FinalResponse.new(response, aggregated_usage, history))
    end
  end

  struct StreamingPromptRequest(M)
    getter agent : Crig::Agent(M)
    getter prompt : Crig::Completion::Message
    getter chat_history : Array(Crig::Completion::Message)?
    getter max_turns : Int32
    getter hook : Crig::PromptHook?

    def initialize(
      @agent : Crig::Agent(M),
      @prompt : Crig::Completion::Message,
      @chat_history : Array(Crig::Completion::Message)? = nil,
      @max_turns : Int32 = 0,
      @hook : Crig::PromptHook? = nil,
    )
    end

    def self.from_agent(agent : Crig::Agent(M), prompt : Crig::Completion::Message | String) : self
      prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
      new(agent, prompt_message, nil, agent.default_max_turns || 0)
    end

    def multi_turn(turns : Int) : self
      self.class.new(@agent, @prompt, @chat_history, turns.to_i32, @hook)
    end

    def with_history(history : Array(Crig::Completion::Message)) : self
      self.class.new(@agent, @prompt, history.dup, @max_turns, @hook)
    end

    def with_hook(hook : Crig::PromptHook) : self
      self.class.new(@agent, @prompt, @chat_history, @max_turns, hook)
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def send_items : Crig::MultiTurnStreamingResult(Crig::FinalResponse)
      history = (@chat_history || [] of Crig::Completion::Message).dup
      has_history = !@chat_history.nil?
      items = [] of Crig::MultiTurnStreamItem(Crig::FinalResponse)
      aggregated_usage = Crig::Completion::Usage.new
      current_prompt = @prompt
      current_turn = 0

      loop do
        if current_turn > @max_turns + 1
          error = Crig::Completion::PromptError.max_turns_exceeded(@max_turns, history, current_prompt)
          raise Crig::StreamingError.prompt(
            error.reason || error.message || "MaxTurnsExceeded: #{@max_turns}"
          )
        end

        current_turn += 1
        maybe_run_completion_hook(current_prompt, history)

        stream = @agent.stream_completion(current_prompt, history).stream(@agent.model)
        aggregated_usage = aggregated_usage + (stream.response.try(&.usage) || Crig::Completion::Usage.new)
        history << current_prompt

        turn_result = process_stream_turn(stream, current_prompt, history, items)

        if turn_result.saw_tool_call
          append_tool_turn_history(history, turn_result.reasoning, turn_result.tool_calls, turn_result.tool_results)
          current_prompt = history.pop || current_prompt
          next
        end

        final_history = history.dup
        final_history << Crig::Completion::Message.assistant(turn_result.response_text) unless turn_result.response_text.empty?
        final_response = Crig::FinalResponse.new(
          turn_result.response_text,
          aggregated_usage,
          has_history ? final_history : nil,
        )

        if hook = @hook
          action = hook.on_stream_completion_response_finish(current_prompt, final_response)
          if action.kind.terminate?
            reason = action.reason || "terminated"
            raise Crig::StreamingError.prompt("PromptCancelled: #{reason}")
          end
        end

        items << Crig::MultiTurnStreamItem(Crig::FinalResponse).final_response_with_history(
          final_response.response,
          final_response.usage,
          final_response.history,
        )
        return Crig::MultiTurnStreamingResult(Crig::FinalResponse).new(items)
      end
    end

    # ameba:enable Metrics/CyclomaticComplexity

    def send : Crig::StreamingCompletionResponse(Crig::FinalResponse)
      items = send_items
      final_response = items.items.last.final_response || Crig::FinalResponse.empty
      chunks = items.items.compact_map do |item|
        item.assistant_item.try(&.text).try(&.text)
      end
      Crig::StreamingCompletionResponse(Crig::FinalResponse).new(chunks, final_response)
    end

    private record StreamTurnResult,
      response_text : String,
      saw_tool_call : Bool,
      tool_calls : Array(Crig::Completion::AssistantContent),
      tool_results : Array(Tuple(String, String?, String)),
      reasoning : Array(Crig::Completion::Reasoning)

    private def maybe_run_completion_hook(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Nil
      if hook = @hook
        action = hook.on_completion_call(prompt, history)
        if action.kind.terminate?
          reason = action.reason || "terminated"
          raise Crig::StreamingError.prompt("PromptCancelled: #{reason}")
        end
      end
    end

    private def process_stream_turn(
      stream,
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
      items : Array(Crig::MultiTurnStreamItem(Crig::FinalResponse)),
    ) : StreamTurnResult
      response_text = ""
      saw_tool_call = false
      tool_calls = [] of Crig::Completion::AssistantContent
      tool_results = [] of Tuple(String, String?, String)
      reasoning = [] of Crig::Completion::Reasoning

      stream.choice.each do |assistant_content|
        case assistant_content.kind
        in .text?
          if text = assistant_content.text
            response_text += text.text
            if hook = @hook
              action = hook.on_text_delta(text.text, response_text)
              if action.kind.terminate?
                reason = action.reason || "terminated"
                raise Crig::StreamingError.prompt("PromptCancelled: #{reason}")
              end
            end

            items << Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::FinalResponse).text(text.text)
            )
          end
        in .reasoning?
          if reasoning_item = assistant_content.reasoning
            Crig.merge_reasoning_blocks(reasoning, reasoning_item)
            items << Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::FinalResponse).reasoning(reasoning_item)
            )
          end
        in .tool_call?
          if tool_call = assistant_content.tool_call
            internal_call_id = tool_call.call_id || tool_call.id
            saw_tool_call = true

            items << Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_item(
              Crig::StreamedAssistantContent(Crig::FinalResponse).tool_call(tool_call, internal_call_id)
            )

            tool_calls << assistant_content

            tool_result = execute_tool_call(tool_call, internal_call_id, history)
            tool_results << {tool_call.id, tool_call.call_id, tool_result}
            items << Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_user_item(
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
        in .image?
        end
      end

      StreamTurnResult.new(response_text, saw_tool_call, tool_calls, tool_results, reasoning)
    end

    private def execute_tool_call(
      tool_call : Crig::Completion::ToolCall,
      internal_call_id : String,
      history : Array(Crig::Completion::Message),
    ) : String
      args = tool_call.function.arguments.to_json

      if hook = @hook
        action = hook.on_tool_call(tool_call.function.name, tool_call.call_id, internal_call_id, args)
        case action.kind
        in .terminate?
          reason = action.reason || "terminated"
          raise Crig::StreamingError.prompt("PromptCancelled: #{reason}")
        in .skip?
          return action.reason || ""
        in .continue?
        end
      end

      handle = @agent.tool_server_handle
      raise Crig::StreamingError.tool("No tool server handle configured") unless handle

      result = begin
        handle.call_tool(tool_call.function.name, args)
      rescue ex
        raise Crig::StreamingError.tool(ex.message || ex.class.name)
      end

      if hook = @hook
        action = hook.on_tool_result(tool_call.function.name, tool_call.call_id, internal_call_id, args, result)
        if action.kind.terminate?
          reason = action.reason || "terminated"
          raise Crig::StreamingError.prompt("PromptCancelled: #{reason}")
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
    content = Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
      Crig::Completion::ToolResultContent.text(tool_result)
    )
    user_content = if call_id
                     Crig::Completion::UserContent.tool_result_with_call_id(id, call_id, content)
                   else
                     Crig::Completion::UserContent.tool_result(id, content)
                   end

    Crig::Completion::Message.from(user_content)
  end

  def self.stream_to_stdout(stream : Crig::MultiTurnStreamingResult(R), io : IO = STDOUT) : Crig::FinalResponse forall R
    final_res = Crig::FinalResponse.empty
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
      in .stream_user_item?
      in .final_response?
        final_res = content.final_response || final_res
      end
    end

    final_res
  end
end
