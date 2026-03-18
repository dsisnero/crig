module Crig
  class PauseControl
    @paused = false

    def self.new : self
      allocate.tap(&.initialize)
    end

    def initialize
    end

    def pause : Nil
      @paused = true
    end

    def resume : Nil
      @paused = false
    end

    # ameba:disable Naming/PredicateName
    def is_paused : Bool
      @paused
    end
    # ameba:enable Naming/PredicateName
  end

  enum ToolCallDeltaContentKind
    Name
    Delta
  end

  struct ToolCallDeltaContent
    getter kind : ToolCallDeltaContentKind
    getter value : String

    def initialize(@kind : ToolCallDeltaContentKind, @value : String)
    end

    def self.name(value : String) : self
      new(ToolCallDeltaContentKind::Name, value)
    end

    def self.delta(value : String) : self
      new(ToolCallDeltaContentKind::Delta, value)
    end
  end

  class RawStreamingToolCall
    getter id : String
    property internal_call_id : String
    property call_id : String?
    getter name : String
    getter arguments : JSON::Any
    property signature : String?
    property additional_params : JSON::Any?

    def initialize(
      @id : String,
      @name : String,
      @arguments : JSON::Any,
      @internal_call_id : String = "",
      @call_id : String? = nil,
      @signature : String? = nil,
      @additional_params : JSON::Any? = nil,
    )
    end

    def self.empty : self
      new("", "", JSON.parse("null"))
    end

    def with_internal_call_id(internal_call_id : String) : self
      @internal_call_id = internal_call_id
      self
    end

    def with_call_id(call_id : String) : self
      @call_id = call_id
      self
    end

    def with_signature(signature : String?) : self
      @signature = signature
      self
    end

    def with_additional_params(additional_params : JSON::Any?) : self
      @additional_params = additional_params
      self
    end

    def to_tool_call : Crig::Completion::ToolCall
      Crig::Completion::ToolCall.new(
        @id,
        Crig::Completion::ToolFunction.new(@name, @arguments),
        @call_id,
        @signature,
        @additional_params,
      )
    end
  end

  struct RawStreamingChoice(R)
    enum Kind
      Message
      ToolCall
      ToolCallDelta
      Reasoning
      ReasoningDelta
      FinalResponse
      MessageId
    end

    getter kind : Kind
    getter message : String?
    getter tool_call : Crig::RawStreamingToolCall?
    getter id : String?
    getter internal_call_id : String?
    getter content : Crig::ToolCallDeltaContent?
    getter reasoning_id : String?
    getter reasoning_content : Crig::Completion::ReasoningContent?
    getter reasoning_delta : String?
    getter final_response : R?
    getter message_id : String?

    def initialize(
      @kind : Kind,
      @message : String? = nil,
      @tool_call : Crig::RawStreamingToolCall? = nil,
      @id : String? = nil,
      @internal_call_id : String? = nil,
      @content : Crig::ToolCallDeltaContent? = nil,
      @reasoning_id : String? = nil,
      @reasoning_content : Crig::Completion::ReasoningContent? = nil,
      @reasoning_delta : String? = nil,
      @final_response : R? = nil,
      @message_id : String? = nil,
    )
    end

    def self.message(text : String) : self
      new(Kind::Message, message: text)
    end

    def self.tool_call(tool_call : Crig::RawStreamingToolCall) : self
      new(Kind::ToolCall, tool_call: tool_call)
    end

    def self.tool_call_delta(id : String, internal_call_id : String, content : Crig::ToolCallDeltaContent) : self
      new(Kind::ToolCallDelta, id: id, internal_call_id: internal_call_id, content: content)
    end

    def self.reasoning(id : String?, content : Crig::Completion::ReasoningContent) : self
      new(Kind::Reasoning, reasoning_id: id, reasoning_content: content)
    end

    def self.reasoning_delta(id : String?, reasoning : String) : self
      new(Kind::ReasoningDelta, reasoning_id: id, reasoning_delta: reasoning)
    end

    def self.final_response(response : R) : self
      new(Kind::FinalResponse, final_response: response)
    end

    def self.message_id(id : String) : self
      new(Kind::MessageId, message_id: id)
    end
  end

  struct StreamedAssistantContent(R)
    enum Kind
      Text
      ToolCall
      ToolCallDelta
      Reasoning
      ReasoningDelta
      Final
    end

    getter kind : Kind
    getter text : Crig::Completion::Text?
    getter tool_call : Crig::Completion::ToolCall?
    getter internal_call_id : String?
    getter id : String?
    getter content : Crig::ToolCallDeltaContent?
    getter reasoning : Crig::Completion::Reasoning?
    getter reasoning_delta : String?
    getter final : R?

    def initialize(
      @kind : Kind,
      @text : Crig::Completion::Text? = nil,
      @tool_call : Crig::Completion::ToolCall? = nil,
      @internal_call_id : String? = nil,
      @id : String? = nil,
      @content : Crig::ToolCallDeltaContent? = nil,
      @reasoning : Crig::Completion::Reasoning? = nil,
      @reasoning_delta : String? = nil,
      @final : R? = nil,
    )
    end

    def self.text(text : String) : self
      new(Kind::Text, Crig::Completion::Text.new(text))
    end

    def self.tool_call(tool_call : Crig::Completion::ToolCall, internal_call_id : String) : self
      new(Kind::ToolCall, nil, tool_call, internal_call_id, nil, nil, nil, nil, nil)
    end

    def self.tool_call_delta(id : String, internal_call_id : String, content : Crig::ToolCallDeltaContent) : self
      new(Kind::ToolCallDelta, nil, nil, internal_call_id, id, content)
    end

    def self.reasoning(reasoning : Crig::Completion::Reasoning) : self
      new(Kind::Reasoning, nil, nil, nil, nil, nil, reasoning)
    end

    def self.reasoning_delta(id : String?, reasoning : String) : self
      new(Kind::ReasoningDelta, nil, nil, nil, id, nil, nil, reasoning)
    end

    def self.final_response(res : R) : self
      new(Kind::Final, nil, nil, nil, nil, nil, nil, nil, res)
    end
  end

  struct StreamedUserContent
    enum Kind
      ToolResult
    end

    getter kind : Kind
    getter tool_result : Crig::Completion::ToolResult?
    getter internal_call_id : String?

    def initialize(
      @kind : Kind,
      @tool_result : Crig::Completion::ToolResult? = nil,
      @internal_call_id : String? = nil,
    )
    end

    def self.tool_result(tool_result : Crig::Completion::ToolResult, internal_call_id : String) : self
      new(Kind::ToolResult, tool_result: tool_result, internal_call_id: internal_call_id)
    end
  end

  struct StreamingResult(R)
    getter items : Array(Crig::RawStreamingChoice(R))

    def initialize(@items : Array(Crig::RawStreamingChoice(R)))
    end
  end

  module StreamingPrompt(M, R)
    abstract def stream_prompt(prompt : Crig::Completion::Message | String)
  end

  module StreamingChat(M, R)
    abstract def stream_chat(prompt : Crig::Completion::Message | String, chat_history : Array(Crig::Completion::Message))
  end

  module StreamingCompletion(M)
    abstract def stream_completion(prompt : Crig::Completion::Message | String, chat_history : Array(Crig::Completion::Message))
  end

  struct StreamingCompletionResponse(R)
    getter chunks : Array(String)
    getter response : R?
    getter pause_control : Crig::PauseControl
    getter choice : Crig::OneOrMany(Crig::Completion::AssistantContent)
    getter message_id : String?
    getter? final_response_yielded : Bool

    def initialize(
      @chunks : Array(String),
      @response : R? = nil,
      @pause_control : Crig::PauseControl = Crig::PauseControl.new,
      @choice : Crig::OneOrMany(Crig::Completion::AssistantContent) = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("")),
      @message_id : String? = nil,
      @raw_choices : Array(Crig::RawStreamingChoice(R))? = nil,
      @raw_index : Int32 = 0,
      @assistant_items : Array(Crig::Completion::AssistantContent) = [] of Crig::Completion::AssistantContent,
      @text_item_index : Int32? = nil,
      @reasoning_item_index : Int32? = nil,
      @cancelled : Bool = false,
      @final_response_yielded : Bool = false,
    )
    end

    def self.stream(chunks : Enumerable(String), response : R? = nil) : self
      items = chunks.to_a
      choice = if items.empty?
                 Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(""))
               else
                 Crig::OneOrMany(Crig::Completion::AssistantContent).many(
                   items.map { |chunk| Crig::Completion::AssistantContent.text(chunk).as(Crig::Completion::AssistantContent) }
                 )
               end
      new(items, response, choice: choice)
    end

    def self.stream_raw_choices(raw_choices : Enumerable(Crig::RawStreamingChoice(R))) : self
      new(
        [] of String,
        nil,
        choice: Crig::OneOrMany(Crig::Completion::AssistantContent).one(
          Crig::Completion::AssistantContent.text("")
        ),
        raw_choices: raw_choices.to_a,
        assistant_items: [] of Crig::Completion::AssistantContent,
      )
    end

    def self.from_raw_choices(raw_choices : Enumerable(Crig::RawStreamingChoice(R))) : self
      response = stream_raw_choices(raw_choices)
      while response.next_item
      end
      response
    end

    private def append_text_chunk(
      text : String,
    ) : Int32
      if index = @text_item_index
        if item = @assistant_items[index]?
          if item.kind.text?
            if existing = item.text
              @assistant_items[index] = Crig::Completion::AssistantContent.text(existing.text + text)
              return index
            end
          end
        end
      end

      @assistant_items << Crig::Completion::AssistantContent.text(text)
      @assistant_items.size - 1
    end

    private def append_reasoning_chunk(
      id : String?,
      text : String,
    ) : Int32
      if index = @reasoning_item_index
        if item = @assistant_items[index]?
          if item.kind.reasoning?
            if existing = item.reasoning
              content = existing.content.dup
              if last = content.last?
                if last.kind.text?
                  content[-1] = Crig::Completion::ReasoningContent.text(
                    (last.text || "") + text,
                    last.signature,
                  )
                  @assistant_items[index] = Crig::Completion::AssistantContent.new(
                    Crig::Completion::AssistantContent::Kind::Reasoning,
                    reasoning: Crig::Completion::Reasoning.new(content, existing.id),
                  )
                  return index
                end
              end
            end
          end
        end
      end

      @assistant_items << Crig::Completion::AssistantContent.new(
        Crig::Completion::AssistantContent::Kind::Reasoning,
        reasoning: Crig::Completion::Reasoning.new(
          [Crig::Completion::ReasoningContent.text(text)],
          id,
        ),
      )
      @assistant_items.size - 1
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def next_item : Crig::StreamedAssistantContent(R)?
      return if @cancelled
      return if is_paused

      raw_choices = @raw_choices
      unless raw_choices
        finalize_choice
        return
      end

      while choice = raw_choices[@raw_index]?
        @raw_index += 1

        case choice.kind
        in .message?
          if text = choice.message
            @reasoning_item_index = nil
            @chunks << text
            @text_item_index = append_text_chunk(text)
            return Crig::StreamedAssistantContent(R).text(text)
          end
        in .tool_call_delta?
          if id = choice.id
            if internal_call_id = choice.internal_call_id
              if content = choice.content
                return Crig::StreamedAssistantContent(R).tool_call_delta(id, internal_call_id, content)
              end
            end
          end
        in .reasoning?
          if content = choice.reasoning_content
            reasoning = Crig::Completion::Reasoning.new([content], choice.reasoning_id)
            @text_item_index = nil
            @reasoning_item_index = nil
            @assistant_items << Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::Reasoning,
              reasoning: reasoning,
            )
            return Crig::StreamedAssistantContent(R).reasoning(reasoning)
          end
        in .reasoning_delta?
          if reasoning = choice.reasoning_delta
            @text_item_index = nil
            @reasoning_item_index = append_reasoning_chunk(choice.reasoning_id, reasoning)
            return Crig::StreamedAssistantContent(R).reasoning_delta(choice.reasoning_id, reasoning)
          end
        in .tool_call?
          if raw_tool_call = choice.tool_call
            internal_call_id = raw_tool_call.internal_call_id
            tool_call = raw_tool_call.to_tool_call
            @text_item_index = nil
            @reasoning_item_index = nil
            @assistant_items << if call_id = tool_call.call_id
              Crig::Completion::AssistantContent.tool_call_with_call_id(
                tool_call.id,
                call_id,
                tool_call.function.name,
                tool_call.function.arguments,
              )
            else
              Crig::Completion::AssistantContent.tool_call(
                tool_call.id,
                tool_call.function.name,
                tool_call.function.arguments,
              )
            end
            return Crig::StreamedAssistantContent(R).tool_call(tool_call, internal_call_id)
          end
        in .final_response?
          if value = choice.final_response
            unless @final_response_yielded
              @response = value
              @final_response_yielded = true
              return Crig::StreamedAssistantContent(R).final_response(value)
            end
          end
        in .message_id?
          @message_id = choice.message_id
        end
      end

      finalize_choice
      nil
    end

    # ameba:enable Metrics/CyclomaticComplexity

    private def finalize_choice : Nil
      return unless @raw_choices

      if @assistant_items.empty?
        @assistant_items << Crig::Completion::AssistantContent.text("")
      end
      @choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(@assistant_items)
      @raw_choices = nil
    end

    def cancel : Nil
      @cancelled = true
      finalize_choice
    end

    def pause : Nil
      @pause_control.pause
    end

    def resume : Nil
      @pause_control.resume
    end

    # ameba:disable Naming/PredicateName
    def is_paused : Bool
      @pause_control.is_paused
    end
    # ameba:enable Naming/PredicateName
  end
end
