require "http/client"

module Crig
  module Providers
    module Mira
      MIRA_API_BASE_URL = "https://api.mira.network"

      struct MiraExt
      end

      struct MiraBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = MIRA_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "MIRA_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      enum MiraError
        InvalidApiKey
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct RawMessage
        include JSON::Serializable

        getter role : String
        getter content : String

        def initialize(@role : String, @content : String)
        end

        def to_core_message : Crig::Completion::Message
          case @role
          when "user"
            Crig::Completion::Message.user(@content)
          when "assistant"
            Crig::Completion::Message.assistant(@content)
          else
            raise Crig::Completion::CompletionError.new("Unsupported message role: #{@role}")
          end
        end
      end

      struct ChatChoice
        include JSON::Serializable

        getter message : RawMessage
        getter finish_reason : String?
        getter index : Int32?

        def initialize(@message : RawMessage, @finish_reason : String? = nil, @index : Int32? = nil)
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter prompt_tokens : Int32
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @total_tokens : Int32)
        end

        def token_usage : Crig::Completion::Usage?
          output = @total_tokens - @prompt_tokens
          Crig::Completion::Usage.new(@prompt_tokens.to_i64, output.to_i64, @total_tokens.to_i64, 0_i64)
        end

        def to_s(io : IO) : Nil
          io << "Prompt tokens: " << @prompt_tokens << " Total tokens: " << @total_tokens
        end
      end

      struct CompletionResponse
        enum Kind
          Structured
          Simple
        end

        getter kind : Kind
        getter id : String?
        getter object : String?
        getter created : Int64?
        getter model : String?
        getter choices : Array(ChatChoice)?
        getter usage : Usage?
        getter text : String?

        def initialize(
          @kind : Kind,
          @id : String? = nil,
          @object : String? = nil,
          @created : Int64? = nil,
          @model : String? = nil,
          @choices : Array(ChatChoice)? = nil,
          @usage : Usage? = nil,
          @text : String? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          if text = value.as_s?
            return new(Kind::Simple, text: text)
          end

          hash = value.as_h
          new(
            Kind::Structured,
            id: hash["id"].as_s,
            object: hash["object"].as_s,
            created: hash["created"].as_i64,
            model: hash["model"].as_s,
            choices: hash["choices"].as_a.map { |entry| ChatChoice.from_json(entry.to_json) },
            usage: hash["usage"]?.try { |entry| Usage.from_json(entry.to_json) },
          )
        end

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          case @kind
          in .simple?
            content = @text || raise Crig::Completion::CompletionError.new("Response contained no text")
            Crig::Completion::CompletionResponse(self).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(content)),
              Crig::Completion::Usage.new,
              self,
            )
          in .structured?
            choice = @choices.try(&.first?) || raise Crig::Completion::CompletionError.new("Response contained no choices")
            message = choice.message.to_core_message
            assistant = message.content.map do |item|
              content = item.as?(Crig::Completion::AssistantContent) || raise Crig::Completion::CompletionError.new("Received user message in response where assistant message was expected")
              if content.kind.text?
                Crig::Completion::AssistantContent.text(content.text.try(&.text) || "")
              else
                raise Crig::Completion::CompletionError.new("Unsupported content type encountered in Mira response")
              end
            end
            built = Crig::OneOrMany(Crig::Completion::AssistantContent).many(assistant)
            Crig::Completion::CompletionResponse(self).new(
              built,
              @usage.try(&.token_usage) || Crig::Completion::Usage.new,
              self,
            )
          end
        end
      end

      struct MiraCompletionRequest
        getter model : String
        getter messages : Array(RawMessage)
        getter temperature : Float64?
        getter max_tokens : Int64?
        getter? stream : Bool

        def initialize(
          @model : String,
          @messages : Array(RawMessage),
          @temperature : Float64? = nil,
          @max_tokens : Int64? = nil,
          @stream : Bool = false,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest, stream : Bool = false) : self
          model = req.model || default_model
          messages = [] of RawMessage

          if preamble = req.preamble
            messages << RawMessage.new("user", preamble)
          end

          if documents = req.normalized_documents
            text = documents.content
              .map do |content|
                user_content = content.as(Crig::Completion::UserContent)
                case user_content.kind
                in .document?
                  document = user_content.document.as(Crig::Completion::Document)
                  case document.data.kind
                  in .base64?, .string?
                    document.data.string_value || ""
                  in .url?, .raw?, .file_id?, .unknown?
                    ""
                  end
                in .text?
                  user_content.text.try(&.text) || ""
                in .image?, .audio?, .video?, .tool_result?
                  ""
                end
              end
              .reject(&.empty?)
              .join('\n')
            messages << RawMessage.new("user", text) unless text.empty?
          end

          req.chat_history.each do |message|
            messages << raw_message_from_core(message)
          end

          new(model, messages, req.temperature, req.max_tokens, stream)
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" do
                json.array do
                  @messages.each do |message|
                    json.object do
                      json.field "role", message.role
                      json.field "content", message.content
                    end
                  end
                end
              end
              json.field "temperature", @temperature unless @temperature.nil?
              json.field "max_tokens", @max_tokens unless @max_tokens.nil?
              json.field "stream", @stream
            end
          end
        end

        private def self.raw_message_from_core(message : Crig::Completion::Message) : RawMessage
          case message.role
          in .user?
            text = message.content.map do |content|
              user = content.as(Crig::Completion::UserContent)
              user.kind.text? ? (user.text.try(&.text) || "") : ""
            end.join('\n')
            RawMessage.new("user", text)
          in .assistant?
            text = message.content.map do |content|
              assistant = content.as(Crig::Completion::AssistantContent)
              assistant.kind.text? ? (assistant.text.try(&.text) || "") : ""
            end.join('\n')
            RawMessage.new("assistant", text)
          in .system?
            text = message.content.map do |content|
              user = content.as(Crig::Completion::UserContent)
              user.kind.text? ? (user.text.try(&.text) || "") : ""
            end.join('\n')
            RawMessage.new("system", text)
          end
        end
      end

      struct StreamingDelta
        getter role : String?
        getter content : String?

        def initialize(@role : String? = nil, @content : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["role"]?.try(&.as_s?), hash["content"]?.try(&.as_s?))
        end
      end

      struct StreamingChoice
        getter index : Int32
        getter delta : StreamingDelta
        getter finish_reason : String?

        def initialize(@index : Int32, @delta : StreamingDelta, @finish_reason : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"].as_i,
            StreamingDelta.from_json_value(hash["delta"]),
            hash["finish_reason"]?.try(&.as_s?),
          )
        end
      end

      struct StreamingCompletionChunk
        getter id : String
        getter model : String
        getter choices : Array(StreamingChoice)
        getter usage : Usage?

        def initialize(@id : String, @model : String, @choices : Array(StreamingChoice), @usage : Usage? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            hash["model"].as_s,
            hash["choices"].as_a.map { |entry| StreamingChoice.from_json_value(entry) },
            hash["usage"]?.try { |entry| Usage.from_json(entry.to_json) },
          )
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = MIRA_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = MIRA_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["MIRA_API_KEY"]? || raise "MIRA_API_KEY not set"
          new(api_key, MIRA_API_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, MIRA_API_BASE_URL)
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

        def get(path : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Accept"        => headers["Accept"]? || "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("GET", build_uri(path), headers: all_headers)
        end

        def list_models : Array(String)
          response = get("/v1/models")
          body = response.body
          raise Crig::Completion::CompletionError.new("API error: #{response.status_code} - #{body}") if response.status_code >= 400
          parsed = JSON.parse(body)
          parsed["data"].as_a.map(&.["id"].as_s)
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
          span = Crig::Span.chat_span("mira", @model, request.preamble, nil)

          payload = MiraCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/v1/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new("API error: #{response.status_code} - #{text}") if response.status_code >= 400

          parsed = CompletionResponse.from_json_value(JSON.parse(text))
          result = parsed.to_crig_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = MiraCompletionRequest.from_request(@model, request, true).to_json_value
          response = @client.post_json("/v1/chat/completions", payload.to_json, {"Accept" => "text/event-stream"})
          text = response.body
          raise Crig::Completion::CompletionError.new("API error: #{response.status_code} - #{text}") if response.status_code >= 400

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

        private struct StreamingProfile
          def normalize_chunk(data : String) : Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Usage)?
            json = JSON.parse(data)
            chunk = StreamingCompletionChunk.from_json_value(json)

            choice = chunk.choices.first?
            Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Usage).new(
              response_id: chunk.id,
              choice: choice ? Crig::Providers::Internal::OpenAICompatible::CompatibleChoice.new(
                text: choice.delta.content,
              ) : nil,
              usage: chunk.usage,
            )
          end

          def build_final_response(usage : Usage?) : Crig::Client::FinalCompletionResponse
            Crig::Client::FinalCompletionResponse.new(usage.try(&.token_usage))
          end

          def should_evict(
            existing : Crig::RawStreamingToolCall,
            incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk,
          ) : Bool
            false
          end

          def should_emit_completed_tool_call_immediately(
            tool_call : Crig::RawStreamingToolCall,
            incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk,
          ) : Bool
            false
          end
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Mira::CompletionModel)
      end
    end
  end
end
