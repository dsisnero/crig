module Crig
  module Providers
    module XAI
      def self.send_xai_streaming_request(
        client : Client,
        model : String,
        request : XAICompletionRequest,
      ) : Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse)
        payload = request.to_json_value.as_h
        payload = OpenAI.merge_json_hashes(payload, {"stream" => JSON::Any.new(true)})
        response = client.post_json("/v1/responses", payload.to_json, {"Accept" => "text/event-stream"})
        text = response.body
        raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

        raw_choices = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
          Crig::Providers::OpenAI::Client.new(client.api_key, client.base_url),
          model,
        ).parse_streaming_choices(text)

        Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).stream_raw_choices(raw_choices)
      end
    end
  end
end
