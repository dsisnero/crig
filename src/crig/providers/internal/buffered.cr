module Crig
  module Providers
    module Internal
      # Create a Usage with the given token counts and zero values for the rest.
      def self.completion_usage(
        input_tokens : Int64,
        output_tokens : Int64,
        total_tokens : Int64,
        cached_input_tokens : Int64 = 0_i64,
      ) : Crig::Completion::Usage
        Crig::Completion::Usage.new(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens,
          cached_input_tokens: cached_input_tokens,
          cache_creation_input_tokens: 0_i64,
          reasoning_tokens: 0_i64,
        )
      end

      # Adapt a buffered (non-streaming) CompletionResponse into a streaming response.
      #
      # Each AssistantContent in the response choice is mapped through `map_content`
      # to zero or more RawStreamingChoice items. A FinalResponse is appended at
      # the end of the stream.
      # Adapt a buffered (non-streaming) CompletionResponse into a streaming response.
      # The block maps each AssistantContent to zero or more RawStreamingChoice items.
      def self.stream_from_completion_response(response : Crig::Completion::CompletionResponse(R), &) : Crig::StreamingCompletionResponse(R) forall R
        raw_choices = [] of Crig::RawStreamingChoice(R)

        response.choice.each do |content|
          mapped = yield(content).as(Array(Crig::RawStreamingChoice(R)))
          raw_choices.concat(mapped)
        end

        raw_choices << Crig::RawStreamingChoice(R).final_response(response.raw_response)
        Crig::StreamingCompletionResponse(R).stream_raw_choices(raw_choices)
      end
    end
  end
end
