require "json"
require "random/secure"

module Crig
  struct MockResponse
    include Crig::Completion::GetTokenUsage

    getter token_count : Int64

    def initialize(@token_count : Int64)
    end

    def token_usage : Crig::Completion::Usage?
      Crig::Completion::Usage.new(total_tokens: @token_count)
    end
  end

  struct PauseControl
    # ameba:disable Naming/QueryBoolMethods
    property paused : Bool

    # ameba:enable Naming/QueryBoolMethods

    def initialize(@paused : Bool = false)
    end

    def self.new : self
      allocate.tap(&.initialize)
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

  struct ToolCallDeltaContent
    enum Kind
      Name
      Delta
    end

    getter kind : Kind
    getter value : String

    def initialize(@kind : Kind, @value : String)
    end

    def self.name(value : String) : self
      new(Kind::Name, value)
    end

    def self.delta(value : String) : self
      new(Kind::Delta, value)
    end
  end

  struct RawStreamingToolCall
    property id : String
    property internal_call_id : String
    property call_id : String?
    property name : String
    property arguments : JSON::Any
    getter signature : String?
    getter additional_params : JSON::Any?

    def initialize(
      @id : String,
      @name : String,
      @arguments : JSON::Any,
      @internal_call_id : String = Random::Secure.hex(8),
      @call_id : String? = nil,
      @signature : String? = nil,
      @additional_params : JSON::Any? = nil,
    )
    end

    def self.empty : self
      new("", "", JSON.parse("null"))
    end

    def with_internal_call_id(internal_call_id : String) : self
      self.class.new(@id, @name, @arguments, internal_call_id, @call_id, @signature, @additional_params)
    end

    def with_call_id(call_id : String) : self
      self.class.new(@id, @name, @arguments, @internal_call_id, call_id, @signature, @additional_params)
    end

    def with_signature(signature : String?) : self
      self.class.new(@id, @name, @arguments, @internal_call_id, @call_id, signature, @additional_params)
    end

    def with_additional_params(additional_params : JSON::Any?) : self
      self.class.new(@id, @name, @arguments, @internal_call_id, @call_id, @signature, additional_params)
    end

    def to_tool_call : Crig::Completion::ToolCall
      Crig::Completion::ToolCall.new(
        @id,
        Crig::Completion::ToolFunction.new(@name, @arguments),
        @call_id,
        @signature,
        @additional_params
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
      TextStart
      TextAdditionalParams
    end

    getter kind : Kind
    getter message : String?
    getter tool_call : RawStreamingToolCall?
    getter id : String?
    getter internal_call_id : String?
    getter content : ToolCallDeltaContent?
    getter reasoning_content : Crig::Completion::ReasoningContent?
    getter reasoning_id : String?
    getter reasoning_delta : String?
    getter final_response : R?
    getter message_id : String?
    getter additional_params : JSON::Any?

    def initialize(
      @kind : Kind,
      @message : String? = nil,
      @tool_call : RawStreamingToolCall? = nil,
      @id : String? = nil,
      @internal_call_id : String? = nil,
      @content : ToolCallDeltaContent? = nil,
      @reasoning_content : Crig::Completion::ReasoningContent? = nil,
      @reasoning_id : String? = nil,
      @reasoning_delta : String? = nil,
      @final_response : R? = nil,
      @message_id : String? = nil,
      @additional_params : JSON::Any? = nil,
    )
    end

    def self.message(message : String) : self
      new(Kind::Message, message: message)
    end

    def self.tool_call(tool_call : RawStreamingToolCall) : self
      new(Kind::ToolCall, tool_call: tool_call)
    end

    def self.tool_call_delta(id : String, internal_call_id : String, content : ToolCallDeltaContent) : self
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

    def self.text_start(additional_params : JSON::Any? = nil) : self
      new(Kind::TextStart, additional_params: additional_params)
    end

    def self.text_additional_params(params : JSON::Any) : self
      new(Kind::TextAdditionalParams, additional_params: params)
    end
  end

  struct StreamingResult(R)
    getter items : Array(RawStreamingChoice(R))

    def initialize(@items : Array(RawStreamingChoice(R)))
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
    getter content : ToolCallDeltaContent?
    getter reasoning : Crig::Completion::Reasoning?
    getter reasoning_delta : String?
    getter final : R?

    def initialize(
      @kind : Kind,
      @text : Crig::Completion::Text? = nil,
      @tool_call : Crig::Completion::ToolCall? = nil,
      @internal_call_id : String? = nil,
      @content : ToolCallDeltaContent? = nil,
      @reasoning : Crig::Completion::Reasoning? = nil,
      @reasoning_delta : String? = nil,
      @final : R? = nil,
    )
    end

    def self.text(text : String) : self
      new(Kind::Text, text: Crig::Completion::Text.new(text))
    end

    def self.tool_call(tool_call : Crig::Completion::ToolCall, internal_call_id : String) : self
      new(Kind::ToolCall, tool_call: tool_call, internal_call_id: internal_call_id)
    end

    def self.tool_call_delta(id : String, internal_call_id : String, content : ToolCallDeltaContent) : self
      placeholder = Crig::Completion::ToolCall.new(
        id,
        Crig::Completion::ToolFunction.new("", JSON.parse("null"))
      )
      new(Kind::ToolCallDelta, tool_call: placeholder, internal_call_id: internal_call_id, content: content)
    end

    def self.reasoning(reasoning : Crig::Completion::Reasoning) : self
      new(Kind::Reasoning, reasoning: reasoning)
    end

    def self.reasoning_delta(id : String?, reasoning : String) : self
      new(Kind::ReasoningDelta, reasoning: Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text(reasoning)], id), reasoning_delta: reasoning)
    end

    def self.final_response(response : R) : self
      new(Kind::Final, final: response)
    end

    def id : String?
      @tool_call.try(&.id)
    end

    def message : String?
      @text.try(&.text)
    end

    def reasoning_content : Crig::Completion::ReasoningContent?
      @reasoning.try(&.content.first?)
    end
  end

  struct StreamedUserContent
    enum Kind
      ToolResult
    end

    getter kind : Kind
    getter tool_result : Crig::Completion::ToolResult?
    getter internal_call_id : String

    def initialize(@kind : Kind, @internal_call_id : String, @tool_result : Crig::Completion::ToolResult? = nil)
    end

    def self.tool_result(tool_result : Crig::Completion::ToolResult, internal_call_id : String) : self
      new(Kind::ToolResult, internal_call_id, tool_result)
    end
  end

  # Stateful wrapper around provider streaming output.
  # Providers emit raw choices; this class assembles them into assistant content,
  # tracks the final response, and exposes pause/resume/cancel controls.
  class StreamingCompletionResponse(R)
    getter chunks : Array(String)
    getter choice : Crig::OneOrMany(Crig::Completion::AssistantContent)
    getter response : R?
    getter message_id : String?
    getter pause_control : PauseControl
    # ameba:disable Naming/QueryBoolMethods
    getter cancelled : Bool
    # ameba:enable Naming/QueryBoolMethods

    @raw_choices : Array(RawStreamingChoice(R))
    @source_channel : Channel(Crig::Concurrency::Result(RawStreamingChoice(R)))?
    @position : Int32
    @assistant_items : Array(Crig::Completion::AssistantContent)
    @text_item_index : Int32?
    @reasoning_item_index : Int32?
    @final_response_yielded : Bool

    def initialize(
      @chunks : Array(String),
      @response : R? = nil,
      choice : Crig::OneOrMany(Crig::Completion::AssistantContent)? = nil,
      @message_id : String? = nil,
      @pause_control : PauseControl = PauseControl.new,
      @cancelled : Bool = false,
    )
      @raw_choices = if choice
                       self.class.raw_choices_from_choice(choice)
                     else
                       @chunks.map { |chunk| RawStreamingChoice(R).message(chunk) }
                     end
      @source_channel = nil
      @raw_choices << RawStreamingChoice(R).final_response(@response.as(R)) if @response
      @position = 0
      @assistant_items = choice ? choice.to_a : [] of Crig::Completion::AssistantContent
      @text_item_index = nil
      @reasoning_item_index = nil
      @final_response_yielded = false
      @choice = choice || Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(""))
    end

    # Build a streaming response from plain text chunks.
    def self.stream(chunks : Array(String), response : R? = nil) : self
      new(chunks, response)
    end

    # Build a streaming response from pre-parsed provider streaming choices.
    def self.stream(raw_choices : Array(RawStreamingChoice(R))) : self
      new([] of String).tap do |response|
        response.load_raw_choices(raw_choices)
      end
    end

    # Build a streaming response from a channel-backed source.
    def self.stream(source_channel : Channel(Crig::Concurrency::Result(RawStreamingChoice(R)))) : self
      new([] of String).tap do |response|
        response.load_stream_channel(source_channel)
      end
    end

    def self.stream_raw_choices(raw_choices : Array(RawStreamingChoice(R))) : self
      stream(raw_choices)
    end

    def self.from_raw_choices(raw_choices : Array(RawStreamingChoice(R))) : self
      stream(raw_choices).tap(&.consume)
    end

    def final_response_yielded? : Bool
      @final_response_yielded
    end

    def final_response_yielded : Bool
      @final_response_yielded
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

    def cancel : Nil
      @cancelled = true
      if source_channel = @source_channel
        begin
          source_channel.close
        rescue Channel::ClosedError
        end
      end
    end

    def load_raw_choices(raw_choices : Array(RawStreamingChoice(R))) : self
      @raw_choices = raw_choices
      @source_channel = nil
      @chunks = [] of String
      @assistant_items = [] of Crig::Completion::AssistantContent
      @text_item_index = nil
      @reasoning_item_index = nil
      @choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("")
      )
      @position = 0
      @message_id = nil
      @response = nil
      @final_response_yielded = false
      @cancelled = false
      self
    end

    def load_stream_channel(source_channel : Channel(Crig::Concurrency::Result(RawStreamingChoice(R)))) : self
      @source_channel = source_channel
      @raw_choices = [] of RawStreamingChoice(R)
      @chunks = [] of String
      @assistant_items = [] of Crig::Completion::AssistantContent
      @text_item_index = nil
      @reasoning_item_index = nil
      @choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("")
      )
      @position = 0
      @message_id = nil
      @response = nil
      @final_response_yielded = false
      @cancelled = false
      self
    end

    def consume : Array(StreamedAssistantContent(R))
      items = [] of StreamedAssistantContent(R)
      while item = next_item
        items << item
      end
      items
    end

    def next_item : StreamedAssistantContent(R)?
      return if @cancelled || is_paused

      if @source_channel
        return next_stream_item
      end

      choice = @raw_choices[@position]?
      return unless choice

      @position += 1
      process_choice(choice)
    end

    private def next_stream_item : StreamedAssistantContent(R)?
      source_channel = @source_channel
      return unless source_channel

      loop do
        return if @cancelled || is_paused

        result = source_channel.receive?
        unless result
          finalize_choice
          return
        end

        if item = process_choice(result.unwrap)
          return item
        end
      end
    end

    def each_item(& : StreamedAssistantContent(R) ->) : Nil
      while item = next_item
        yield item
      end
    end

    def to_completion_response : Crig::Completion::CompletionResponse(R?)
      Crig::Completion::CompletionResponse(R?).new(
        @choice,
        Crig::Completion::Usage.new,
        @response,
        @message_id
      )
    end

    private def process_choice(choice : RawStreamingChoice(R)) : StreamedAssistantContent(R)?
      case choice.kind
      in .message?
        text = choice.message || ""
        @reasoning_item_index = nil
        append_text_chunk(text)
        finalize_choice
        StreamedAssistantContent(R).text(text)
      in .text_start?
        @reasoning_item_index = nil
        @text_item_index = nil
        if params = choice.additional_params
          append_text_additional_params(params)
        end
        next_item
      in .text_additional_params?
        if params = choice.additional_params
          append_text_additional_params(params)
        end
        next_item
      in .tool_call_delta?
        finalize_choice
        StreamedAssistantContent(R).tool_call_delta(
          choice.id || "",
          choice.internal_call_id || "",
          choice.content || ToolCallDeltaContent.delta("")
        )
      in .reasoning?
        @text_item_index = nil
        @reasoning_item_index = nil
        reasoning = Crig::Completion::Reasoning.new(
          [choice.reasoning_content || Crig::Completion::ReasoningContent.text("")],
          choice.reasoning_id
        )
        @assistant_items << Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning
        )
        finalize_choice
        StreamedAssistantContent(R).reasoning(reasoning)
      in .reasoning_delta?
        @text_item_index = nil
        append_reasoning_chunk(choice.reasoning_id, choice.reasoning_delta || "")
        finalize_choice
        StreamedAssistantContent(R).reasoning_delta(choice.reasoning_id, choice.reasoning_delta || "")
      in .tool_call?
        @text_item_index = nil
        @reasoning_item_index = nil
        raw_tool_call = choice.tool_call || RawStreamingToolCall.empty
        tool_call = raw_tool_call.to_tool_call
        @assistant_items << Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::ToolCall,
          tool_call: tool_call
        )
        finalize_choice
        StreamedAssistantContent(R).tool_call(tool_call, raw_tool_call.internal_call_id)
      in .final_response?
        return if @final_response_yielded
        @response = choice.final_response
        @final_response_yielded = true
        finalize_choice
        StreamedAssistantContent(R).final_response(choice.final_response.as(R))
      in .message_id?
        @message_id = choice.message_id
        next_item
      end
    end

    private def append_text_chunk(text : String) : Nil
      @chunks << text

      if index = @text_item_index
        existing = @assistant_items[index]?
        if existing && existing.kind.text?
          existing_text = existing.text
          if existing_text
            combined_text = "#{existing_text.text}#{text}"
            params = existing_text.additional_params
            @assistant_items[index] = Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::Text,
              text: Crig::Completion::Text.new(combined_text, params),
            )
            return
          end
        end
      end

      @assistant_items << Crig::Completion::AssistantContent.text(text)
      @text_item_index = @assistant_items.size - 1
    end

    private def append_text_additional_params(additional_params : JSON::Any) : Nil
      return if additional_params.raw.is_a?(Nil)

      index = if idx = @text_item_index
                existing = @assistant_items[idx]?
                existing && existing.kind.text? ? idx : nil
              end

      unless index
        @assistant_items << Crig::Completion::AssistantContent.text("")
        index = @assistant_items.size - 1
        @text_item_index = index
      end

      existing = @assistant_items[index]?
      return unless existing && existing.kind.text?

      text = existing.text
      return unless text

      if current = text.additional_params
        Crig::JSONUtils.merge_text_additional_params(current, additional_params)
      else
        @assistant_items[index] = Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Text,
          text: Crig::Completion::Text.new(text.text, additional_params),
        )
      end
    end

    private def append_reasoning_chunk(id : String?, text : String) : Nil
      if index = @reasoning_item_index
        existing = @assistant_items[index]?
        if existing && existing.kind.reasoning?
          reasoning = existing.reasoning
          if reasoning && (content = reasoning.content.last?) && content.kind.text?
            new_content = reasoning.content.dup
            new_content[-1] = Crig::Completion::ReasoningContent.text("#{content.text}#{text}", content.signature)
            updated = Crig::Completion::Reasoning.new(new_content, reasoning.id)
            @assistant_items[index] = Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::Reasoning,
              reasoning: updated
            )
            return
          end
        end
      end

      @assistant_items << Crig::Completion::AssistantContent.new(
        Crig::Completion::AssistantContent::Kind::Reasoning,
        reasoning: Crig::Completion::Reasoning.new(
          [Crig::Completion::ReasoningContent.text(text)],
          id
        )
      )
      @reasoning_item_index = @assistant_items.size - 1
    end

    private def finalize_choice : Nil
      items = @assistant_items.empty? ? [Crig::Completion::AssistantContent.text("")] : @assistant_items
      @choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(items)
    end

    def self.raw_choices_from_choice(
      choice : Crig::OneOrMany(Crig::Completion::AssistantContent),
    ) : Array(RawStreamingChoice(R))
      choice.to_a.flat_map do |item|
        case item.kind
        in .text?
          [RawStreamingChoice(R).message(item.text.try(&.text) || "")]
        in .tool_call?
          tool_call = item.tool_call
          if tool_call
            raw_tool_call = RawStreamingToolCall.new(
              tool_call.id,
              tool_call.function.name,
              tool_call.function.arguments,
              tool_call.call_id || tool_call.id,
              tool_call.call_id,
              tool_call.signature,
              tool_call.additional_params
            )
            [RawStreamingChoice(R).tool_call(raw_tool_call)]
          else
            [] of RawStreamingChoice(R)
          end
        in .reasoning?
          reasoning = item.reasoning
          if reasoning
            reasoning.content.map do |content|
              RawStreamingChoice(R).reasoning(reasoning.id, content)
            end
          else
            [] of RawStreamingChoice(R)
          end
        in .image?
          [] of RawStreamingChoice(R)
        end
      end
    end
  end

  # Consume a stream to completion while writing visible text chunks to an IO.
  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(R), io : IO = STDOUT) : R forall R
    final_response = nil.as(R?)

    stream.each_item do |item|
      case item.kind
      in .text?
        if text = item.text
          io.print(text.text)
          io.flush
        end
      in .reasoning?
        if reasoning = item.reasoning
          io.print(reasoning.display_text)
          io.flush
        end
      in .tool_call?
      in .tool_call_delta?
      in .reasoning_delta?
      in .final?
        final_response = item.final
      end
    end

    final_response || stream.response || raise "stream produced no final response"
  end
end
