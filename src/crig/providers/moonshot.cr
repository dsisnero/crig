require "http/client"

module Crig
  module Providers
    module Moonshot
      MOONSHOT_API_BASE_URL        = "https://api.moonshot.cn/v1"
      MOONSHOT_GLOBAL_API_BASE_URL = "https://api.moonshot.ai/v1"
      MOONSHOT_ANTHROPIC_BASE_URL  = "https://api.moonshot.ai/anthropic"

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
          in .auto?
            Auto
          in .required?, .specific?
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
          partial_history.each do |message|
            Crig::Providers::OpenAI::Chat::Message.from_core_message(message).each do |item|
              full_history << item
            end
          end

          new(
            model,
            full_history,
            req.temperature,
            req.tools.map { |tool| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(tool) },
            req.max_tokens,
            req.tool_choice.try { |choice| ToolChoice.from_core(choice) },
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
          response_body.to_completion_response(parsed)
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

          raw_choices, final_usage = parse_streaming_choices(text)

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(final_usage)
          )
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        private def parse_streaming_choices(text : String) : {Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)), Crig::Completion::Usage?}
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          tool_calls = {} of Int32 => {String, String, String}
          final_response = Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse.new
          message_id : String? = nil

          text.each_line do |line|
            next unless line.starts_with?("data:")
            data = line.lchop("data:").strip
            next if data.empty? || data == "[DONE]"

            chunk_json = JSON.parse(data)
            if id = chunk_json["id"]?.try(&.as_s?)
              unless message_id
                message_id = id
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message_id(id)
              end
            end

            chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(chunk_json)
            if usage = chunk.usage
              final_response = Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse.new(usage)
            end

            choice = chunk.choices.first?
            next unless choice
            append_content_delta(raw_choices, choice.delta.content)
            append_tool_call_deltas(raw_choices, tool_calls, choice.delta.tool_calls)
          end

          append_final_tool_calls(raw_choices, tool_calls)
          {raw_choices, final_response.token_usage}
        end

        private def append_content_delta(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)),
          content : String?,
        ) : Nil
          return if content.nil? || content.empty?
          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(content)
        end

        private def append_tool_call_deltas(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
          deltas : Array(Crig::Providers::OpenAI::Chat::Streaming::ToolCall),
        ) : Nil
          deltas.each do |tool_call|
            existing = tool_calls[tool_call.index]?
            id = tool_call.id || existing.try(&.[0]) || ""
            name = tool_call.function.name || existing.try(&.[1]) || ""
            arguments_delta = tool_call.function.arguments || ""
            combined_arguments = (existing.try(&.[2]) || "") + arguments_delta
            tool_calls[tool_call.index] = {id, name, combined_arguments}

            if incoming_name = tool_call.function.name
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                id,
                id.empty? ? tool_call.index.to_s : id,
                Crig::ToolCallDeltaContent.name(incoming_name),
              )
            end
            unless arguments_delta.empty?
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                id,
                id.empty? ? tool_call.index.to_s : id,
                Crig::ToolCallDeltaContent.delta(arguments_delta),
              )
            end
          end
        end

        private def append_final_tool_calls(
          raw_choices : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)),
          tool_calls : Hash(Int32, {String, String, String}),
        ) : Nil
          tool_calls.keys.sort!.each do |index|
            id, name, arguments = tool_calls[index]
            raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(
                id,
                name,
                parse_json_or_string(arguments),
                id.empty? ? index.to_s : id,
              )
            )
          end
        end

        private def parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON.parse(value.to_json)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Moonshot::CompletionModel)
      end
    end
  end
end
