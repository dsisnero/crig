module Crig
  module Providers
    module OpenAI
      module ResponseChunkKindConverter
        def self.from_json(pull : JSON::PullParser) : ResponseChunkKind
          ResponseChunkKind.from_wire(pull.read_string)
        end

        def self.to_json(value : ResponseChunkKind, json : JSON::Builder)
          json.string(value.to_wire)
        end
      end

      enum ResponseChunkKind
        ResponseCreated
        ResponseInProgress
        ResponseCompleted
        ResponseFailed
        ResponseIncomplete

        def self.from_wire(value : String) : self
          case value
          when "response.created"
            ResponseCreated
          when "response.in_progress"
            ResponseInProgress
          when "response.completed"
            ResponseCompleted
          when "response.failed"
            ResponseFailed
          when "response.incomplete"
            ResponseIncomplete
          else
            raise ArgumentError.new("Unknown OpenAI Responses chunk kind: #{value}")
          end
        end

        def to_wire : String
          case self
          in .response_created?
            "response.created"
          in .response_in_progress?
            "response.in_progress"
          in .response_completed?
            "response.completed"
          in .response_failed?
            "response.failed"
          in .response_incomplete?
            "response.incomplete"
          end
        end
      end

      struct ContentPartChunkPart
        enum Kind
          OutputText
          SummaryText
        end

        getter kind : Kind
        getter text : String

        def initialize(@kind : Kind, @text : String)
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "output_text"
            new(Kind::OutputText, value["text"].as_s)
          when "summary_text"
            new(Kind::SummaryText, value["text"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI content part chunk type: #{value["type"].as_s}")
          end
        end
      end

      struct SummaryPartChunkPart
        enum Kind
          SummaryText
        end

        getter kind : Kind
        getter text : String

        def initialize(@kind : Kind, @text : String)
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "summary_text"
            new(Kind::SummaryText, value["text"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI summary part chunk type: #{value["type"].as_s}")
          end
        end
      end

      struct ResponsesStreamingCompletionResponse
        include JSON::Serializable

        getter usage : ResponsesUsage

        def initialize(@usage : ResponsesUsage)
        end
      end

      struct ResponseChunk
        include JSON::Serializable

        @[JSON::Field(key: "type", converter: Crig::Providers::OpenAI::ResponseChunkKindConverter)]
        getter kind : ResponseChunkKind
        getter response : CompletionResponsePayload
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64

        def initialize(@kind : ResponseChunkKind, @response : CompletionResponsePayload, @sequence_number : Int64)
        end
      end

      struct StreamingItemDoneOutput
        include JSON::Serializable

        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        @[JSON::Field(converter: Crig::Providers::OpenAI::OutputConverter)]
        getter item : Output

        def initialize(@sequence_number : Int64, @item : Output)
        end
      end

      struct ContentPartChunk
        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter part : ContentPartChunkPart

        def initialize(@content_index : Int64, @sequence_number : Int64, @part : ContentPartChunkPart)
        end

        def self.from_json_value(value : JSON::Any) : self
          new(
            value["content_index"].as_i64,
            value["sequence_number"].as_i64,
            ContentPartChunkPart.from_json_value(value["part"]),
          )
        end

        def self.from_json(text : String) : self
          from_json_value(JSON.parse(text))
        end
      end

      struct DeltaTextChunk
        include JSON::Serializable

        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter delta : String

        def initialize(@content_index : Int64, @sequence_number : Int64, @delta : String)
        end
      end

      struct DeltaTextChunkWithItemId
        include JSON::Serializable

        @[JSON::Field(key: "item_id")]
        getter item_id : String
        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter delta : String

        def initialize(@item_id : String, @content_index : Int64, @sequence_number : Int64, @delta : String)
        end
      end

      struct OutputTextChunk
        include JSON::Serializable

        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter text : String

        def initialize(@content_index : Int64, @sequence_number : Int64, @text : String)
        end
      end

      struct RefusalTextChunk
        include JSON::Serializable

        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter refusal : String

        def initialize(@content_index : Int64, @sequence_number : Int64, @refusal : String)
        end
      end

      struct ArgsTextChunk
        include JSON::Serializable

        @[JSON::Field(key: "content_index")]
        getter content_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter arguments : JSON::Any

        def initialize(@content_index : Int64, @sequence_number : Int64, @arguments : JSON::Any)
        end
      end

      struct SummaryPartChunk
        @[JSON::Field(key: "summary_index")]
        getter summary_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter part : SummaryPartChunkPart

        def initialize(@summary_index : Int64, @sequence_number : Int64, @part : SummaryPartChunkPart)
        end

        def self.from_json_value(value : JSON::Any) : self
          new(
            value["summary_index"].as_i64,
            value["sequence_number"].as_i64,
            SummaryPartChunkPart.from_json_value(value["part"]),
          )
        end

        def self.from_json(text : String) : self
          from_json_value(JSON.parse(text))
        end
      end

      struct SummaryTextChunk
        include JSON::Serializable

        @[JSON::Field(key: "summary_index")]
        getter summary_index : Int64
        @[JSON::Field(key: "sequence_number")]
        getter sequence_number : Int64
        getter delta : String

        def initialize(@summary_index : Int64, @sequence_number : Int64, @delta : String)
        end
      end

      struct OutputItemAdded
        getter message : StreamingItemDoneOutput

        def initialize(@message : StreamingItemDoneOutput)
        end
      end

      struct OutputItemDone
        getter message : StreamingItemDoneOutput

        def initialize(@message : StreamingItemDoneOutput)
        end
      end

      struct ContentPartAdded
        getter chunk : ContentPartChunk

        def initialize(@chunk : ContentPartChunk)
        end
      end

      struct ContentPartDone
        getter chunk : ContentPartChunk

        def initialize(@chunk : ContentPartChunk)
        end
      end

      struct OutputTextDelta
        getter chunk : DeltaTextChunk

        def initialize(@chunk : DeltaTextChunk)
        end
      end

      struct OutputTextDone
        getter chunk : OutputTextChunk

        def initialize(@chunk : OutputTextChunk)
        end
      end

      struct RefusalDelta
        getter chunk : DeltaTextChunk

        def initialize(@chunk : DeltaTextChunk)
        end
      end

      struct RefusalDone
        getter chunk : RefusalTextChunk

        def initialize(@chunk : RefusalTextChunk)
        end
      end

      struct FunctionCallArgsDelta
        getter chunk : DeltaTextChunkWithItemId

        def initialize(@chunk : DeltaTextChunkWithItemId)
        end
      end

      struct FunctionCallArgsDone
        getter chunk : ArgsTextChunk

        def initialize(@chunk : ArgsTextChunk)
        end
      end

      struct ReasoningSummaryPartAdded
        getter chunk : SummaryPartChunk

        def initialize(@chunk : SummaryPartChunk)
        end
      end

      struct ReasoningSummaryPartDone
        getter chunk : SummaryPartChunk

        def initialize(@chunk : SummaryPartChunk)
        end
      end

      struct ReasoningSummaryTextDelta
        getter chunk : SummaryTextChunk

        def initialize(@chunk : SummaryTextChunk)
        end
      end

      struct ReasoningSummaryTextDone
        getter chunk : SummaryTextChunk

        def initialize(@chunk : SummaryTextChunk)
        end
      end

      alias ItemChunkKind = OutputItemAdded |
                            OutputItemDone |
                            ContentPartAdded |
                            ContentPartDone |
                            OutputTextDelta |
                            OutputTextDone |
                            RefusalDelta |
                            RefusalDone |
                            FunctionCallArgsDelta |
                            FunctionCallArgsDone |
                            ReasoningSummaryPartAdded |
                            ReasoningSummaryPartDone |
                            ReasoningSummaryTextDelta |
                            ReasoningSummaryTextDone

      struct ItemChunk
        getter item_id : String?
        getter output_index : Int64
        getter data : ItemChunkKind

        def initialize(@item_id : String?, @output_index : Int64, @data : ItemChunkKind)
        end

        def self.from_json_value(value : JSON::Any) : self
          item_id = value["item_id"]?.try(&.as_s?)
          output_index = value["output_index"].as_i64
          data = parse_data(value)
          new(item_id, output_index, data)
        end

        def self.from_json(text : String) : self
          from_json_value(JSON.parse(text))
        end

        # ameba:disable Metrics/CyclomaticComplexity
        private def self.parse_data(value : JSON::Any) : ItemChunkKind
          case value["type"].as_s
          when "response.output_item.added"
            OutputItemAdded.new(StreamingItemDoneOutput.from_json(value.to_json))
          when "response.output_item.done"
            OutputItemDone.new(StreamingItemDoneOutput.from_json(value.to_json))
          when "response.content_part.added"
            ContentPartAdded.new(ContentPartChunk.from_json_value(value))
          when "response.content_part.done"
            ContentPartDone.new(ContentPartChunk.from_json_value(value))
          when "response.output_text.delta"
            OutputTextDelta.new(DeltaTextChunk.from_json(value.to_json))
          when "response.output_text.done"
            OutputTextDone.new(OutputTextChunk.from_json(value.to_json))
          when "response.refusal.delta"
            RefusalDelta.new(DeltaTextChunk.from_json(value.to_json))
          when "response.refusal.done"
            RefusalDone.new(RefusalTextChunk.from_json(value.to_json))
          when "response.function_call_arguments.delta"
            FunctionCallArgsDelta.new(DeltaTextChunkWithItemId.from_json(value.to_json))
          when "response.function_call_arguments.done"
            FunctionCallArgsDone.new(ArgsTextChunk.from_json(value.to_json))
          when "response.reasoning_summary_part.added"
            ReasoningSummaryPartAdded.new(SummaryPartChunk.from_json_value(value))
          when "response.reasoning_summary_part.done"
            ReasoningSummaryPartDone.new(SummaryPartChunk.from_json_value(value))
          when "response.reasoning_summary_text.delta"
            ReasoningSummaryTextDelta.new(SummaryTextChunk.from_json(value.to_json))
          when "response.reasoning_summary_text.done"
            ReasoningSummaryTextDone.new(SummaryTextChunk.from_json(value.to_json))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI Responses item chunk type: #{value["type"].as_s}")
          end
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end

      struct StreamingResponseChunk
        getter chunk : ResponseChunk

        def initialize(@chunk : ResponseChunk)
        end
      end

      struct StreamingDeltaChunk
        getter chunk : ItemChunk

        def initialize(@chunk : ItemChunk)
        end
      end

      alias StreamingCompletionChunk = StreamingResponseChunk | StreamingDeltaChunk

      struct ResponsesCompletionModel
        def reasoning_choices_from_done_item(
          id : String,
          summary : Array(ReasoningSummary),
          encrypted_content : String?,
        ) : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse))
          choices = summary.map do |reasoning_summary|
            Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).reasoning(
              id,
              Crig::Completion::ReasoningContent.summary(reasoning_summary.text),
            )
          end

          if encrypted_content
            choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).reasoning(
              id,
              Crig::Completion::ReasoningContent.encrypted(encrypted_content),
            )
          end

          choices
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse)
          final_usage = ResponsesUsage.new
          tool_calls = [] of Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse)
          tool_call_internal_ids = {} of String => String

          text.each_line do |line|
            next unless line.starts_with?("data:")
            data = line.lchop("data:").strip
            next if data.empty?

            parsed_chunk = parse_streaming_chunk(data)

            case parsed_chunk
            when StreamingResponseChunk
              response_chunk = parsed_chunk.chunk
              if response_chunk.kind.response_completed?
                if usage = response_chunk.response.usage
                  final_usage = usage
                end
              end
            when StreamingDeltaChunk
              case item_data = parsed_chunk.chunk.data
              when OutputItemAdded
                item = item_data.message.item
                case item.kind
                when .function_call?
                  function_call = require_function_call(item)
                  internal_call_id = tool_call_internal_ids[function_call.id]? || Random::Secure.hex(8).tap { |value| tool_call_internal_ids[function_call.id] = value }
                  raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).tool_call_delta(
                    function_call.id,
                    internal_call_id,
                    Crig::ToolCallDeltaContent.name(function_call.name),
                  )
                end
              when OutputItemDone
                item = item_data.message.item
                case item.kind
                when .function_call?
                  function_call = require_function_call(item)
                  internal_call_id = tool_call_internal_ids[function_call.id]? || Random::Secure.hex(8).tap { |value| tool_call_internal_ids[function_call.id] = value }
                  tool_calls << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).tool_call(
                    Crig::RawStreamingToolCall.new(
                      function_call.id,
                      function_call.name,
                      function_call.arguments,
                      internal_call_id,
                      function_call.call_id,
                    )
                  )
                when .reasoning?
                  reasoning = require_reasoning(item)
                  raw_choices.concat(
                    reasoning_choices_from_done_item(
                      reasoning.id,
                      reasoning.summary,
                      reasoning.encrypted_content,
                    )
                  )
                when .message?
                  message = require_message(item)
                  raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).message_id(message.id)
                end
              when OutputTextDelta
                raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).message(item_data.chunk.delta)
              when RefusalDelta
                raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).message(item_data.chunk.delta)
              when ReasoningSummaryTextDelta
                raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).reasoning_delta(nil, item_data.chunk.delta)
              when FunctionCallArgsDelta
                delta = item_data.chunk
                internal_call_id = tool_call_internal_ids[delta.item_id]? || Random::Secure.hex(8).tap { |value| tool_call_internal_ids[delta.item_id] = value }
                raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).tool_call_delta(
                  delta.item_id,
                  internal_call_id,
                  Crig::ToolCallDeltaContent.delta(delta.delta),
                )
              else
                next
              end
            end
          rescue JSON::ParseException
            next
          end

          raw_choices.concat(tool_calls)
          raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).final_response(
            ResponsesStreamingCompletionResponse.new(final_usage)
          )
          raw_choices
        end

        # ameba:enable Metrics/CyclomaticComplexity

        private def parse_streaming_chunk(data : String) : StreamingCompletionChunk
          value = JSON.parse(data)
          if value["response"]?
            StreamingResponseChunk.new(ResponseChunk.from_json(data))
          else
            StreamingDeltaChunk.new(ItemChunk.from_json_value(value))
          end
        end

        private def require_function_call(item : Output) : OutputFunctionCall
          item.function_call || raise Crig::Completion::CompletionError.new("Missing OpenAI function call output")
        end

        private def require_reasoning(item : Output) : OutputReasoning
          item.reasoning || raise Crig::Completion::CompletionError.new("Missing OpenAI reasoning output")
        end

        private def require_message(item : Output) : OutputMessage
          item.message || raise Crig::Completion::CompletionError.new("Missing OpenAI message output")
        end
      end
    end
  end
end
