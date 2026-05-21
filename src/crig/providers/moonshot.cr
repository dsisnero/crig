require "http/client"

module Crig
  module Providers
    module Moonshot
      MOONSHOT_API_BASE_URL             = "https://api.moonshot.cn/v1"
      MOONSHOT_GLOBAL_API_BASE_URL      = "https://api.moonshot.ai/v1"
      MOONSHOT_ANTHROPIC_BASE_URL       = "https://api.moonshot.ai/anthropic"
      MOONSHOT_CHINA_ANTHROPIC_BASE_URL = "https://api.moonshot.cn/anthropic"

      MOONSHOT_CHAT = "moonshot-v1-128k"
      KIMI_K2       = "kimi-k2"
      KIMI_K2_5     = "kimi-k2.5"

      struct MoonshotExt
      end

      struct MoonshotBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = MOONSHOT_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def global : self
          base_url(MOONSHOT_GLOBAL_API_BASE_URL)
        end

        def china : self
          base_url(MOONSHOT_API_BASE_URL)
        end

        def build : Client
          key = @api_key || raise "MOONSHOT_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      struct MoonshotError
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter error : MoonshotError

        def initialize(@error : MoonshotError)
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if error = value.as_h["error"]?
            new(error: ApiErrorResponse.from_json(error.to_json))
          else
            new(ok: yield value)
          end
        end
      end

      enum ToolChoice
        None
        Auto

        def to_wire : String
          to_s.downcase
        end

        def self.from_core(value : Crig::Completion::ToolChoice) : self
          case value.kind
          in .none?
            None
          in .auto?, .required?
            Auto
          in .specific?
            raise Crig::Completion::CompletionError.new("Unsupported tool choice type: #{value.kind}")
          end
        end
      end

      struct MoonshotCompletionRequest
        getter model : String
        getter messages : Array(Crig::Providers::OpenAI::Chat::Message)
        getter temperature : Float64?
        getter tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition)
        getter max_tokens : Int64?
        getter tool_choice : ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Crig::Providers::OpenAI::Chat::Message),
          @temperature : Float64? = nil,
          @tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition) = [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
          @max_tokens : Int64? = nil,
          @tool_choice : ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          model = req.model || default_model
          partial_history = [] of Crig::Completion::Message
          if docs = req.normalized_documents
            partial_history << docs
          end
          partial_history.concat(req.chat_history.to_a)

          full_history = [] of Crig::Providers::OpenAI::Chat::Message
          if preamble = req.preamble
            full_history << Crig::Providers::OpenAI::Chat::Message.system(preamble)
          end

          tool_choice_required = false

          partial_history.each do |message|
            Crig::Providers::OpenAI::Chat::Message.from_core_message(message).each do |item|
              full_history << item
            end
          end

          tool_choice_val = req.tool_choice.try do |choice|
            if choice.kind.required?
              tool_choice_required = true
              ToolChoice::Auto
            else
              ToolChoice.from_core(choice)
            end
          end

          if tool_choice_required && !req.tools.empty?
            steering = Crig::Providers::OpenAI::Chat::Message.system(
              "Moonshot does not support tool_choice=required; coercing to auto with an additional steering message"
            )
            full_history.unshift(steering)
          end

          new(
            model,
            full_history,
            req.temperature,
            req.tools.map { |tool| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(tool) },
            req.max_tokens,
            tool_choice_val,
            req.additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = Crig::Providers::OpenAI.build_json_any do |json|
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
              json.field "max_tokens", @max_tokens unless @max_tokens.nil?
              json.field "tool_choice", @tool_choice.try(&.to_wire) if @tool_choice
            end
          end

          if additional_params = @additional_params
            JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
          else
            payload
          end
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = MOONSHOT_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = MOONSHOT_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["MOONSHOT_API_KEY"]? || raise "MOONSHOT_API_KEY not set"
          new(api_key, MOONSHOT_API_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, MOONSHOT_API_BASE_URL)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => headers["Accept"]? || "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
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

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.chat_span("moonshot", @model, request.preamble, nil)

          payload = MoonshotCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(Crig::Providers::OpenAI::Chat::CompletionResponse).from_json_value(parsed) do |value|
            Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(value)
          end
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("Moonshot response did not include a success payload")
          result = response_body.to_completion_response(parsed)
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          request_payload = MoonshotCompletionRequest.from_request(@model, request)
          params = request_payload.additional_params || JSON.parse(%({}))
          merged = JSON.parse(
            Crig::Providers::OpenAI.merge_json_hashes(
              params.as_h,
              JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}})).as_h
            ).to_json
          )
          payload = MoonshotCompletionRequest.new(
            request_payload.model,
            request_payload.messages,
            request_payload.temperature,
            request_payload.tools,
            request_payload.max_tokens,
            request_payload.tool_choice,
            merged,
          ).to_json_value

          response = @client.post_json("/chat/completions", payload.to_json, {"Accept" => "text/event-stream"})
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          profile = StreamingProfile.new
          items, final_usage = Crig::Providers::Internal::OpenAICompatible.process_compatible_sse_stream(
            text, profile
          )
          raw_choices = items.map { |item| Crig::Providers::Internal::OpenAICompatible.convert_to_raw_choice(item, Crig::Client::FinalCompletionResponse) }
          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            profile.build_final_response(final_usage)
          )
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        private struct StreamingProfile
          def normalize_chunk(data : String) : Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Crig::Providers::OpenAI::OpenAIUsage)?
            json = JSON.parse(data)
            chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(json)

            choice = chunk.choices.first?
            tool_call_chunks = choice.try(&.delta.tool_calls).try(&.map { |tc|
              Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
                tc.index, tc.id, tc.function.name, tc.function.arguments,
              )
            }) || [] of Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk

            compat_choice = Crig::Providers::Internal::OpenAICompatible::CompatibleChoice.new(
              text: choice.try(&.delta.content),
              tool_calls: tool_call_chunks,
            )

            Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Crig::Providers::OpenAI::OpenAIUsage).new(
              response_id: json["id"]?.try(&.as_s?),
              choice: compat_choice,
              usage: chunk.usage,
            )
          end

          def build_final_response(usage : Crig::Providers::OpenAI::OpenAIUsage?) : Crig::Client::FinalCompletionResponse
            Crig::Client::FinalCompletionResponse.new(usage.try(&.token_usage))
          end

          def should_evict(existing : Crig::RawStreamingToolCall, incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk) : Bool
            false
          end

          def should_emit_completed_tool_call_immediately(tool_call : Crig::RawStreamingToolCall, incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk) : Bool
            false
          end
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Moonshot::CompletionModel)
      end

      struct MoonshotAnthropicExt
      end

      struct MoonshotAnthropicBuilder
        property anthropic_version : String = Crig::Providers::Anthropic::ANTHROPIC_VERSION_LATEST
        property anthropic_betas : Array(String) = [] of String
      end

      struct AnthropicClientBuilder
        getter api_key : String
        getter base_url : String
        getter anthropic_version : String
        getter anthropic_betas : Array(String)

        def initialize(
          @api_key : String,
          @base_url : String = MOONSHOT_ANTHROPIC_BASE_URL,
          @anthropic_version : String = Crig::Providers::Anthropic::ANTHROPIC_VERSION_LATEST,
          @anthropic_betas : Array(String) = [] of String,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url, @anthropic_version, @anthropic_betas)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url, @anthropic_version, @anthropic_betas)
        end

        def global : self
          base_url(MOONSHOT_ANTHROPIC_BASE_URL)
        end

        def china : self
          base_url(MOONSHOT_CHINA_ANTHROPIC_BASE_URL)
        end

        def anthropic_version(version : String) : self
          self.class.new(@api_key, @base_url, version, @anthropic_betas)
        end

        def anthropic_beta(beta : String) : self
          self.class.new(@api_key, @base_url, @anthropic_version, @anthropic_betas + [beta])
        end

        def anthropic_betas(betas : Array(String)) : self
          self.class.new(@api_key, @base_url, @anthropic_version, @anthropic_betas + betas)
        end

        def build : AnthropicClient
          AnthropicClient.new(@api_key, @base_url, @anthropic_version, @anthropic_betas)
        end
      end

      struct AnthropicClient
        include Crig::CompletionClient(Crig::Providers::Anthropic::CompletionModel)

        getter inner : Crig::Providers::Anthropic::Client

        def initialize(api_key : String, base_url : String, anthropic_version : String, anthropic_betas : Array(String))
          @inner = Crig::Providers::Anthropic::Client.new(
            api_key: api_key,
            base_url: Anthropic.normalize_anthropic_base_url(base_url),
            anthropic_version: anthropic_version,
            anthropic_betas: anthropic_betas,
          )
        end

        def self.builder : AnthropicClientBuilder
          raise "Use AnthropicClient.builder(api_key) instead"
        end

        def self.from_env : self
          api_key = ENV["MOONSHOT_API_KEY"]? || raise "MOONSHOT_API_KEY not set"
          builder = AnthropicClientBuilder.new(api_key)

          if primary = ENV["MOONSHOT_ANTHROPIC_API_BASE"]?
            builder = builder.base_url(primary)
          elsif fallback = ENV["MOONSHOT_API_BASE"]?
            if normalized = Moonshot.normalize_anthropic_base_url(fallback)
              builder = builder.base_url(normalized)
            end
          end

          builder.build
        end

        def self.from_val(input : String) : self
          AnthropicClientBuilder.new(input).build
        end

        def completion_model(model : String) : Crig::Providers::Anthropic::CompletionModel
          @inner.completion_model(model)
        end

        delegate agent, to: @inner
        delegate extractor, to: @inner
      end

      def self.normalize_anthropic_base_url(base_url : String) : String?
        if base_url.includes?("/anthropic")
          return base_url
        end
        normalized = base_url.rstrip('/')
        if normalized.ends_with?("/v1")
          normalized[0...-"/v1".size] + "/anthropic"
        end
      end

      def self.resolve_anthropic_base_override(primary : String?, fallback : String?) : String?
        if primary
          primary
        elsif fallback
          normalize_anthropic_base_url(fallback)
        end
      end

      def self.anthropic_beta : AnthropicClientBuilder | Crig::Nothing
        raise "Use AnthropicClientBuilder#anthropic_beta on an Anthropic client builder"
      end

      def self.anthropic_betas : AnthropicClientBuilder | Crig::Nothing
        raise "Use AnthropicClientBuilder#anthropic_betas on an Anthropic client builder"
      end

      def self.anthropic_version : AnthropicClientBuilder | Crig::Nothing
        raise "Use AnthropicClientBuilder#anthropic_version on an Anthropic client builder"
      end
    end
  end
end
