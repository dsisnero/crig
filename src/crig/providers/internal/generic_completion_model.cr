module Crig
  module Providers
    module Internal
      module GenericCompletionModel
        def self.send_completion_request(
          client,
          path : String,
          body : String,
          provider_name : String,
          model : String,
          preamble : String?,
          &
        )
          span = Crig::Span.chat_span(provider_name, model, preamble, nil)

          response = client.post_json(path, body)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          result = yield parsed

          if raw_response = result.raw_response
            span.record_response_metadata(raw_response) if raw_response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def self.send_streaming_request(
          client,
          path : String,
          body : String,
          provider_name : String,
          model : String,
          preamble : String?,
          additional_headers : Hash(String, String) = {} of String => String,
          &
        )
          all_headers = additional_headers.merge({"Accept" => "text/event-stream"})

          response = client.post_json(path, body, all_headers)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          yield text
        end
      end
    end
  end
end
