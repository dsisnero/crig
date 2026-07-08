module Crig
  enum OutputMode
    Auto; Tool; Native; Prompted

    def self.default : OutputMode
      Auto
    end
  end

  struct PendingToolCall
    include JSON::Serializable
    getter tool_call : Completion::ToolCall
    getter preresolved_result : Completion::UserContent?
    getter internal_call_id : String?

    def initialize(@tool_call : Completion::ToolCall, @preresolved_result : Completion::UserContent? = nil, @internal_call_id : String? = nil)
    end
  end

  struct ModelTurn
    include JSON::Serializable
    getter message_id : String?
    getter choice : OneOrMany(Completion::AssistantContent)
    getter usage : Completion::Usage
    getter executable_tool_names : Array(String)
    getter allowed_tool_names : Array(String)

    def initialize(@message_id : String? = nil, @choice : OneOrMany(Completion::AssistantContent) = OneOrMany(Completion::AssistantContent).one(Completion::AssistantContent.text("")),
                   @usage : Completion::Usage = Completion::Usage.new, @executable_tool_names : Array(String) = [] of String,
                   @allowed_tool_names : Array(String) = [] of String)
    end

    # Named-argument constructor for ergonomic use
    def self.new(*, message_id : String? = nil, choice : OneOrMany(Completion::AssistantContent)? = nil,
                 usage : Completion::Usage? = nil, executable_tool_names : Array(String)? = nil,
                 allowed_tools : Array(String)? = nil)
      new(
        message_id: message_id,
        choice: choice || OneOrMany(Completion::AssistantContent).one(Completion::AssistantContent.text("")),
        usage: usage || Completion::Usage.new,
        executable_tool_names: executable_tool_names || (allowed_tools || [] of String),
        allowed_tool_names: allowed_tools || (executable_tool_names || [] of String),
      )
    end
  end

  struct AgentRunStep
    enum Kind
      CallModel; CallTools; Done
    end
    getter kind : Kind
    getter prompt : Completion::Message?
    getter history : Array(Completion::Message)?
    getter turn : Int32?
    getter calls : Array(PendingToolCall)?
    getter response : PromptResponse?

    private def initialize(@kind : Kind, @prompt : Completion::Message? = nil, @history : Array(Completion::Message)? = nil,
                           @turn : Int32? = nil, @calls : Array(PendingToolCall)? = nil, @response : PromptResponse? = nil)
    end

    def self.call_model(p : Completion::Message, h : Array(Completion::Message), t : Int32) : self
      new(Kind::CallModel, prompt: p, history: h, turn: t)
    end

    def self.call_tools(c : Array(PendingToolCall)) : self
      new(Kind::CallTools, calls: c)
    end

    def self.done(r : PromptResponse) : self
      new(Kind::Done, response: r)
    end

    def call_model? : Bool
      @kind.call_model?
    end

    def call_tools? : Bool
      @kind.call_tools?
    end

    def done? : Bool
      @kind.done?
    end
  end

  struct ModelTurnOutcome
    enum Kind
      Continue; NeedsResolution; TurnRetried
    end
    getter kind : Kind
    getter response_hook_suppressed : Bool
    getter context : InvalidToolCallContext?

    private def initialize(@kind : Kind, @response_hook_suppressed : Bool = false, @context : InvalidToolCallContext? = nil)
    end

    def self.continue(suppressed : Bool = false) : self
      new(Kind::Continue, response_hook_suppressed: suppressed)
    end

    def self.needs_resolution(ctx : InvalidToolCallContext) : self
      new(Kind::NeedsResolution, context: ctx)
    end

    def self.turn_retried : self
      new(Kind::TurnRetried)
    end
  end

  # Sans-IO state machine
  class AgentRun
    enum State
      PreparingRequest; AwaitingModel; ResolvingToolCalls; AwaitingAdvance; ExecutingTools; Done; Failed
    end

    property max_turns : Int32 = 0
    property max_invalid_tool_call_retries : Int32 = 0
    property tool_choice : Completion::ToolChoice?
    property output_tool_name : String?
    property output_schema : JSON::Any?
    property max_output_retries : Int32 = 0
    @output_retries : Int32 = 0
    property chat_history : Array(Completion::Message)?
    @new_messages : Array(Completion::Message) = [] of Completion::Message
    @current_turn : Int32 = 0
    @usage : Completion::Usage = Completion::Usage.new
    property completion_calls : Array(CompletionCall) = [] of CompletionCall

    @state : State = State::PreparingRequest
    @cc_index : Int32 = 0
    @itc_retries : Int32 = 0

    # Resolving state
    @msg_id : String?
    @items : Array(Completion::AssistantContent) = [] of Completion::AssistantContent
    @orig_choice : OneOrMany(Completion::AssistantContent)?
    @next_idx : Int32 = 0
    @exe_tools : Array(String) = [] of String
    @alw_tools : Array(String) = [] of String
    @skipped : Hash(String, Completion::UserContent) = {} of String => Completion::UserContent
    @recovered : Bool = false
    @any_skipped : Bool = false
    @has_tc : Bool = false

    @pending : Array(PendingToolCall) = [] of PendingToolCall
    @rb_pending : Bool = false
    @st_rec : Bool = false

    # Turn state
    @turn_items : Array(Completion::AssistantContent) = [] of Completion::AssistantContent
    @turn_has_tc : Bool = false
    @done_response : PromptResponse?

    def initialize(prompt : Completion::Message)
      @new_messages = [prompt]
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "max_turns", @max_turns
        json.field "current_turn", @current_turn
        json.field "state", @state.to_s
        json.field "pending" do
          json.array do
            @pending.each do |p|
              json.object do
                tc = p.tool_call
                json.field "id", tc.id
                json.field "name", tc.function.name
                json.field "args", tc.function.arguments.to_json
                if cid = tc.call_id
                  json.field "call_id", cid
                end
              end
            end
          end
        end
      end
    end

    def self.from_json(json : JSON::PullParser) : self
      run = allocate
      run.initialize_from_json(json)
      run
    end

    def self.from_json(string : String) : self
      pull = JSON::PullParser.new(string)
      from_json(pull)
    end

    def initialize_from_json(json : JSON::PullParser) : Nil
      json.read_object do |key|
        case key
        when "max_turns"    then @max_turns = json.read_int.to_i32
        when "current_turn" then @current_turn = json.read_int.to_i32
        when "state"        then @state = State.parse(json.read_string)
        when "pending"
          json.read_array do
            id = ""; name = ""; args_json = "{}"; call_id = nil; preresolved = nil
            json.read_object do |k|
              case k
              when "id"          then id = json.read_string
              when "name"        then name = json.read_string
              when "args"        then args_json = json.read_string
              when "call_id"     then call_id = json.read_string
              when "preresolved" then preresolved = json.read_string
              else                    json.skip
              end
            end
            fn = Completion::ToolFunction.new(name, JSON.parse(args_json))
            tc = Completion::ToolCall.new(id, fn, call_id)
            @pending << PendingToolCall.new(tc, preresolved_result: nil)
          end
        else json.skip
        end
      end
    end

    def to_json : String
      io = IO::Memory.new
      builder = JSON::Builder.new(io)
      builder.start_document
      to_json(builder)
      builder.end_document
      io.to_s
    end

    def with_history(h : Array(Completion::Message)) : self
      @chat_history = h; self
    end

    def max_turns(v : Int32) : self
      @max_turns = v; self
    end

    def max_invalid_tool_call_retries(v : Int32) : self
      @max_invalid_tool_call_retries = v; self
    end

    def with_tool_choice(v : Completion::ToolChoice) : self
      @tool_choice = v; self
    end

    def with_output_tool_name(v : String) : self
      @output_tool_name = v; self
    end

    def with_output_validation(s : JSON::Any?, r : Int32) : self
      @output_schema = s; @max_output_retries = r; self
    end

    def turn : Int32
      @current_turn
    end

    def messages : Array(Completion::Message)
      @new_messages
    end

    def is_done? : Bool
      @state.done?
    end

    def full_history : Array(Completion::Message)
      (@chat_history.try(&.dup) || [] of Completion::Message).tap(&.concat(@new_messages))
    end

    def next_step : AgentRunStep
      case @state
      in .preparing_request?    then prep_request
      in .awaiting_model?       then raise Completion::PromptError.prompt_cancelled(full_history, "next_step while awaiting model")
      in .resolving_tool_calls? then raise Completion::PromptError.prompt_cancelled(full_history, "next_step while resolving tool calls")
      in .awaiting_advance?     then advance
      in .executing_tools?      then AgentRunStep.call_tools(@pending)
      in .done?                 then AgentRunStep.done(@done_response.not_nil!)
      in .failed?               then raise Completion::PromptError.prompt_cancelled(full_history, "run failed")
      end
    end

    private def prep_request
      raise Completion::PromptError.prompt_cancelled(full_history, "no pending prompt") if @new_messages.empty?
      if @current_turn >= @max_turns && @max_turns > 0
        raise Completion::PromptError.max_turns_exceeded(@max_turns, full_history, @new_messages.last)
      end
      p = @new_messages.last
      h = (@chat_history.try(&.dup) || [] of Completion::Message)
      h.concat(@new_messages[0...-1])
      @current_turn += 1; @rb_pending = false; @st_rec = false
      @state = State::AwaitingModel
      AgentRunStep.call_model(p, h, @current_turn)
    end

    def model_response(turn : ModelTurn) : ModelTurnOutcome
      raise Completion::PromptError.prompt_cancelled(full_history, "model_response without pending CallModel") unless @state.awaiting_model?
      raise Completion::PromptError.prompt_cancelled(full_history, "model_response after streamed record") if @st_rec

      cc = CompletionCall.new(@cc_index, turn.usage); @cc_index += 1
      @completion_calls << cc; @usage = @usage + turn.usage
      @items = turn.choice.to_a
      @has_tc = @items.any? { |i| i.tool_call }
      @msg_id = turn.message_id; @orig_choice = turn.choice
      @next_idx = 0; @exe_tools = turn.executable_tool_names; @alw_tools = turn.allowed_tool_names
      @skipped.clear; @recovered = false; @any_skipped = false
      @state = State::ResolvingToolCalls
      advance_resolution
    end

    private def advance_resolution
      while @next_idx < @items.size
        item = @items[@next_idx]
        if tc = item.tool_call
          break unless @alw_tools.includes?(tc.function.name)
        end
        @next_idx += 1
      end
      return finalize_turn if @next_idx >= @items.size

      tc = @items[@next_idx].tool_call.not_nil!
      ctx = InvalidToolCallContext.new(tool_name: tc.function.name, tool_call_id: tc.id,
        args: tc.function.arguments.to_json, available_tools: @exe_tools,
        allowed_tools: @alw_tools, tool_choice: @tool_choice,
        chat_history: diagnostic_history, is_streaming: false)
      ModelTurnOutcome.needs_resolution(ctx)
    end

    private def diagnostic_history
      hist = full_history[0...-1]? || [] of Completion::Message
      if @items.any? && (c = @orig_choice)
        hist + [assistant_msg(@msg_id, c)]
      else
        hist
      end
    end

    private def assistant_msg(id, choice : OneOrMany(Completion::AssistantContent))
      items = choice.to_a.map(&.as(Completion::UserContent | Completion::AssistantContent))
      mixed = OneOrMany(Completion::UserContent | Completion::AssistantContent).many(items)
      Completion::Message.new(Completion::Message::Role::Assistant, mixed, id)
    end

    private def finalize_turn
      if @has_tc && (oname = @output_tool_name)
        otc = @items.find { |i| tc = i.tool_call; tc && tc.function.name == oname }
        if otc && (tc = otc.tool_call)
          output = tc.function.arguments.to_json
          missing = missing_output_fields(tc.function.arguments)
          if !missing.empty? && can_reprompt?
            @new_messages << assistant_msg(@msg_id, @orig_choice.not_nil!)
            @new_messages << Completion::Message.user("Missing field(s): #{missing.join(", ")}. Call `#{oname}` again.")
            return reprompt
          end
          final = @items.reject { |i| i.tool_call }
          final << Completion::AssistantContent.text(output)
          @new_messages << assistant_msg(@msg_id, OneOrMany(Completion::AssistantContent).many(final))
          @done_response = PromptResponse.new(output, @usage)
            .with_messages(@new_messages.dup)
            .with_completion_calls(@completion_calls.dup)
          @state = State::Done
          return ModelTurnOutcome.continue
        end
      end

      if (c = @orig_choice) && !is_empty_choice?(c)
        @new_messages << assistant_msg(@msg_id, c)
      end

      if @has_tc
        @output_retries = 0
        calls = @items.select { |i| i.tool_call }.map { |i|
          t = i.tool_call.not_nil!
          PendingToolCall.new(tool_call: t, preresolved_result: @skipped[t.id]?)
        }
        @pending = calls; @state = State::ExecutingTools
        return ModelTurnOutcome.continue(suppressed: @recovered)
      end

      if (oname = @output_tool_name) && (c = @orig_choice) && !is_empty_choice?(c) && can_reprompt?
        unless text_ok?(choice_text(c))
          @new_messages << Completion::Message.user("Provide answer by calling `#{oname}` tool.")
          return reprompt
        end
      end

      text = @orig_choice ? choice_text(@orig_choice.not_nil!) : ""
      @done_response = PromptResponse.new(text, @usage)
        .with_messages(@new_messages.dup)
        .with_completion_calls(@completion_calls.dup)
      @state = State::Done
      ModelTurnOutcome.continue
    end

    private def choice_text(c) : String
      c.to_a.flat_map { |i| i.text.try(&.text) || [""] }.join("\n")
    end

    private def is_empty_choice?(c) : Bool
      c.to_a.all? { |i| i.text.nil? && i.tool_call.nil? && i.reasoning.nil? }
    end

    private def can_reprompt?
      @output_retries < @max_output_retries && @current_turn <= @max_turns + 1
    end

    private def reprompt
      @output_retries += 1; @state = State::PreparingRequest
      ModelTurnOutcome.turn_retried
    end

    private def missing_output_fields(args : JSON::Any) : Array(String)
      s = @output_schema.try &.as_h?; return [] of String unless s
      req = s["required"]?.try &.as_a?; return [] of String unless req
      obj = args.as_h?
      fields = req.compact_map(&.as_s?)
      fields.reject { |f| obj.try &.has_key?(f) }
    end

    private def text_ok?(text : String) : Bool
      v = JSON.parse(text.strip); missing_output_fields(v).empty?
    rescue
      false
    end

    def resolve_invalid_tool_call(action : InvalidToolCallHookAction) : ModelTurnOutcome
      raise Completion::PromptError.prompt_cancelled(full_history, "no pending") unless @state.resolving_tool_calls?
      tc = @items[@next_idx].tool_call.not_nil!
      raise Completion::PromptError.prompt_cancelled(full_history, "tool call is valid") if @alw_tools.includes?(tc.function.name)

      case action.kind
      in .fail?
        raise Completion::PromptError.unknown_tool_call(tc.function.name, @exe_tools, @alw_tools, diagnostic_history)
      in .retry?
        if @itc_retries >= @max_invalid_tool_call_retries
          raise Completion::PromptError.unknown_tool_call(tc.function.name, @exe_tools, @alw_tools, diagnostic_history)
        end
        @itc_retries += 1
        @new_messages << assistant_msg(@msg_id, @orig_choice.not_nil!)
        @new_messages << Completion::Message.user(action.feedback.not_nil!)
        @state = State::PreparingRequest
        ModelTurnOutcome.turn_retried
      in .repair?
        rn = action.tool_name.not_nil!
        raise Completion::PromptError.unknown_tool_call(rn, @exe_tools, @alw_tools, diagnostic_history) unless @alw_tools.includes?(rn)
        # Replace tool_call with repaired name (ToolCall is a struct so we must create new AssistantContent)
        old_tc = @items[@next_idx].tool_call.not_nil!
        new_fn = Completion::ToolFunction.new(rn, old_tc.function.arguments)
        new_tc = Completion::ToolCall.new(old_tc.id, new_fn, old_tc.call_id, old_tc.signature, old_tc.additional_params)
        @items[@next_idx] = Completion::AssistantContent.new(
          Completion::AssistantContent::Kind::ToolCall, tool_call: new_tc)
        @recovered = true
        advance_resolution
      in .skip?
        raise Completion::PromptError.unknown_tool_call(tc.function.name, @exe_tools, @alw_tools, diagnostic_history) if @tool_choice.try(&.none?)
        reason = action.reason.not_nil!
        content = Completion::UserContent.tool_result(tc.id, OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text(reason)))
        @skipped[tc.id] = content
        @recovered = true; @any_skipped = true; @next_idx += 1
        advance_resolution
      end
    end

    def tool_results(results : Array(Completion::UserContent)) : Nil
      raise Completion::PromptError.prompt_cancelled(full_history, "tool_results without CallTools") unless @state.executing_tools?
      raise Completion::PromptError.prompt_cancelled(full_history, "empty results") if results.empty?
      unanswered = @pending.map(&.tool_call.id)
      results.each do |r|
        tr = r.tool_result
        raise Completion::PromptError.prompt_cancelled(full_history, "not a tool result") unless tr
        idx = unanswered.index(tr.id)
        raise Completion::PromptError.prompt_cancelled(full_history, "unknown/duplicate: #{tr.id}") unless idx
        unanswered.delete_at(idx)
      end
      raise Completion::PromptError.prompt_cancelled(full_history, "unanswered: #{unanswered}") unless unanswered.empty?
      @new_messages << Completion::Message.user(results)
      @state = State::PreparingRequest
    end

    private def advance
      if @turn_has_tc
        calls = @turn_items.select { |i| i.tool_call }.map { |i|
          t = i.tool_call.not_nil!; PendingToolCall.new(tool_call: t, preresolved_result: @skipped[t.id]?)
        }
        @pending = calls; @state = State::ExecutingTools
        AgentRunStep.call_tools(calls)
      else
        text = @turn_items.empty? ? "" : choice_text(OneOrMany(Completion::AssistantContent).many(@turn_items))
        @done_response = PromptResponse.new(text, @usage)
          .with_messages(@new_messages.dup)
          .with_completion_calls(@completion_calls.dup)
        @state = State::Done
        AgentRunStep.done(@done_response.not_nil!)
      end
    end
  end
end
