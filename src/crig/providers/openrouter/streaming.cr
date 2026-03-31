module Crig
  module Providers
    module OpenRouter
      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : Usage

        def initialize(@usage : Usage = Usage.new(0, 0, 0))
        end

        def token_usage : Crig::Completion::Usage?
          @usage.token_usage
        end
      end

      struct FinishReason
        enum Kind
          ToolCalls
          Stop
          Error
          ContentFilter
          Length
          Other
        end

        getter kind : Kind
        getter value : String

        def initialize(@kind : Kind, @value : String)
        end

        def self.from_string(value : String) : self
          case value
          when "tool_calls"     then new(Kind::ToolCalls, value)
          when "stop"           then new(Kind::Stop, value)
          when "error"          then new(Kind::Error, value)
          when "content_filter" then new(Kind::ContentFilter, value)
          when "length"         then new(Kind::Length, value)
          else
            new(Kind::Other, value)
          end
        end

        delegate tool_calls?, to: @kind
      end

      struct StreamingFunction
        include JSON::Serializable

        getter name : String?
        getter arguments : String?

        def initialize(@name : String? = nil, @arguments : String? = nil)
        end
      end

      struct StreamingToolCall
        include JSON::Serializable

        getter index : Int32
        getter id : String?
        @[JSON::Field(key: "type")]
        getter type : String?
        getter function : StreamingFunction

        def initialize(@index : Int32, @function : StreamingFunction, @id : String? = nil, @type : String? = nil)
        end
      end

      struct StreamingDelta
        getter role : String?
        getter content : String?
        getter tool_calls : Array(StreamingToolCall)
        getter reasoning : String?
        getter reasoning_details : Array(ReasoningDetails)

        def initialize(
          @role : String? = nil,
          @content : String? = nil,
          @tool_calls : Array(StreamingToolCall) = [] of StreamingToolCall,
          @reasoning : String? = nil,
          @reasoning_details : Array(ReasoningDetails) = [] of ReasoningDetails,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["role"]?.try(&.as_s?),
            hash["content"]?.try(&.as_s?),
            hash["tool_calls"]?.try(&.as_a?).try(&.map { |entry| StreamingToolCall.from_json(entry.to_json) }) || [] of StreamingToolCall,
            hash["reasoning"]?.try(&.as_s?),
            hash["reasoning_details"]?.try(&.as_a?).try(&.map { |entry| ReasoningDetails.from_json_value(entry) }) || [] of ReasoningDetails,
          )
        end
      end

      struct StreamingChoice
        getter finish_reason : FinishReason?
        getter native_finish_reason : String?
        getter index : Int32
        getter delta : StreamingDelta

        def initialize(@index : Int32, @delta : StreamingDelta, @finish_reason : FinishReason? = nil, @native_finish_reason : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"].as_i,
            StreamingDelta.from_json_value(hash["delta"]),
            hash["finish_reason"]?.try(&.as_s?).try { |reason| FinishReason.from_string(reason) },
            hash["native_finish_reason"]?.try(&.as_s?),
          )
        end
      end

      struct ErrorResponse
        include JSON::Serializable

        getter code : Int32
        getter message : String

        def initialize(@code : Int32, @message : String)
        end
      end

      struct StreamingCompletionChunk
        getter id : String
        getter model : String
        getter choices : Array(StreamingChoice)
        getter usage : Usage?
        getter error : ErrorResponse?

        def initialize(
          @id : String,
          @model : String,
          @choices : Array(StreamingChoice),
          @usage : Usage? = nil,
          @error : ErrorResponse? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            hash["model"].as_s,
            hash["choices"].as_a.map { |entry| StreamingChoice.from_json_value(entry) },
            hash["usage"]?.try(&.as_h?).try { |usage| Usage.from_json(usage.to_json) },
            hash["error"]?.try(&.as_h?).try { |error| ErrorResponse.from_json(error.to_json) },
          )
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def self.send_compatible_streaming_request(
        client : Client,
        request : OpenrouterCompletionRequest,
      ) : Crig::StreamingCompletionResponse(Crig::Providers::OpenRouter::StreamingCompletionResponse)
        response = client.post_json(
          "/chat/completions",
          request.to_json_value.to_json,
          {"Accept" => "text/event-stream"}
        )
        text = response.body
        raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

        raw_choices = [] of Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse)
        tool_calls = {} of Int32 => {String, String, JSON::Any, String?, JSON::Any?}
        final_usage = Usage.new(0, 0, 0)
        message_id : String? = nil

        text.each_line do |line|
          next unless line.starts_with?("data:")
          data = line.lchop("data:").strip
          next if data.empty? || data == "[DONE]"

          chunk = StreamingCompletionChunk.from_json_value(JSON.parse(data))
          unless message_id
            message_id = chunk.id
            raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).message_id(chunk.id)
          end
          if usage = chunk.usage
            final_usage = usage
          end
          choice = chunk.choices.first?
          next unless choice
          delta = choice.delta

          if reasoning = delta.reasoning
            unless reasoning.empty?
              raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).reasoning_delta(nil, reasoning)
            end
          end

          unless delta.content.to_s.empty?
            raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).message(delta.content.to_s)
          end

          delta.tool_calls.each do |tool_call|
            existing = tool_calls[tool_call.index]? || {"", "", JSON::Any.new(""), nil, nil}
            id = tool_call.id || existing[0]
            name = tool_call.function.name || existing[1]
            current_args = existing[2].as_s? || existing[2].to_json
            incoming_args = tool_call.function.arguments || ""
            combined_args = current_args + incoming_args
            parsed_args = begin
              JSON.parse(combined_args)
            rescue
              JSON::Any.new(combined_args)
            end
            tool_calls[tool_call.index] = {id, name, parsed_args, existing[3], existing[4]}

            if incoming_name = tool_call.function.name
              unless incoming_name.empty?
                raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).tool_call_delta(
                  id,
                  id.empty? ? tool_call.index.to_s : id,
                  Crig::ToolCallDeltaContent.name(incoming_name),
                )
              end
            end
            unless incoming_args.empty?
              raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).tool_call_delta(
                id,
                id.empty? ? tool_call.index.to_s : id,
                Crig::ToolCallDeltaContent.delta(incoming_args),
              )
            end
          end

          delta.reasoning_details.each do |detail|
            next unless detail.kind.encrypted?
            if encrypted_id = detail.id
              tool_calls.each do |index, current|
                next unless current[0] == encrypted_id
                tool_calls[index] = {current[0], current[1], current[2], detail.data, detail.to_json_value}
              end
            end
          end

          if choice.finish_reason.try(&.tool_calls?)
            tool_calls.keys.sort!.each do |index|
              id, name, arguments, signature, additional_params = tool_calls[index]
              raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).tool_call(
                Crig::RawStreamingToolCall.new(
                  id,
                  name,
                  arguments,
                  id.empty? ? index.to_s : id,
                  nil,
                  signature,
                  additional_params,
                )
              )
              tool_calls.delete(index)
            end
          end
        end

        tool_calls.keys.sort!.each do |index|
          id, name, arguments, signature, additional_params = tool_calls[index]
          raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).tool_call(
            Crig::RawStreamingToolCall.new(
              id,
              name,
              arguments,
              id.empty? ? index.to_s : id,
              nil,
              signature,
              additional_params,
            )
          )
        end

        raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenRouter::StreamingCompletionResponse).final_response(
          StreamingCompletionResponse.new(final_usage)
        )
        Crig::StreamingCompletionResponse(Crig::Providers::OpenRouter::StreamingCompletionResponse).stream_raw_choices(raw_choices)
      end
      # ameba:enable Metrics/CyclomaticComplexity
    end
  end
end
