require "wait_group"

module Crig
  class AgentRunner(M)
    @model : M
    @max_turns : Int32 = 0
    @max_invalid_tool_call_retries : Int32 = 0
    @agent_name : String? = nil
    @preamble : String? = nil
    @static_context : Array(Completion::Request::Document) = [] of Completion::Request::Document
    @temperature : Float64? = nil
    @max_tokens : UInt64? = nil
    @additional_params : JSON::Any?
    @tool_choice : Completion::ToolChoice?
    @output_tool_name : String? = nil
    @output_mode : OutputMode = OutputMode::Auto
    @concurrency : Int32 = 1
    @tool_extensions : Tool::ToolCallExtensions = Tool::ToolCallExtensions.new
    @tool_server_handle : ToolServerHandle?
    @hooks : Array(AgentHook) = [] of AgentHook

    def initialize(@model : M)
    end

    def max_turns(v : Int32) : self
      @max_turns = v; self
    end

    def max_invalid_tool_call_retries(v : Int32) : self
      @max_invalid_tool_call_retries = v; self
    end

    def tool_concurrency(v : Int32) : self
      @concurrency = v; self
    end

    def add_hook(h : AgentHook) : self
      @hooks << h; self
    end

    def tool_choice(v : Completion::ToolChoice) : self
      @tool_choice = v; self
    end

    def preamble(v : String) : self
      @preamble = v; self
    end

    def temperature(v : Float64) : self
      @temperature = v; self
    end

    def max_tokens(v : UInt64) : self
      @max_tokens = v; self
    end

    def tool_server_handle(h : ToolServerHandle) : self
      @tool_server_handle = h; self
    end

    def run(prompt : Completion::Message) : PromptResponse
      ctx = HookContext.new(is_streaming: false, agent_name: @agent_name)
      run = build_run(prompt)

      loop do
        step = run.next_step
        case step.kind
        in .call_model? then drive_call_model(ctx, run, step)
        in .call_tools? then drive_call_tools(ctx, run, step)
        in .done?       then return step.response.not_nil!
        end
      end
    end

    def stream(prompt : Completion::Message) : Channel(StreamItem)
      ch = Channel(StreamItem).new(16)
      spawn do
        begin
          stream_loop(prompt, ch)
        rescue ex : Completion::PromptError
          ch.send(StreamError.new(ex))
        rescue ex : Exception
          ch.send(StreamError.new(ex))
        ensure
          ch.close
        end
      end
      ch
    end

    private def build_run(prompt : Completion::Message) : AgentRun
      run = AgentRun.new(prompt)
        .max_turns(@max_turns)
        .max_invalid_tool_call_retries(@max_invalid_tool_call_retries)
      run.with_tool_choice(@tool_choice.not_nil!) if @tool_choice
      run.with_output_tool_name(@output_tool_name.not_nil!) if @output_tool_name
      run
    end

    private def stream_loop(prompt, ch)
      ctx = HookContext.new(is_streaming: true, agent_name: @agent_name)
      run = build_run(prompt)

      loop do
        step = run.next_step
        case step.kind
        in .call_model?
          turn = step.turn.not_nil!
          sprompt = step.prompt.not_nil!
          shistory = step.history.not_nil!
          ctx.set_turn(turn)

          call_event = StepEvent.completion_call(sprompt.rag_text || "", turn)
          patch = dispatch_completion_call_hook(ctx, call_event)

          builder = build_completion_request(sprompt, shistory, patch)
          response = @model.completion(builder.build)
          choice = response.choice

          text = choice_text(choice)
          unless text.empty?
            ch.send(StreamTextDelta.new(text, text))
          end

          resp_event = StepEvent.completion_response
          dispatch_hook(ctx, resp_event)

          exe_tools = builder.tools.map(&.name)
          turn_data = ModelTurn.new(choice: choice, usage: response.usage, allowed_tools: exe_tools)
          outcome = run.model_response(turn_data)
          handle_outcome(run, ctx, outcome)
        in .call_tools?
          calls = step.calls.not_nil!
          results = execute_tools(run, ctx, calls)
          results.each do |r|
            if tr = r.tool_result
              ch.send(StreamToolResult.new(tr.id, "tool_result"))
            end
          end
          run.tool_results(results)
        in .done?
          ch.send(StreamDone.new(step.response.not_nil!))
          break
        end
      end
    end

    private def drive_call_model(ctx, run, step)
      turn = step.turn.not_nil!
      sprompt = step.prompt.not_nil!
      shistory = step.history.not_nil!
      ctx.set_turn(turn)

      # 1. Dispatch CompletionCall hook (matching upstream: resolve_completion_call)
      call_event = StepEvent.completion_call(sprompt.rag_text || "", turn)
      patch = dispatch_completion_call_hook(ctx, call_event)

      # 2. Build request (matching upstream: build_prepared_completion_request)
      builder = build_completion_request(sprompt, shistory, patch)
      request = builder.build

      # 3. Call model
      response = @model.completion(request)

      # 4. Dispatch CompletionResponse hook
      resp_event = StepEvent.completion_response
      dispatch_hook(ctx, resp_event)

      # 7. Feed model response to state machine
      exe_tools = request.tools ? request.tools.not_nil!.map(&.name) : [] of String
      turn_data = ModelTurn.new(choice: response.choice, usage: response.usage, allowed_tools: exe_tools)
      outcome = run.model_response(turn_data)
      handle_outcome(run, ctx, outcome)
    end

    private def drive_call_tools(ctx, run, step)
      calls = step.calls.not_nil!
      results = execute_tools(run, ctx, calls)
      run.tool_results(results)
    end

    private def build_completion_request(sprompt, shistory, patch : RequestPatch?) : Completion::Request::CompletionRequestBuilder
      builder = @model.completion_request(sprompt)
      builder = builder.messages(shistory) unless shistory.empty?
      builder = builder.documents(@static_context) unless @static_context.empty?

      # Add tool definitions from tool server (matching upstream: tool_server_handle.get_tool_defs)
      if tsh = @tool_server_handle
        tool_defs = tsh.get_tool_defs(nil)
        builder = builder.tools(tool_defs) unless tool_defs.empty?
      end

      # Apply patch (matching upstream: patch → baseline)
      p = patch
      effective_preamble = (p.try(&.preamble) || @preamble)
      effective_temp = (p.try(&.temperature) || @temperature)
      effective_tokens = (p.try(&.max_tokens) || @max_tokens)
      effective_choice = (p.try(&.tool_choice) || @tool_choice)

      builder = builder.preamble(effective_preamble.not_nil!) if effective_preamble
      builder = builder.temperature(effective_temp.not_nil!) if effective_temp
      builder = builder.max_tokens(effective_tokens.not_nil!.to_i64) if effective_tokens
      builder = builder.tool_choice(effective_choice.not_nil!) if effective_choice
      builder = builder.additional_params_opt(@additional_params) if @additional_params

      # Apply active_tools filter from patch (intersects with baseline tool set)
      if p.try(&.active_tools)
        active = p.not_nil!.active_tools.not_nil!
        current_tools = builder.tools.select { |t| active.includes?(t.name) }
        builder = builder.tools(current_tools)
      end

      builder
    end

    private def choice_text(choice : OneOrMany(Completion::AssistantContent)) : String
      choice.to_a.flat_map { |i| i.text.try(&.text) || [""] }.join
    end

    private def dispatch_completion_call_hook(ctx, event) : RequestPatch?
      merged : RequestPatch? = nil
      @hooks.each do |hook|
        flow = hook.on_event(ctx, event)
        case flow.kind
        in .continue?      then next
        in .patch_request? then merged = merged ? merged.merge(flow.patch.not_nil!) : flow.patch
        in .terminate?     then raise Completion::PromptError.prompt_cancelled([] of Completion::Message, flow.reason.not_nil!)
        in .skip?, .rewrite_args?, .rewrite_result?, .fail?, .retry?, .repair?
          raise Completion::PromptError.prompt_cancelled([] of Completion::Message, "unsupported for CompletionCall: #{flow.kind}")
        end
      end
      merged
    end

    private def dispatch_hook(ctx, event) : Nil
      @hooks.each do |hook|
        flow = hook.on_event(ctx, event)
        case flow.kind
        in .continue?  then next
        in .terminate? then raise Completion::PromptError.prompt_cancelled([] of Completion::Message, flow.reason.not_nil!)
        in .skip?, .rewrite_args?, .rewrite_result?, .patch_request?, .fail?, .retry?, .repair?
          raise Completion::PromptError.prompt_cancelled([] of Completion::Message, "unsupported: #{flow.kind}")
        end
      end
    end

    private def execute_tools(run, ctx, calls : Array(PendingToolCall)) : Array(Completion::UserContent)
      if @concurrency <= 1 || calls.size <= 1
        execute_tools_sequential(ctx, calls)
      else
        execute_tools_concurrent(ctx, calls)
      end
    end

    private def execute_tools_sequential(ctx, calls : Array(PendingToolCall)) : Array(Completion::UserContent)
      calls.map { |c| execute_single_call(ctx, c) }
    end

    private def execute_single_call(ctx, call : PendingToolCall) : Completion::UserContent
      tc = call.tool_call
      tool_name = tc.function.name
      args = tc.function.arguments.to_json

      call_event = StepEvent.tool_call(tool_name, tc.call_id, tc.id, args)
      effective_args = dispatch_tool_call_hook(ctx, call_event)

      result_text = execute_single_tool(tool_name, effective_args)

      result_event = StepEvent.tool_result(tool_name, tc.call_id, tc.id, args, result_text)
      effective_result = dispatch_tool_result_hook(ctx, result_event)

      content = OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text(effective_result))
      if cid = tc.call_id
        Completion::UserContent.tool_result_with_call_id(tc.id, cid, content)
      else
        Completion::UserContent.tool_result(tc.id, content)
      end
    end

    private def execute_tools_concurrent(ctx, calls : Array(PendingToolCall)) : Array(Completion::UserContent)
      results = Array(Completion::UserContent?).new(calls.size, nil)
      first_error = Atomic(Completion::PromptError?).new(nil)
      terminating = Atomic(Bool).new(false)
      sem = Channel(Bool).new(@concurrency)
      wg = WaitGroup.new(calls.size)

      calls.each_with_index do |call, index|
        spawn do
          sem.send(true)
          if terminating.get
            sem.receive; wg.done; next
          end
          begin
            results[index] = execute_single_call(ctx, call)
          rescue ex : Completion::PromptError
            first_error.compare_and_set(nil, ex)
            terminating.set(true)
          rescue ex : Exception
            first_error.compare_and_set(nil, Completion::PromptError.prompt_cancelled([] of Completion::Message, ex.message || "tool error"))
            terminating.set(true)
          end
          sem.receive; wg.done
        end
      end
      wg.wait
      if err = first_error.get
        raise err
      end
      results.compact_map { |r| r }
    end

    private def dispatch_tool_call_hook(ctx, event) : String
      effective = event.args.not_nil!
      @hooks.each do |hook|
        flow = hook.on_event(ctx, event)
        case flow.kind
        in .continue?     then next
        in .rewrite_args? then effective = flow.args.not_nil!.to_json
        in .terminate?    then raise Completion::PromptError.prompt_cancelled([] of Completion::Message, flow.reason.not_nil!)
        in .skip?, .rewrite_result?, .patch_request?, .fail?, .retry?, .repair?
          raise Completion::PromptError.prompt_cancelled([] of Completion::Message, "unsupported for ToolCall: #{flow.kind}")
        end
      end
      effective
    end

    private def dispatch_tool_result_hook(ctx, event) : String
      effective = event.result.not_nil!
      @hooks.each do |hook|
        flow = hook.on_event(ctx, event)
        case flow.kind
        in .continue?       then next
        in .rewrite_result? then effective = flow.result.not_nil!
        in .terminate?      then raise Completion::PromptError.prompt_cancelled([] of Completion::Message, flow.reason.not_nil!)
        in .skip?, .rewrite_args?, .patch_request?, .fail?, .retry?, .repair?
          raise Completion::PromptError.prompt_cancelled([] of Completion::Message, "unsupported for ToolResult: #{flow.kind}")
        end
      end
      effective
    end

    private def execute_single_tool(name : String, args : String) : String
      "#{name}_result(#{args})"
    end

    private def handle_outcome(run, ctx, outcome : ModelTurnOutcome) : Nil
      case outcome.kind
      in .needs_resolution?
        ctx2 = outcome.context.not_nil!
        raise Completion::PromptError.unknown_tool_call(
          ctx2.tool_name, ctx2.available_tools, ctx2.allowed_tools, ctx2.chat_history)
      in .turn_retried?, .continue?
      end
    end
  end
end
