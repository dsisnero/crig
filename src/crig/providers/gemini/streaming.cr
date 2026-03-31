module Crig
  module Providers
    module Gemini
      struct PartialUsage
        include JSON::Serializable

        @[JSON::Field(key: "totalTokenCount")]
        getter total_token_count : Int32 = 0
        @[JSON::Field(key: "cachedContentTokenCount")]
        getter cached_content_token_count : Int32?
        @[JSON::Field(key: "candidatesTokenCount")]
        getter candidates_token_count : Int32?
        @[JSON::Field(key: "thoughtsTokenCount")]
        getter thoughts_token_count : Int32?
        @[JSON::Field(key: "promptTokenCount")]
        getter prompt_token_count : Int32 = 0

        def initialize(
          @total_token_count : Int32 = 0,
          @cached_content_token_count : Int32? = nil,
          @candidates_token_count : Int32? = nil,
          @thoughts_token_count : Int32? = nil,
          @prompt_token_count : Int32 = 0,
        )
        end

        def token_usage : Crig::Completion::Usage
          input_tokens = @prompt_token_count.to_i64
          output_tokens = (@cached_content_token_count || 0).to_i64 +
                          (@candidates_token_count || 0).to_i64 +
                          (@thoughts_token_count || 0).to_i64
          Crig::Completion::Usage.new(
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: input_tokens + output_tokens,
            cached_input_tokens: (@cached_content_token_count || 0).to_i64,
          )
        end
      end

      struct StreamGenerateContentResponse
        include JSON::Serializable

        getter candidates : Array(ContentCandidate)
        @[JSON::Field(key: "modelVersion")]
        getter model_version : String?
        @[JSON::Field(key: "usageMetadata")]
        getter usage_metadata : PartialUsage?

        def initialize(
          @candidates : Array(ContentCandidate),
          @model_version : String? = nil,
          @usage_metadata : PartialUsage? = nil,
        )
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable

        @[JSON::Field(key: "usageMetadata")]
        getter usage_metadata : PartialUsage

        def initialize(@usage_metadata : PartialUsage = PartialUsage.new)
        end

        def token_usage : Crig::Completion::Usage
          usage_metadata.token_usage
        end
      end

      struct CompletionModel
        def stream(request : Crig::Completion::Request::CompletionRequest)
          request_model = Gemini.resolve_request_model(@model, request)
          payload = Gemini.create_request_body(request)
          response = @client.post_json(Gemini.streaming_endpoint(request_model), payload.to_json, sse: true)
          body = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(body)
          end

          Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(
            parse_streaming_choices(body)
          )
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          final_usage = nil.as(PartialUsage?)

          text.each_line do |line|
            next unless line.starts_with?("data:")

            data_str = line[5..].to_s.strip
            next if data_str.empty? || data_str == "[DONE]"

            data = begin
              StreamGenerateContentResponse.from_json(data_str)
            rescue ex
              raise Crig::Completion::CompletionError.new("Failed to parse Gemini SSE message: #{ex.message}")
            end

            choice = data.candidates.first?
            next unless choice
            content = choice.content
            next unless content

            content.parts.each do |part|
              append_stream_part(raw_choices, part)
            end

            if choice.finish_reason
              final_usage = data.usage_metadata
              break
            end
          end

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
            StreamingCompletionResponse.new(final_usage || PartialUsage.new)
          )
          raw_choices
        end

        private def append_stream_part(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          part : Part,
        ) : Nil
          case part.part.kind
          in .text?
            text = part.part.text || ""
            return if text.empty?

            if part.thought
              if part.thought_signature
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning(
                  nil,
                  Crig::Completion::ReasoningContent.text(text, part.thought_signature)
                )
              else
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, text)
              end
            else
              raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(text)
            end
          in .function_call?
            function_call = part.part.function_call.as(FunctionCall)
            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(
                function_call.name,
                function_call.name,
                function_call.args
              ).with_signature(part.thought_signature)
            )
          in .inline_data?, .function_response?, .file_data?, .executable_code?, .code_execution_result?
          end
        end
      end
    end
  end
end
