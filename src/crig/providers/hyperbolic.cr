require "base64"
require "http/client"

module Crig
  module Providers
    module Hyperbolic
      HYPERBOLIC_API_BASE_URL = "https://api.hyperbolic.xyz"

      LLAMA_3_1_8B         = "meta-llama/Meta-Llama-3.1-8B-Instruct"
      LLAMA_3_3_70B        = "meta-llama/Llama-3.3-70B-Instruct"
      LLAMA_3_1_70B        = "meta-llama/Meta-Llama-3.1-70B-Instruct"
      LLAMA_3_70B          = "meta-llama/Meta-Llama-3-70B-Instruct"
      HERMES_3_70B         = "NousResearch/Hermes-3-Llama-3.1-70b"
      DEEPSEEK_2_5         = "deepseek-ai/DeepSeek-V2.5"
      QWEN_2_5_72B         = "Qwen/Qwen2.5-72B-Instruct"
      LLAMA_3_2_3B         = "meta-llama/Llama-3.2-3B-Instruct"
      QWEN_2_5_CODER_32B   = "Qwen/Qwen2.5-Coder-32B-Instruct"
      QWEN_QWQ_PREVIEW_32B = "Qwen/QwQ-32B-Preview"
      DEEPSEEK_R1_ZERO     = "deepseek-ai/DeepSeek-R1-Zero"
      DEEPSEEK_R1          = "deepseek-ai/DeepSeek-R1"
      SDXL1_0_BASE         = "SDXL1.0-base"
      SD2                  = "SD2"
      SD1_5                = "SD1.5"
      SSD                  = "SSD"
      SDXL_TURBO           = "SDXL-turbo"
      SDXL_CONTROLNET      = "SDXL-ControlNet"
      SD1_5_CONTROLNET     = "SD1.5-ControlNet"

      struct HyperbolicExt
      end

      struct HyperbolicBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = HYPERBOLIC_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "HYPERBOLIC_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if message = value.as_h["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct EmbeddingData
        include JSON::Serializable

        getter object : String
        getter embedding : Array(Float64)
        getter index : Int32

        def initialize(@object : String, @embedding : Array(Float64), @index : Int32)
        end
      end

      struct Usage
        include JSON::Serializable

        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @total_tokens : Int32)
        end
      end

      struct Choice
        include JSON::Serializable

        getter index : Int32
        getter message : Crig::Providers::OpenAI::Chat::Message
        getter finish_reason : String

        def initialize(@index : Int32, @message : Crig::Providers::OpenAI::Chat::Message, @finish_reason : String)
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"].as_i,
            Crig::Providers::OpenAI::Chat::Message.from_json_value(hash["message"]),
            hash["finish_reason"].as_s,
          )
        end
      end

      struct CompletionResponse
        include JSON::Serializable

        getter id : String
        getter object : String
        getter created : Int64
        getter model : String
        getter choices : Array(Choice)
        getter usage : Usage?

        def initialize(
          @id : String,
          @object : String,
          @created : Int64,
          @model : String,
          @choices : Array(Choice),
          @usage : Usage? = nil,
        )
        end

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          message = choice.message
          raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call") unless message.kind.assistant?

          content = [] of Crig::Completion::AssistantContent
          message.assistant_content.each do |entry|
            text = case entry.kind
                   in .text?
                     entry.text
                   in .refusal?
                     entry.text
                   end
            content << Crig::Completion::AssistantContent.text(text) unless text.to_s.empty?
          end
          message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(
              call.id,
              call.function.name,
              call.function.arguments,
            )
          end
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") if content.empty?

          usage = if response_usage = @usage
                    Crig::Completion::Usage.new(
                      input_tokens: response_usage.prompt_tokens.to_i64,
                      output_tokens: (response_usage.total_tokens - response_usage.prompt_tokens).to_i64,
                      total_tokens: response_usage.total_tokens.to_i64,
                      cached_input_tokens: 0_i64,
                    )
                  else
                    Crig::Completion::Usage.new
                  end

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
            usage,
            self,
          )
        end
      end

      struct HyperbolicCompletionRequest
        getter model : String
        getter messages : Array(Crig::Providers::OpenAI::Chat::Message)
        getter temperature : Float64?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Crig::Providers::OpenAI::Chat::Message),
          @temperature : Float64? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          model = req.model || default_model
          params = Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(model, req)
          openai_request = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(params)

          new(
            model,
            openai_request.messages,
            req.temperature,
            req.additional_params,
          )
        end

        def to_json(json : JSON::Builder) : Nil
          payload = Crig::Providers::OpenAI.build_json_any do |builder|
            builder.object do
              builder.field "model", @model
              builder.field "messages" do
                builder.array do
                  @messages.each(&.to_json_value.to_json(builder))
                end
              end
              builder.field "temperature", @temperature unless @temperature.nil?
            end
          end

          merged = if params = @additional_params
                     JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, params.as_h).to_json)
                   else
                     payload
                   end
          merged.to_json(json)
        end
      end

      struct Image
        include JSON::Serializable

        getter image : String

        def initialize(@image : String)
        end
      end

      struct ImageGenerationResponse
        include JSON::Serializable

        getter images : Array(Image)

        def initialize(@images : Array(Image))
        end

        def to_crig_response : Crig::ImageGenerationResponse(self)
          Crig::ImageGenerationResponse(self).new(Base64.decode(@images.first.image), self)
        end
      end

      struct AudioGenerationResponse
        include JSON::Serializable

        getter audio : String

        def initialize(@audio : String)
        end

        def to_crig_response : Crig::AudioGenerationResponse(self)
          Crig::AudioGenerationResponse(self).new(Base64.decode(@audio), self)
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = HYPERBOLIC_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = HYPERBOLIC_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["HYPERBOLIC_API_KEY"]? || raise "HYPERBOLIC_API_KEY not set"
          new(api_key, HYPERBOLIC_API_BASE_URL)
        end

        def self.from_val(input : Crig::BearerAuth) : self
          new(input.token, HYPERBOLIC_API_BASE_URL)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def image_generation_model(model : String) : ImageGenerationModel
          ImageGenerationModel.new(self, model)
        end

        def audio_generation_model(model : String) : AudioGenerationModel
          AudioGenerationModel.new(self, model)
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          HTTP::Client.exec(
            "POST",
            build_uri(path),
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@api_key.token}",
              "Content-Type"  => "application/json",
              "Accept"        => accept,
            },
            body: body,
          )
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def self.with_model(client : Client, model : String) : self
          new(client, model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.current
          span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "chat")
          span.set_attribute(Crig::Telemetry::GEN_AI_PROVIDER_NAME, "hyperbolic")
          span.set_attribute(Crig::Telemetry::GEN_AI_REQUEST_MODEL, @model)
          if preamble = request.preamble
            span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
          end

          payload = HyperbolicCompletionRequest.from_request(@model, request)
          response = @client.post_json("/v1/chat/completions", payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          completion_response = envelope.ok || raise Crig::Completion::CompletionError.new("Hyperbolic response did not include a success payload")
          result = completion_response.to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = HyperbolicCompletionRequest.from_request(@model, request)
          merged = if params = payload.additional_params
                     JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(params.as_h, JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}})).as_h).to_json)
                   else
                     JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}}))
                   end
          request_payload = HyperbolicCompletionRequest.new(payload.model, payload.messages, payload.temperature, merged)
          response = @client.post_json("/v1/chat/completions", request_payload.to_json, "text/event-stream")
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parse_stream_response(body)
        end

        private def parse_stream_response(text : String) : Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)
          tool_calls = {} of Int32 => {String, String, String}
          usage = Crig::Providers::OpenAI::OpenAIUsage.new

          text.each_line do |line|
            stripped = line.strip
            next unless payload = parse_sse_payload(stripped)
            chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(JSON.parse(payload))
            usage = chunk.usage || usage
            append_stream_chunk(raw_choices, tool_calls, chunk)
          end

          flush_stream_tool_calls(raw_choices, tool_calls)
          raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).final_response(
            Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse.new(usage)
          )
          Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).stream_raw_choices(raw_choices)
        end

        private def parse_sse_payload(line : String) : String?
          return if line.empty? || !line.starts_with?("data:")

          payload = line.lchop("data:").strip
          return if payload == "[DONE]"

          payload
        end

        private def append_stream_chunk(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
          chunk : Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk,
        ) : Nil
          return unless choice = chunk.choices.first?
          if content = choice.delta.content
            raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).message(content) unless content.empty?
          end
          choice.delta.tool_calls.each do |tool_call|
            append_stream_tool_call(raw_choices, tool_calls, tool_call)
          end
        end

        private def append_stream_tool_call(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
          tool_call : Crig::Providers::OpenAI::Chat::Streaming::ToolCall,
        ) : Nil
          if name = tool_call.function.name
            append_named_stream_tool_call(raw_choices, tool_calls, tool_call, name)
          elsif arguments = tool_call.function.arguments
            if existing = tool_calls[tool_call.index]?
              tool_calls[tool_call.index] = {existing[0], existing[1], existing[2] + arguments}
            end
          end
        end

        private def append_named_stream_tool_call(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
          tool_call : Crig::Providers::OpenAI::Chat::Streaming::ToolCall,
          name : String,
        ) : Nil
          if arguments = tool_call.function.arguments
            if arguments.empty?
              tool_calls[tool_call.index] = {tool_call.id || "", name, ""}
            else
              raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).tool_call(
                Crig::RawStreamingToolCall.new(tool_call.id || "", name, parse_json_or_string(arguments))
              )
            end
          else
            tool_calls[tool_call.index] = {tool_call.id || "", name, ""}
          end
        end

        private def flush_stream_tool_calls(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
        ) : Nil
          tool_calls.each_value do |(id, name, arguments)|
            raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(id, name, parse_json_or_string(arguments))
            )
          end
        end

        private def parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON::Any.new(value)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct ImageGenerationModel
        include Crig::ImageGenerationModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def self.with_model(client : Client, model : String) : self
          new(client, model)
        end

        def image_generation_request : Crig::ImageGenerationRequestBuilder
          Crig::ImageGenerationRequestBuilder.new(self)
        end

        def image_generation(request : Crig::ImageGenerationRequest)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model_name", @model
              json.field "prompt", request.prompt
              json.field "height", request.height
              json.field "width", request.width
            end
          end
          payload = if params = request.additional_params
                      JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, params.as_h).to_json)
                    else
                      payload
                    end

          response = @client.post_json("/v1/image/generation", payload.to_json)
          body = response.body
          raise Crig::ImageGenerationError.new("#{response.status_code}: #{body}") if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(ImageGenerationResponse).from_json_value(parsed) { |value| ImageGenerationResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::ImageGenerationError.new(error.message)
          end
          image_response = envelope.ok || raise Crig::ImageGenerationError.new("Hyperbolic image response did not include a success payload")
          image_response.to_crig_response
        end
      end

      struct AudioGenerationModel
        include Crig::AudioGenerationModel

        getter client : Client
        getter language : String

        def initialize(@client : Client, @language : String)
        end

        def self.make(client : Client, language : String) : self
          new(client, language)
        end

        def audio_generation_request : Crig::AudioGenerationRequestBuilder
          Crig::AudioGenerationRequestBuilder.new(self)
        end

        def audio_generation(request : Crig::AudioGenerationRequest)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "language", @language
              json.field "speaker", request.voice
              json.field "text", request.text
              json.field "speed", request.speed
            end
          end

          response = @client.post_json("/v1/audio/generation", payload.to_json)
          body = response.body
          raise Crig::AudioGenerationError.new("#{response.status_code}: #{body}") if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(AudioGenerationResponse).from_json_value(parsed) { |value| AudioGenerationResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::AudioGenerationError.new(error.message)
          end
          audio_response = envelope.ok || raise Crig::AudioGenerationError.new("Hyperbolic audio response did not include a success payload")
          audio_response.to_crig_response
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Hyperbolic::CompletionModel)
        include Crig::ImageGenerationClient(Crig::Providers::Hyperbolic::ImageGenerationModel)
        include Crig::AudioGenerationClient(Crig::Providers::Hyperbolic::AudioGenerationModel)
      end
    end
  end
end
