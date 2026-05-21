require "http/client"
require "http/formdata"

module Crig
  module Providers
    module Groq
      GROQ_API_BASE_URL = "https://api.groq.com/openai/v1"

      DEEPSEEK_R1_DISTILL_LLAMA_70B = "deepseek-r1-distill-llama-70b"
      GEMMA2_9B_IT                  = "gemma2-9b-it"
      LLAMA_3_1_8B_INSTANT          = "llama-3.1-8b-instant"
      LLAMA_3_2_11B_VISION_PREVIEW  = "llama-3.2-11b-vision-preview"
      LLAMA_3_2_1B_PREVIEW          = "llama-3.2-1b-preview"
      LLAMA_3_2_3B_PREVIEW          = "llama-3.2-3b-preview"
      LLAMA_3_2_90B_VISION_PREVIEW  = "llama-3.2-90b-vision-preview"
      LLAMA_3_2_70B_SPECDEC         = "llama-3.2-70b-specdec"
      LLAMA_3_2_70B_VERSATILE       = "llama-3.2-70b-versatile"
      LLAMA_GUARD_3_8B              = "llama-guard-3-8b"
      LLAMA_3_70B_8192              = "llama3-70b-8192"
      LLAMA_3_8B_8192               = "llama3-8b-8192"
      MIXTRAL_8X7B_32768            = "mixtral-8x7b-32768"
      WHISPER_LARGE_V3              = "whisper-large-v3"
      WHISPER_LARGE_V3_TURBO        = "whisper-large-v3-turbo"
      DISTIL_WHISPER_LARGE_V3_EN    = "distil-whisper-large-v3-en"

      struct GroqExt
      end

      struct GroqBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = GROQ_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "GROQ_API_KEY not set"
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

      enum ReasoningFormat
        Parsed
        Raw
        Hidden

        def to_json(json : JSON::Builder) : Nil
          json.string(to_s.downcase)
        end
      end

      struct GroqAdditionalParameters
        getter reasoning_format : ReasoningFormat?
        getter include_reasoning : Bool?
        getter extra : Hash(String, JSON::Any)?

        def initialize(
          @reasoning_format : ReasoningFormat? = nil,
          @include_reasoning : Bool? = nil,
          @extra : Hash(String, JSON::Any)? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          object = value.as_h
          extra = object.dup
          reasoning_format = case raw = extra.delete("reasoning_format").try(&.as_s?)
                             when "parsed" then ReasoningFormat::Parsed
                             when "raw"    then ReasoningFormat::Raw
                             when "hidden" then ReasoningFormat::Hidden
                             when nil      then nil
                             else
                               raise Crig::Completion::CompletionError.new("Unsupported Groq reasoning format: #{raw}")
                             end
          include_reasoning = extra.delete("include_reasoning").try(&.as_bool?)
          new(reasoning_format, include_reasoning, extra.empty? ? nil : extra)
        end

        def write_fields(json : JSON::Builder) : Nil
          json.field "reasoning_format", @reasoning_format unless @reasoning_format.nil?
          json.field "include_reasoning", @include_reasoning unless @include_reasoning.nil?
          if extra = @extra
            extra.each do |key, value|
              json.field key, value
            end
          end
        end
      end

      struct StreamOptions
        getter? include_usage : Bool

        def initialize(@include_usage : Bool = false)
        end

        def include_usage : Bool
          @include_usage
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "include_usage", @include_usage
          end
        end
      end

      struct GroqCompletionRequest
        getter model : String
        getter messages : Array(Crig::Providers::OpenAI::Chat::Message)
        getter temperature : Float64?
        getter tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition)
        getter tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice?
        getter additional_params : GroqAdditionalParameters?
        getter? stream : Bool
        getter stream_options : StreamOptions?

        def initialize(
          @model : String,
          @messages : Array(Crig::Providers::OpenAI::Chat::Message),
          @temperature : Float64? = nil,
          @tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition) = [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
          @tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice? = nil,
          @additional_params : GroqAdditionalParameters? = nil,
          @stream : Bool = false,
          @stream_options : StreamOptions? = nil,
        )
        end

        def stream : Bool
          @stream
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          if req.output_schema
            # Rust warns here; Crystal has no logger contract, so preserve behavior by ignoring the schema.
          end

          params = Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(
            req.model || default_model,
            req,
          )
          messages = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(params).messages

          tool_choice = req.tool_choice.try do |choice|
            case choice.kind
            in .auto?     then Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            in .none?     then Crig::Providers::OpenAI::Chat::ToolChoice::None
            in .required? then Crig::Providers::OpenAI::Chat::ToolChoice::Required
            in .specific?
              raise Crig::Completion::CompletionError.new("Groq does not support specific function tool choice")
            end
          end

          additional_params = req.additional_params.try do |value|
            GroqAdditionalParameters.from_json_value(value)
          end

          new(
            req.model || default_model,
            messages,
            req.temperature,
            req.tools.map { |tool| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(tool) },
            tool_choice,
            additional_params,
            false,
            nil,
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "model", @model
            json.field "messages" do
              json.array do
                @messages.each(&.to_json_value.to_json(json))
              end
            end
            json.field "temperature", @temperature unless @temperature.nil?
            unless @tools.empty?
              json.field "tools" do
                json.array do
                  @tools.each(&.to_json_value.to_json(json))
                end
              end
            end
            json.field "tool_choice", @tool_choice.try(&.to_wire) unless @tool_choice.nil?
            @additional_params.try(&.write_fields(json))
            json.field "stream", @stream
            if stream_options = @stream_options
              json.field "stream_options" { stream_options.to_json(json) }
            end
          end
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = GROQ_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = GROQ_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["GROQ_API_KEY"]? || raise "GROQ_API_KEY not set"
          new(api_key, GROQ_API_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, GROQ_API_BASE_URL)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def transcription_model(model : String) : TranscriptionModel
          TranscriptionModel.new(self, model)
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

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : Crig::Providers::OpenAI::OpenAIUsage

        def initialize(@usage : Crig::Providers::OpenAI::OpenAIUsage)
        end

        def token_usage : Crig::Completion::Usage?
          @usage.to_crig_usage
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

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.current
          span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "chat")
          span.set_attribute(Crig::Telemetry::GEN_AI_PROVIDER_NAME, "groq")
          span.set_attribute(Crig::Telemetry::GEN_AI_REQUEST_MODEL, @model)
          if preamble = request.preamble
            span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
          end

          payload = GroqCompletionRequest.from_request(@model, request)
          response = @client.post_json("/chat/completions", payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(Crig::Providers::OpenAI::Chat::CompletionResponse).from_json_value(parsed) do |value|
            Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(value)
          end
          if error = envelope.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          completion_response = envelope.ok || raise Crig::Completion::CompletionError.new("Groq response did not include a success payload")
          result = completion_response.to_completion_response(parsed)
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          base = GroqCompletionRequest.from_request(@model, request)
          payload = GroqCompletionRequest.new(
            base.model,
            base.messages,
            base.temperature,
            base.tools,
            base.tool_choice,
            base.additional_params,
            true,
            StreamOptions.new(true),
          )
          response = @client.post_json("/chat/completions", payload.to_json, "text/event-stream")
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(parse_streaming_choices(body))
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          calls = {} of Int32 => {String, String, String}
          final_usage = Crig::Providers::OpenAI::OpenAIUsage.new

          text.each_line do |line|
            stripped = line.strip
            next if stripped.empty? || !stripped.starts_with?("data:")
            payload = stripped.lchop("data:").strip
            next if payload == "[DONE]"

            parsed = JSON.parse(payload)
            if usage = parsed["usage"]?
              final_usage = Crig::Providers::OpenAI::OpenAIUsage.from_json(usage.to_json)
            end

            choice = parsed["choices"]?.try(&.as_a?.try(&.first?))
            next unless choice
            delta = choice["delta"]?.try(&.as_h?) || next

            if reasoning = delta["reasoning"]?.try(&.as_s?)
              raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, reasoning)
            end

            if content = delta["content"]?.try(&.as_s?)
              raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(content) unless content.empty?
            end

            tool_calls = delta["tool_calls"]?.try(&.as_a?) || [] of JSON::Any
            tool_calls.each do |entry|
              append_streaming_tool_call(raw_choices, calls, entry)
            end
          end

          calls.each_value do |(id, name, arguments)|
            parsed_arguments = parse_json_or_string(arguments)
            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(id, name, parsed_arguments)
            )
          end

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
            StreamingCompletionResponse.new(final_usage)
          )
          raw_choices
        end

        private def append_streaming_tool_call(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          calls : Hash(Int32, {String, String, String}),
          entry : JSON::Any,
        ) : Nil
          hash = entry.as_h
          index = hash["index"]?.try(&.as_i?) || 0
          id = hash["id"]?.try(&.as_s?) || ""
          function = hash["function"]?.try(&.as_h?) || {} of String => JSON::Any
          name = function["name"]?.try(&.as_s?) || ""
          arguments = function["arguments"]?.try(&.as_s?) || ""

          if !name.empty? && arguments.empty?
            calls[index] = {id, name, ""}
            return
          end

          if name.empty? && !arguments.empty?
            if existing = calls[index]?
              calls[index] = {existing[0], existing[1], existing[2] + arguments}
            end
            return
          end

          parsed_arguments = parse_json_or_string(arguments)
          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
            Crig::RawStreamingToolCall.new(id, name, parsed_arguments)
          )
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

      struct TranscriptionModel
        include Crig::TranscriptionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def transcription_request : Crig::TranscriptionRequestBuilder
          Crig::TranscriptionRequestBuilder.new(self)
        end

        def transcription(request : Crig::TranscriptionRequest)
          io = IO::Memory.new
          form = HTTP::FormData::Builder.new(io)
          form.field("model", @model)
          form.file("file", IO::Memory.new(request.data), HTTP::FormData::FileMetadata.new(filename: request.filename))
          form.field("language", request.language) if request.language
          form.field("prompt", request.prompt) if request.prompt
          form.field("temperature", request.temperature.to_s) if request.temperature
          if additional_params = request.additional_params
            additional_params.as_h.each do |key, value|
              form.field(key, value.to_s)
            end
          end
          form.finish

          response = HTTP::Client.exec(
            "POST",
            @client.build_uri("/audio/transcriptions"),
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@client.api_key.token}",
              "Content-Type"  => form.content_type,
              "Accept"        => "application/json",
            },
            body: io.to_s,
          )
          body = response.body
          raise Crig::TranscriptionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          if message = parsed["message"]?.try(&.as_s?)
            raise Crig::TranscriptionError.new(message)
          end

          response_body = Crig::Providers::OpenAI::TranscriptionResponse.from_json(body)
          response_body.to_crig_response
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Groq::CompletionModel)
        include Crig::TranscriptionClient(Crig::Providers::Groq::TranscriptionModel)
      end
    end
  end
end
