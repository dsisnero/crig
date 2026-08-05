require "wait_group"

module Crig
  class AgentRunner(M)
    @model : M
    @max_turns : Int32 = 1
    @max_invalid_tool_call_retries : Int32 = 0
    @agent_name : String? = nil
    @preamble : String? = nil
    @static_context : Array(Completion::Request::Document) = [] of Completion::Request::Document
    @temperature : Float64? = nil
    @max_tokens : UInt64? = nil
    @additional_params : JSON::Any?
    @tool_choice : Completion::ToolChoice?
    @output_tool_name : String? = nil
    @output_tool_description : String = "Structured output"
    @ignore_unhandled_invalid_tool_calls : Bool = false
    @output_mode : OutputMode = OutputMode::Auto
    @output_schema : JSON::Any? = nil
    @concurrency : Int32 = 1
    @tool_context : Tool::ToolContext = Tool::ToolContext.new
    @tool_server_handle : ToolServerHandle?
    @record_content_telemetry : Bool = false
    @chat_history : Array(Completion::Message)? = nil
    @static_tools : Array(Completion::ToolDefinition) = [] of Completion::ToolDefinition
    @hooks : Array(AgentHook) = [] of AgentHook

    def initialize(@model : M)
    end

    # -- Public getters (for PromptRequest delegation) --

    def max_turns : Int32
      @max_turns
    end

    def concurrency : Int32
      @concurrency
    end

    def chat_history : Array(Completion::Message)?
      @chat_history
    end

    # -- Public setters (builder pattern) --

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

    def without_tool_choice : self
      @tool_choice = nil; self
    end

    def preamble(v : String) : self
      @preamble = v; self
    end

    def without_preamble : self
      @preamble = nil; self
    end

    def temperature(v : Float64) : self
      @temperature = v; self
    end

    def without_temperature : self
      @temperature = nil; self
    end

    def max_tokens(v : UInt64) : self
      @max_tokens = v; self
    end

    def without_max_tokens : self
      @max_tokens = nil; self
    end

    def output_tool(name : String, description : String = "Structured output") : self
      @output_tool_name = name
      @output_tool_description = description
      self
    end

    def ignore_unhandled_invalid_tool_calls : self
      @ignore_unhandled_invalid_tool_calls = true
      self
    end

    def output_schema(v : JSON::Any?) : self
      @output_schema = v; self
    end

    def output_mode(v : OutputMode) : self
      @output_mode = v; self
    end

    # Opt into recording sensitive model/tool content on GenAI spans
    # (upstream `record_content_telemetry`).
    def record_content_telemetry(enabled : Bool) : self
      @record_content_telemetry = enabled; self
    end

    def tool_server_handle(h : ToolServerHandle) : self
      @tool_server_handle = h; self
    end

    def tool_context(v : Tool::ToolContext) : self
      @tool_context = v; self
    end

    def chat_history(v : Array(Completion::Message)?) : self
      @chat_history = v; self
    end

    def static_tools(v : Array(Completion::ToolDefinition)) : self
      @static_tools = v; self
    end

    def static_context(v : Array(Completion::Request::Document)) : self
      @static_context = v; self
    end

    def additional_params(v : JSON::Any) : self
      @additional_params = v; self
    end

    def without_additional_params : self
      @additional_params = nil; self
    end

    def run(prompt : Completion::Message) : PromptResponse
      ctx = HookContext.new(is_streaming: false, agent_name: @agent_name)
      run = build_run(prompt)

      loop do
        step = run.next_step
        error_history = run.full_history
        case step.kind
        in .call_model? then drive_call_model(ctx, run, step, error_history)
        in .call_tools? then drive_call_tools(ctx, run, step, error_history)
        in .done?
          response = step.response
          return response if response
          raise Completion::PromptError.prompt_cancelled(error_history, "done step without response")
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
      if history = @chat_history
        run.with_history(history)
      end
      if tc = @tool_choice
        run.with_tool_choice(tc)
      end
      if otn = @output_tool_name
        run.with_output_tool_name(otn)
      elsif @output_schema && @output_mode != OutputMode::Native && @output_mode != OutputMode::Prompted
        # Derive the collision-safe synthetic output tool name so the run can
        # intercept it, matching the name advertised by the request builder.
        tool_names = (@static_tools || [] of Completion::ToolDefinition).map(&.name)
        if tsh = @tool_server_handle
          tool_names += tsh.get_tool_defs(nil).map(&.name)
        end
        run.with_output_tool_name(Crig.pick_output_tool_name(tool_names.to_set))
      end
      run.with_output_validation(@output_schema, 0) if @output_schema
      run
    end

    private def stream_loop(prompt, ch)
      ctx = HookContext.new(is_streaming: true, agent_name: @agent_name)
      run = build_run(prompt)

      loop do
        step = run.next_step
        error_history = run.full_history
        case step.kind
        in .call_model?
          turn = step.turn || 0
          sprompt = step.prompt || raise "Bug: call_model step without prompt"
          shistory = step.history || raise "Bug: call_model step without history"
          ctx.turn = turn

          call_event = StepEvent.completion_call(sprompt.rag_text || "", turn)
          patch = dispatch_completion_call_hook(ctx, call_event, error_history)

          builder = build_completion_request(sprompt, shistory, patch)
          request = builder.build

          # Trace: chat span (matching upstream source.open_chat_span)
          span = open_chat_span(builder, request)

          response = @model.completion(request)
          choice = response.choice

          # Record response on span
          record_response_on_span(span, response)
          span.end_span

          text = choice_text(choice)
          unless text.empty?
            ch.send(StreamTextDelta.new(text, text))
            dispatch_text_delta_hook(ctx, text, text, error_history)
          end

          ct = choice_text(response.choice)
          resp_event = StepEvent.completion_response(sprompt.rag_text || "", response.raw_response.to_s, ct)
          dispatch_hook(ctx, resp_event, error_history)

          exe_tools = builder.tools.map(&.name)
          turn_data = ModelTurn.new(choice: choice, usage: response.usage, allowed_tools: exe_tools)
          outcome = run.model_response(turn_data)
          handle_outcome(run, ctx, outcome)
        in .call_tools?
          calls = step.calls || raise "Bug: call_tools step without calls"
          results = execute_tools(ctx, calls, error_history)
          results.each do |result_item|
            if tr = result_item.tool_result
              ch.send(StreamToolResult.new(tr.id, "tool_result"))
            end
          end
          run.tool_results(results)
          ch.send(StreamToolExecutionCommitted.new(results))
        in .done?
          response = step.response
          ch.send(StreamDone.new(response)) if response
          break
        end
      end
    end

    private def drive_call_model(ctx, run, step, error_history)
      turn = step.turn || 0
      sprompt = step.prompt || raise "Bug: call_model step without prompt"
      shistory = step.history || raise "Bug: call_model step without history"
      ctx.turn = turn

      # 1. Dispatch CompletionCall hook (matching upstream: resolve_completion_call)
      call_event = StepEvent.completion_call(sprompt.rag_text || "", turn)
      patch = dispatch_completion_call_hook(ctx, call_event, error_history)

      # 2. Build request (matching upstream: build_prepared_completion_request)
      builder = build_completion_request(sprompt, shistory, patch)
      request = builder.build

      # Trace: chat span (matching upstream source.open_chat_span)
      span = open_chat_span(builder, request)

      # 3. Call model
      response = @model.completion(request)

      # Record response on span
      record_response_on_span(span, response)
      span.end_span

      # 4. Dispatch CompletionResponse hook
      ct = choice_text(response.choice)
      resp_event = StepEvent.completion_response(sprompt.rag_text || "", response.raw_response.to_s, ct)
      dispatch_hook(ctx, resp_event, error_history)

      # 7. Feed model response to state machine
      exe_tools = request.tools ? request.tools.map(&.name) : [] of String
      turn_data = ModelTurn.new(choice: response.choice, usage: response.usage, allowed_tools: exe_tools)
      outcome = run.model_response(turn_data)
      handle_outcome(run, ctx, outcome)
    end

    private def drive_call_tools(ctx, run, step, error_history)
      calls = step.calls || raise "Bug: call_tools step without calls"
      results = execute_tools(ctx, calls, error_history)
      run.tool_results(results)
    end

    private def build_input_messages_json(messages : Array(Completion::Message)) : String
      JSON.build do |json|
        json.array do
          messages.each do |message|
            json.object do
              json.field "role", message.role.to_s.downcase
              if text = message.rag_text
                json.field "content", text
              end
            end
          end
        end
      end
    end

    private def open_chat_span(builder, request) : Span
      input_json = if @record_content_telemetry
                     build_input_messages_json(request.chat_history.to_a)
                   end
      Span.chat_span(
        "rig",
        request.model || "unknown",
        builder.preamble,
        input_json,
        @record_content_telemetry,
      )
    end

    private def record_response_on_span(span : Span, response) : Nil
      if @record_content_telemetry
        span.record_model_output(build_output_messages_json(response.choice.to_a))
      end
      if response.responds_to?(:raw_response) && (raw = response.raw_response).responds_to?(:get_response_id)
        span.record_response_metadata(raw)
      end
      span.record_token_usage(response.usage) if response.usage.responds_to?(:token_usage)
    end

    private def build_output_messages_json(content : Array(Completion::AssistantContent)) : String
      JSON.build do |json|
        json.array do
          content.each do |item|
            json.object do
              json.field "role", "assistant"
              if text = item.text.try(&.text)
                json.field "content", text
              end
            end
          end
        end
      end
    end

    private def build_completion_request(sprompt, shistory, patch : RequestPatch?) : Completion::Request::CompletionRequestBuilder
      tool_defs = (@static_tools || [] of Completion::ToolDefinition) + begin
        if tsh = @tool_server_handle
          tsh.get_tool_defs(nil)
        else
          [] of Completion::ToolDefinition
        end
      end

      prepared = PreparedCompletionRequest(typeof(@model)).build(
        model: @model,
        prompt: sprompt,
        chat_history: shistory,
        preamble: @preamble,
        static_context: @static_context,
        temperature: @temperature,
        max_tokens: @max_tokens.try(&.to_i64),
        additional_params: @additional_params,
        tool_choice: @tool_choice,
        tool_defs: tool_defs,
        output_schema: @output_schema,
        output_mode: @output_mode,
        committed_output_tool: @output_tool_name,
        patch: patch,
        output_tool_description: @output_tool_description,
      )
      prepared.builder
    end

    private def choice_text(choice : OneOrMany(Completion::AssistantContent)) : String
      choice.to_a.flat_map { |i| i.text.try(&.text) || [""] }.join
    end

    private def dispatch_completion_call_hook(ctx, event, error_history : Array(Completion::Message)) : RequestPatch?
      merged : RequestPatch? = nil
      @hooks.each do |hook|
        action = hook.on_completion_call(ctx, event)
        case action.kind
        in .cont? then next
        in .patch_request?
          if p = action.patch
            merged = merged ? merged.merge(p) : p
          end
        in .stop? then raise Completion::PromptError.prompt_cancelled(error_history, action.reason || "terminated")
        end
      end
      merged
    end

    private def dispatch_hook(ctx, event, error_history : Array(Completion::Message)) : Nil
      @hooks.each do |hook|
        action = hook.on_observation(ctx, event)
        if action.kind.stop?
          raise Completion::PromptError.prompt_cancelled(error_history, action.reason || "terminated")
        end
      end
    end

    private def dispatch_text_delta_hook(ctx, delta : String, aggregated : String, error_history : Array(Completion::Message)) : Nil
      event = StepEvent.text_delta(delta, aggregated)
      @hooks.each do |hook|
        action = hook.on_text_delta(ctx, event)
        if action.kind.stop?
          raise Completion::PromptError.prompt_cancelled(error_history, action.reason || "terminated")
        end
      end
    end

    private def execute_tools(ctx, calls : Array(PendingToolCall), error_history : Array(Completion::Message)) : Array(Completion::UserContent)
      if @concurrency <= 1 || calls.size <= 1
        execute_tools_sequential(ctx, calls, error_history)
      else
        execute_tools_concurrent(ctx, calls, error_history)
      end
    end

    private def execute_tools_sequential(ctx, calls : Array(PendingToolCall), error_history : Array(Completion::Message)) : Array(Completion::UserContent)
      calls.map { |call| execute_single_call(ctx, call, error_history) }
    end

    private def execute_single_call(ctx, call : PendingToolCall, error_history : Array(Completion::Message)) : Completion::UserContent
      tc = call.tool_call
      tool_name = tc.function.name
      args = tc.function.arguments.to_json

      call_event = StepEvent.tool_call(tool_name, tc.call_id, tc.id, args)
      effective_args, skip_reason = dispatch_tool_call_hook(ctx, call_event, error_history)

      if reason = skip_reason
        # Tool was skipped by hook — produce synthetic result without executing
        content = OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text(reason))
        return Completion::UserContent.tool_result(tc.id, content)
      end

      result_text = execute_single_tool(tool_name, effective_args)

      result_event = StepEvent.tool_result(tool_name, tc.call_id, tc.id, args, result_text)
      effective_result = dispatch_tool_result_hook(ctx, result_event, error_history)

      content = Completion::ToolResultContent.from_tool_output(effective_result)
      if cid = tc.call_id
        Completion::UserContent.tool_result_with_call_id(tc.id, cid, content)
      else
        Completion::UserContent.tool_result_with_call_id(tc.id, tc.id, content)
      end
    end

    private def execute_tools_concurrent(ctx, calls : Array(PendingToolCall), error_history : Array(Completion::Message)) : Array(Completion::UserContent)
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
            results[index] = execute_single_call(ctx, call, error_history)
          rescue ex : Completion::PromptError
            first_error.compare_and_set(nil, ex)
            terminating.set(true)
          rescue ex : Exception
            first_error.compare_and_set(nil, Completion::PromptError.prompt_cancelled(error_history, ex.message || "tool error"))
            terminating.set(true)
          end
          sem.receive; wg.done
        end
      end
      wg.wait
      if err = first_error.get
        raise err
      end
      results.compact_map { |result| result }
    end

    private def dispatch_tool_call_hook(ctx, event, error_history : Array(Completion::Message)) : {String, String?}
      effective = event.args || ""
      @hooks.each do |hook|
        action = hook.on_tool_call(ctx, event)
        case action.kind
        in .cont? then next
        in .rewrite?
          if a = action.args
            effective = a.to_json
            # Subsequent hooks observe the rewritten arguments (upstream order).
            event = StepEvent.tool_call(event.tool_name || "", event.tool_call_id, event.internal_call_id || "", effective)
          end
        in .stop? then return {effective, action.reason}
        end
      end
      {effective, nil}
    end

    private def dispatch_tool_result_hook(ctx, event, error_history : Array(Completion::Message)) : String
      effective = event.result || ""
      @hooks.each do |hook|
        action = hook.on_tool_result(ctx, event)
        case action.kind
        in .cont? then next
        in .rewrite?
          if output = action.output
            if text = output.as_text
              effective = text
              # Subsequent hooks observe the rewritten result (upstream order).
              event = StepEvent.tool_result(event.tool_name || "", event.tool_call_id, event.internal_call_id || "", event.args || "", effective)
            end
          end
        in .stop? then raise Completion::PromptError.prompt_cancelled(error_history, action.reason || "terminated")
        end
      end
      effective
    end

    private def execute_single_tool(name : String, args : String) : String
      if tsh = @tool_server_handle
        result = tsh.execute(name, args, @tool_context)
        result.output.render
      else
        "#{name}_result(#{args})"
      end
    rescue ex
      ex.to_s
    end

    private def handle_outcome(run, ctx, outcome : ModelTurnOutcome) : Nil
      case outcome.kind
      in .needs_resolution?
        ctx2 = outcome.context || raise "Bug: needs_resolution without context"
        if @ignore_unhandled_invalid_tool_calls
          run.resolve_invalid_tool_call(InvalidToolCallHookAction.skip("ignored"))
          return
        end
        invalid_event = StepEvent.tool_call(
          ctx2.tool_name, nil, "", ctx2.args || "")
        action = dispatch_invalid_tool_call_hook(ctx, invalid_event, ctx2)
        case action.kind
        in .fail?
          raise Completion::PromptError.unknown_tool_call(
            ctx2.tool_name, ctx2.available_tools, ctx2.allowed_tools, ctx2.chat_history)
        in .retry?
          run.resolve_invalid_tool_call(
            InvalidToolCallHookAction.retry(action.feedback || "try again"))
        in .repair?
          run.resolve_invalid_tool_call(
            InvalidToolCallHookAction.repair(action.tool_name || ctx2.tool_name))
        in .skip?
          run.resolve_invalid_tool_call(
            InvalidToolCallHookAction.skip(action.reason || "skipped"))
        end
      in .turn_retried?, .continue?
      end
    end

    private def dispatch_invalid_tool_call_hook(ctx, event, ctx2) : InvalidToolCallAction
      @hooks.each do |hook|
        action = hook.on_invalid_tool_call(ctx, event)
        case action.kind
        in .fail?   then return action
        in .retry?  then return action
        in .repair? then return action
        in .skip?   then return action
        end
      end
      InvalidToolCallAction.fail
    end
  end
end
