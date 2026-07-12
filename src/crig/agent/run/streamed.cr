module Crig
  enum StreamedTurnEventKind
    EmitIngested
    EmitToolCallDelta
    InvalidToolCall
    Completed
  end

  struct StreamedTurnEvent
    getter kind : StreamedTurnEventKind
    getter invalid_tool_call : StreamedInvalidToolCall?
    getter usage : Completion::Usage?

    def initialize(@kind : StreamedTurnEventKind, @invalid_tool_call : StreamedInvalidToolCall? = nil, @usage : Completion::Usage? = nil)
    end

    def self.emit_ingested : self
      new(StreamedTurnEventKind::EmitIngested)
    end

    def self.invalid_tool_call(call : StreamedInvalidToolCall) : self
      new(StreamedTurnEventKind::InvalidToolCall, invalid_tool_call: call)
    end

    def self.completed(usage : Completion::Usage? = nil) : self
      new(StreamedTurnEventKind::Completed, usage: usage)
    end
  end

  enum StreamedResolution
    Repaired
    TurnAbandoned
  end

  # One invalid tool call surfaced mid-stream, awaiting resolution.
  struct StreamedInvalidToolCall
    getter tool_call : Completion::ToolCall
    getter internal_call_id : String
    getter args : String?
    getter executable_tool_names : Set(String)
    getter allowed_tool_names : Set(String)

    def initialize(
      @tool_call : Completion::ToolCall,
      @internal_call_id : String,
      @args : String? = nil,
      @executable_tool_names : Set(String) = Set(String).new,
      @allowed_tool_names : Set(String) = Set(String).new,
    )
    end
  end

  # Snapshot of a streamed turn at the moment an invalid tool call appeared.
  struct PartialStreamedTurn
    getter message_id : String?
    getter text : String?
    getter reasoning : Array(Completion::Reasoning)
    getter pending_tool_calls : Array(Completion::ToolCall)

    def initialize(
      @message_id : String? = nil,
      @text : String? = nil,
      @reasoning : Array(Completion::Reasoning) = [] of Completion::Reasoning,
      @pending_tool_calls : Array(Completion::ToolCall) = [] of Completion::ToolCall,
    )
    end
  end

  # The assembled streamed turn, fed to AgentRun#streamed_turn.
  struct StreamedTurn
    getter message_id : String?
    getter choice : OneOrMany(Completion::AssistantContent)
    getter executable_tool_names : Set(String)
    getter allowed_tool_names : Set(String)
    getter internal_call_ids : Array(Tuple(String, String))

    def initialize(
      @message_id : String? = nil,
      @choice : OneOrMany(Completion::AssistantContent) = OneOrMany(Completion::AssistantContent).one(Completion::AssistantContent.text("")),
      @executable_tool_names : Set(String) = Set(String).new,
      @allowed_tool_names : Set(String) = Set(String).new,
      @internal_call_ids : Array(Tuple(String, String)) = [] of Tuple(String, String),
    )
    end
  end

  struct ToolCallDeltaState
    property name_validated : Bool
    property buffered_arguments : Array(String)

    def initialize
      @name_validated = false
      @buffered_arguments = [] of String
    end
  end

  enum PendingInvalidKind
    FullCall
    NameDelta
  end

  struct PendingInvalid
    getter kind : PendingInvalidKind
    getter tool_call : Completion::ToolCall?
    getter internal_call_id : String

    def initialize(@kind : PendingInvalidKind, @tool_call : Completion::ToolCall? = nil, @internal_call_id : String = "")
    end
  end

  # Sans-IO accumulator that assembles one streamed model turn.
  class StreamedTurnAssembler
    getter executable_tool_names : Set(String)
    getter allowed_tool_names : Set(String)
    getter text : String
    property saw_text : Bool
    getter accumulated_reasoning : Array(Completion::Reasoning)
    getter pending_reasoning_delta_text : String
    getter pending_reasoning_delta_id : String?
    getter pending_tool_calls : Array(Tuple(Completion::ToolCall, String))
    getter pending_invalid : PendingInvalid?

    def initialize(@executable_tool_names : Set(String), @allowed_tool_names : Set(String))
      @text = ""
      @saw_text = false
      @accumulated_reasoning = [] of Completion::Reasoning
      @pending_reasoning_delta_text = ""
      @pending_reasoning_delta_id = nil
      @pending_tool_calls = [] of Tuple(Completion::ToolCall, String)
      @pending_invalid = nil
    end

    def aggregated_text : String
      @text
    end

    def ingest(item : StreamedAssistantContent(FinalResponse)) : Array(StreamedTurnEvent)
      case item.kind
      in .text?
        if !@saw_text
          @text = ""
          @saw_text = true
        end
        @text += item.message || ""
        [StreamedTurnEvent.emit_ingested]
      in .reasoning?
        if r = item.reasoning
          Crig.merge_reasoning_blocks(@accumulated_reasoning, r)
        end
        [StreamedTurnEvent.emit_ingested]
      in .reasoning_delta?
        @pending_reasoning_delta_text += item.reasoning_delta || ""
        if @pending_reasoning_delta_id.nil?
          @pending_reasoning_delta_id = item.reasoning.try(&.id)
        end
        [StreamedTurnEvent.emit_ingested]
      in .tool_call?
        tc = item.tool_call
        icid = item.internal_call_id || ""
        if tc && !@allowed_tool_names.includes?(tc.function.name)
          invalid = StreamedInvalidToolCall.new(
            tool_call: tc,
            internal_call_id: icid,
            args: tc.function.arguments.to_json,
            executable_tool_names: @executable_tool_names,
            allowed_tool_names: @allowed_tool_names,
          )
          @pending_invalid = PendingInvalid.new(PendingInvalidKind::FullCall, tc, icid)
          [StreamedTurnEvent.invalid_tool_call(invalid)]
        elsif tc
          @pending_tool_calls << {tc, icid}
          [] of StreamedTurnEvent
        else
          [] of StreamedTurnEvent
        end
      in .tool_call_delta?
        [] of StreamedTurnEvent
      in .final?
        [StreamedTurnEvent.completed]
      end
    end

    def finish(message_id : String?, final_choice : OneOrMany(Completion::AssistantContent)) : StreamedTurn
      internal_call_ids = @pending_tool_calls.map { |tc, icid| {tc.id, icid} }

      if @accumulated_reasoning.empty? && !@pending_reasoning_delta_text.empty?
        assembled = Completion::Reasoning.new(@pending_reasoning_delta_text)
        if id = @pending_reasoning_delta_id
          assembled = assembled.with_id(id)
        end
        @accumulated_reasoning << assembled
      end

      choice = if !@pending_tool_calls.empty? || !@accumulated_reasoning.empty?
                 text_items = Crig.assistant_text_items_from_choice(final_choice)
                 tool_items = @pending_tool_calls.map { |tc, _| Completion::AssistantContent.tool_call(tc.id, tc.function.name, tc.function.arguments) }
                 ordered = Crig.ordered_streaming_assistant_content(@accumulated_reasoning, text_items, tool_items)
                 ordered || final_choice
               else
                 final_choice
               end

      StreamedTurn.new(
        message_id: message_id,
        choice: choice,
        executable_tool_names: @executable_tool_names,
        allowed_tool_names: @allowed_tool_names,
        internal_call_ids: internal_call_ids,
      )
    end
  end
end

module Crig
  def self.merge_reasoning_blocks(accumulated : Array(Completion::Reasoning), incoming : Completion::Reasoning)
    existing = accumulated.reverse_each.find { |r| r.id == incoming.id && r.id && incoming.id }
    if existing
      existing.not_nil!.content.concat(incoming.content)
    else
      accumulated << incoming
    end
  end

  def self.ordered_streaming_assistant_content(
    reasoning_items : Array(Completion::Reasoning),
    text_items : Array(Completion::AssistantContent),
    trailing_items : Array(Completion::AssistantContent),
  ) : OneOrMany(Completion::AssistantContent)?
    content_items = [] of Completion::AssistantContent
    reasoning_items.each { |r| content_items << Completion::AssistantContent.reasoning(r.display_text) }
    content_items.concat(text_items)
    content_items.concat(trailing_items)
    OneOrMany(Completion::AssistantContent).many(content_items)
  end

  def self.assistant_text_items_from_choice(choice : OneOrMany(Completion::AssistantContent)) : Array(Completion::AssistantContent)
    choice.to_a.select { |c| c.kind.text? && c.text.try(&.text) != "" }
  end
end
