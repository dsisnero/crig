require "json"

module Crig
  struct RunId
    getter value : String

    def self.generate : self
      new(Crig.generate_id)
    end

    private def initialize(@value : String)
    end

    def as_str : String
      @value
    end

    def to_s(io : IO) : Nil
      io << @value
    end
  end

  class Scratchpad
    @inner : Tool::ToolContext = Tool::ToolContext.new
    @mutex : Mutex = Mutex.new(:reentrant)

    def initialize(@shared : Scratchpad? = nil)
      if shared
        @inner = shared.@inner
        @mutex = shared.@mutex
      end
    end

    def insert(val : T) : T? forall T
      @mutex.synchronize { @inner.insert(val) }
    end

    def get(type : T.class) : T? forall T
      @mutex.synchronize { @inner.get(T) }
    end

    def contains?(type : T.class) : Bool forall T
      @mutex.synchronize { @inner.contains?(T) }
    end

    def remove(type : T.class) : T? forall T
      @mutex.synchronize { @inner.remove(T) }
    end

    def update(type : T.class, initial : T? = nil, & : T -> _) : T forall T
      @mutex.synchronize do
        val = @inner.get(T)
        unless val
          val = initial || begin
            T.from_json("{}")
          rescue JSON::SerializableError
            raise "Scratchpad#update: no stored value for #{T} and from_json({}) failed. Provide an initial value via .insert or pass initial: to update."
          end
        end
        yield val
        @inner.insert(val)
        val
      end
    end
  end

  struct HookContext
    getter run_id : RunId
    property turn : Int32 = 0
    getter? is_streaming : Bool
    getter agent_name : String?
    getter scratchpad : Scratchpad

    def initialize(@is_streaming : Bool, @agent_name : String? = nil, scratchpad : Scratchpad? = nil)
      @run_id = RunId.generate
      @turn = 0
      @scratchpad = scratchpad || Scratchpad.new
    end

    def turn=(value : Int32) : Nil
      @turn = value
    end
  end

  struct RequestPatch
    property preamble : String?
    property temperature : Float64?
    property max_tokens : UInt64?
    property tool_choice : Completion::ToolChoice?
    property active_tools : Array(String)?
    property additional_params : JSON::Any?
    property extra_context : Array(Completion::Document)
    property history : Array(Completion::Message)?

    def initialize(
      @preamble : String? = nil,
      @temperature : Float64? = nil,
      @max_tokens : UInt64? = nil,
      @tool_choice : Completion::ToolChoice? = nil,
      @active_tools : Array(String)? = nil,
      @additional_params : JSON::Any? = nil,
      @extra_context : Array(Completion::Document) = [] of Completion::Document,
      @history : Array(Completion::Message)? = nil,
    )
    end

    def preamble(value : String) : self
      @preamble = value
      self
    end

    def temperature(value : Float64) : self
      @temperature = value
      self
    end

    def max_tokens(value : UInt64) : self
      @max_tokens = value
      self
    end

    def tool_choice(value : Completion::ToolChoice) : self
      @tool_choice = value
      self
    end

    def active_tools(names : Array(String)) : self
      @active_tools = names
      self
    end

    def additional_params(value : Hash(String, JSON::Any)) : self
      @additional_params = JSON::Any.new(value)
      self
    end

    def extra_context(docs : Array(Completion::Document)) : self
      @extra_context.concat(docs)
      self
    end

    def context(doc : Completion::Document) : self
      @extra_context << doc
      self
    end

    def history(messages : Array(Completion::Message)) : self
      @history = messages
      self
    end

    def empty? : Bool
      @preamble.nil? && @temperature.nil? && @max_tokens.nil? &&
        @tool_choice.nil? && @active_tools.nil? && @additional_params.nil? &&
        @extra_context.empty? && @history.nil?
    end

    def merge(later : RequestPatch) : RequestPatch
      ec = @extra_context + later.@extra_context
      ap = merge_params(@additional_params, later.@additional_params)
      pmb = merge_last_wins(@preamble, later.@preamble)
      tmp = merge_last_wins(@temperature, later.@temperature)
      mt = merge_last_wins(@max_tokens, later.@max_tokens)
      tc = merge_last_wins(@tool_choice, later.@tool_choice)
      hist = merge_last_wins(@history, later.@history)
      at = merge_active_tools(@active_tools, later.@active_tools)

      RequestPatch.new(
        preamble: pmb,
        temperature: tmp,
        max_tokens: mt,
        tool_choice: tc,
        active_tools: at,
        additional_params: ap,
        extra_context: ec,
        history: hist,
      )
    end

    private def merge_last_wins(earlier, later)
      later || earlier
    end

    private def merge_active_tools(earlier : Array(String)?, later : Array(String)?)
      case {earlier, later}
      when {Array(String), Array(String)}
        e = earlier.as(Array(String))
        l_set = later.as(Array(String)).to_set
        e.select { |name| l_set.includes?(name) }
      else
        earlier || later
      end
    end

    private def merge_params(earlier : JSON::Any?, later : JSON::Any?)
      case {earlier, later}
      when {JSON::Any, JSON::Any}
        e = earlier.as(JSON::Any)
        l = later.as(JSON::Any)
        if e.as_h? && l.as_h?
          merged = e.as_h.dup
          l.as_h.each { |k, v| merged[k] = v }
          JSON::Any.new(merged)
        else
          l
        end
      else
        later || earlier
      end
    end
  end

  # -- Event-specific action types (upstream v0.41.0) --

  struct CompletionCallAction
    enum Kind
      Cont; PatchRequest; Stop
    end

    getter kind : Kind
    getter patch : RequestPatch?
    getter reason : String?

    def initialize(@kind : Kind, @patch : RequestPatch? = nil, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Cont)
    end

    def self.patch_request(patch : RequestPatch) : self
      new(Kind::PatchRequest, patch: patch)
    end

    def self.stop(reason : String) : self
      new(Kind::Stop, reason: reason)
    end
  end

  struct ToolCallAction
    enum Kind
      Cont; Rewrite; Stop
    end

    getter kind : Kind
    getter args : JSON::Any?
    getter reason : String?

    def initialize(@kind : Kind, @args : JSON::Any? = nil, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Cont)
    end

    def self.rewrite(args : JSON::Any) : self
      new(Kind::Rewrite, args: args)
    end

    def self.stop(reason : String) : self
      new(Kind::Stop, reason: reason)
    end
  end

  struct ToolResultAction
    enum Kind
      Cont; Rewrite; Stop
    end

    getter kind : Kind
    getter output : Tool::ToolOutput?
    getter reason : String?

    def initialize(@kind : Kind, @output : Tool::ToolOutput? = nil, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Cont)
    end

    def self.rewrite(output : Tool::ToolOutput) : self
      new(Kind::Rewrite, output: output)
    end

    def self.stop(reason : String) : self
      new(Kind::Stop, reason: reason)
    end
  end

  struct InvalidToolCallAction
    enum Kind
      Fail; Retry; Repair; Skip
    end

    getter kind : Kind
    getter feedback : String?
    getter tool_name : String?
    getter reason : String?

    def initialize(@kind : Kind, @feedback : String? = nil, @tool_name : String? = nil, @reason : String? = nil)
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

  struct ObservationAction
    enum Kind
      Cont; Stop
    end

    getter kind : Kind
    getter reason : String?

    def initialize(@kind : Kind, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Cont)
    end

    def self.stop(reason : String) : self
      new(Kind::Stop, reason: reason)
    end
  end

  struct ModelTurnAction
    enum Kind
      Cont; Retry; Stop
    end

    getter kind : Kind
    getter feedback : String?
    getter reason : String?

    def initialize(@kind : Kind, @feedback : String? = nil, @reason : String? = nil)
    end

    def self.cont : self
      new(Kind::Cont)
    end

    def self.retry(feedback : String) : self
      new(Kind::Retry, feedback: feedback)
    end

    def self.stop(reason : String) : self
      new(Kind::Stop, reason: reason)
    end
  end

  # -- Legacy Flow struct (deprecated) --

  struct Flow
    enum Kind
      Continue
      Terminate
      Skip
      RewriteArgs
      RewriteResult
      PatchRequest
      Fail
      Retry
      Repair
    end

    getter kind : Kind
    getter reason : String?
    getter feedback : String?
    getter tool_name : String?
    getter args : JSON::Any?
    getter result : String?
    getter patch : RequestPatch?

    private def initialize(@kind : Kind, @reason : String? = nil, @feedback : String? = nil,
                           @tool_name : String? = nil, @args : JSON::Any? = nil,
                           @result : String? = nil, @patch : RequestPatch? = nil)
    end

    def self.cont : self
      new(Kind::Continue)
    end

    def self.terminate(reason : String) : self
      new(Kind::Terminate, reason: reason)
    end

    def self.skip(reason : String) : self
      new(Kind::Skip, reason: reason)
    end

    def self.rewrite_args(args : JSON::Any) : self
      new(Kind::RewriteArgs, args: args)
    end

    def self.rewrite_result(result : String) : self
      new(Kind::RewriteResult, result: result)
    end

    def self.patch_request(patch : RequestPatch) : self
      new(Kind::PatchRequest, patch: patch)
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

    # Allow comparison of equality for simple flows
    def ==(other : Flow) : Bool
      @kind == other.@kind
    end
  end

  enum StepEventKind
    CompletionCall
    CompletionResponse
    ModelTurnFinished
    InvalidToolCall
    ToolCall
    ToolResult
    TextDelta
    ToolCallDelta
    StreamResponseFinish
  end

  module AgentHook
    # Legacy: single event dispatch (deprecated — override event-specific methods instead).
    abstract def on_event(ctx : HookContext, event : StepEvent) : Flow

    # Event-specific hooks (upstream v0.41.0+).
    # Default implementations delegate to on_event for backward compatibility.
    def on_completion_call(ctx : HookContext, event : StepEvent) : CompletionCallAction
      flow = on_event(ctx, event)
      if flow.kind.continue?
        CompletionCallAction.cont
      elsif flow.kind.patch_request?
        CompletionCallAction.patch_request(flow.patch || RequestPatch.new)
      elsif flow.kind.terminate?
        CompletionCallAction.stop(flow.reason || "terminated")
      else
        CompletionCallAction.cont
      end
    end

    def on_tool_call(ctx : HookContext, event : StepEvent) : ToolCallAction
      flow = on_event(ctx, event)
      if flow.kind.continue?
        ToolCallAction.cont
      elsif flow.kind.rewrite_args?
        ToolCallAction.rewrite(flow.args || JSON.parse(%({})))
      elsif flow.kind.skip? || flow.kind.terminate?
        ToolCallAction.stop(flow.reason || "skipped")
      else
        ToolCallAction.cont
      end
    end

    def on_tool_result(ctx : HookContext, event : StepEvent) : ToolResultAction
      flow = on_event(ctx, event)
      if flow.kind.continue?
        ToolResultAction.cont
      elsif flow.kind.rewrite_result?
        ToolResultAction.rewrite(Tool::ToolOutput.text(flow.result || ""))
      elsif flow.kind.skip? || flow.kind.terminate?
        ToolResultAction.stop(flow.reason || "skipped")
      else
        ToolResultAction.cont
      end
    end

    def on_invalid_tool_call(ctx : HookContext, event : StepEvent) : InvalidToolCallAction
      flow = on_event(ctx, event)
      if flow.kind.fail? || flow.kind.continue?
        InvalidToolCallAction.fail
      elsif flow.kind.retry?
        InvalidToolCallAction.retry(flow.feedback || "try again")
      elsif flow.kind.repair?
        InvalidToolCallAction.repair(flow.tool_name || event.tool_name || "")
      elsif flow.kind.skip?
        InvalidToolCallAction.skip(flow.reason || "skipped")
      else
        InvalidToolCallAction.fail
      end
    end

    def on_observation(ctx : HookContext, event : StepEvent) : ObservationAction
      flow = on_event(ctx, event)
      if flow.kind.continue?
        ObservationAction.cont
      elsif flow.kind.terminate?
        ObservationAction.stop(flow.reason || "terminated")
      else
        ObservationAction.cont
      end
    end
  end

  struct StepEvent
    enum Kind
      CompletionCall
      CompletionResponse
      ModelTurnFinished
      InvalidToolCall
      ToolCall
      ToolResult
      TextDelta
      ToolCallDelta
      StreamResponseFinish
    end

    getter kind : Kind
    getter prompt_text : String?
    getter tool_name : String?
    getter tool_call_id : String?
    getter internal_call_id : String?
    getter args : String?
    getter result : String?
    getter delta : String?
    getter aggregated : String?
    getter turn : Int32?
    getter raw_response : String?
    getter choice_text : String?

    private def initialize(
      @kind : Kind,
      @prompt_text : String? = nil,
      @tool_name : String? = nil,
      @tool_call_id : String? = nil,
      @internal_call_id : String? = nil,
      @args : String? = nil,
      @result : String? = nil,
      @delta : String? = nil,
      @aggregated : String? = nil,
      @turn : Int32? = nil,
      @raw_response : String? = nil,
      @choice_text : String? = nil,
    )
    end

    def self.completion_call(prompt_text : String, turn : Int32) : self
      new(Kind::CompletionCall, prompt_text: prompt_text, turn: turn)
    end

    def self.completion_response(prompt_text : String, raw_response : String, choice_text : String = "") : self
      new(Kind::CompletionResponse, prompt_text: prompt_text, raw_response: raw_response, choice_text: choice_text)
    end

    def self.tool_call(tool_name : String, tool_call_id : String?, internal_call_id : String, args : String) : self
      new(Kind::ToolCall, tool_name: tool_name, tool_call_id: tool_call_id, internal_call_id: internal_call_id, args: args)
    end

    def self.tool_result(tool_name : String, tool_call_id : String?, internal_call_id : String, args : String, result : String) : self
      new(Kind::ToolResult, tool_name: tool_name, tool_call_id: tool_call_id, internal_call_id: internal_call_id, args: args, result: result)
    end

    def completion_call? : Bool
      @kind.completion_call?
    end

    def tool_call? : Bool
      @kind.tool_call?
    end

    def tool_result? : Bool
      @kind.tool_result?
    end
  end
end
