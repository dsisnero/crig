require "http/client"

module Crig
  module Providers
    module Gemini
      GEMINI_API_BASE_URL = "https://generativelanguage.googleapis.com"

      struct GeminiExt
        getter api_key : String

        def initialize(@api_key : String)
        end
      end

      struct GeminiBuilder
      end

      struct GeminiInteractionsExt
        getter api_key : String

        def initialize(@api_key : String)
        end
      end

      struct GeminiInteractionsBuilder
      end

      struct GeminiApiKey
        getter value : String

        def initialize(@value : String)
        end

        def self.from(value : String) : self
          new(value)
        end
      end

      struct ClientBuilder
        getter api_key : GeminiApiKey?
        getter base_url : String

        def initialize(@api_key : GeminiApiKey? = nil, @base_url : String = GEMINI_API_BASE_URL)
        end

        def api_key(value : String | GeminiApiKey) : self
          api_key = value.is_a?(GeminiApiKey) ? value : GeminiApiKey.new(value)
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "GEMINI_API_KEY not set"
          Client.new(api_key.value, @base_url)
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
          if message = value["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct Client
        getter ext : GeminiExt
        getter base_url : String

        def initialize(api_key : String, @base_url : String = GEMINI_API_BASE_URL)
          @ext = GeminiExt.new(api_key)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["GEMINI_API_KEY"]? || raise "GEMINI_API_KEY not set"
          new(api_key)
        end

        def self.from_val(input : GeminiApiKey) : self
          new(input.value)
        end

        def build_uri(path : String, sse : Bool = false) : String
          suffix = sse ? "&alt=sse" : ""
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}?key=#{@ext.api_key}#{suffix}"
        end

        def post_json(path : String, body : String, sse : Bool = false) : HTTP::Client::Response
          headers = HTTP::Headers{
            "Content-Type" => "application/json",
            "Accept"       => sse ? "text/event-stream" : "application/json",
          }
          HTTP::Client.exec("POST", build_uri(path, sse), headers: headers, body: body)
        end

        def get(path : String, sse : Bool = false) : HTTP::Client::Response
          headers = HTTP::Headers{"Accept" => sse ? "text/event-stream" : "application/json"}
          HTTP::Client.get(build_uri(path, sse), headers: headers)
        end

        def interactions_api : InteractionsClient
          InteractionsClient.new(@ext.api_key, @base_url)
        end

        def completion_model(model : String) : Crig::Providers::Gemini::CompletionModel
          Crig::Providers::Gemini::CompletionModel.new(self, model)
        end
      end

      struct InteractionsClient
        getter ext : GeminiInteractionsExt
        getter base_url : String

        def initialize(api_key : String, @base_url : String = GEMINI_API_BASE_URL)
          @ext = GeminiInteractionsExt.new(api_key)
        end

        def self.from_env : self
          api_key = ENV["GEMINI_API_KEY"]? || raise "GEMINI_API_KEY not set"
          new(api_key)
        end

        def self.from_val(input : GeminiApiKey) : self
          new(input.value)
        end

        def build_uri(path : String, sse : Bool = false) : String
          trimmed = path.lstrip('/')
          if sse
            separator = trimmed.includes?('?') ? "&" : "?"
            "#{@base_url.rstrip('/')}/#{trimmed}#{separator}alt=sse"
          else
            "#{@base_url.rstrip('/')}/#{trimmed}"
          end
        end

        def post_json(path : String, body : String, sse : Bool = false) : HTTP::Client::Response
          headers = HTTP::Headers{
            "x-goog-api-key" => @ext.api_key,
            "Content-Type"   => "application/json",
            "Accept"         => sse ? "text/event-stream" : "application/json",
          }
          HTTP::Client.exec("POST", build_uri(path, sse), headers: headers, body: body)
        end

        def get(path : String, sse : Bool = false) : HTTP::Client::Response
          headers = HTTP::Headers{
            "x-goog-api-key" => @ext.api_key,
            "Accept"         => sse ? "text/event-stream" : "application/json",
          }
          HTTP::Client.get(build_uri(path, sse), headers: headers)
        end

        def generate_content_api : Client
          Client.new(@ext.api_key, @base_url)
        end

        def completion_model(model : String) : Crig::Providers::Gemini::Interactions::InteractionsCompletionModel
          Crig::Providers::Gemini::Interactions::InteractionsCompletionModel.new(self, model)
        end

        def create_interaction(request : Crig::Providers::Gemini::Interactions::CreateInteractionRequest) : Crig::Providers::Gemini::Interactions::Interaction
          raise Crig::Completion::CompletionError.new("stream=true requires stream_interaction_events") if request.stream == true
          response = post_json("/v1beta/interactions", request.to_json)
          raise Crig::Completion::CompletionError.new(response.body) if response.status_code >= 400
          Crig::Providers::Gemini::Interactions::Interaction.from_json(response.body)
        end

        def get_interaction(interaction_id : String) : Crig::Providers::Gemini::Interactions::Interaction
          response = get("/v1beta/interactions/#{interaction_id}")
          raise Crig::Completion::CompletionError.new(response.body) if response.status_code >= 400
          Crig::Providers::Gemini::Interactions::Interaction.from_json(response.body)
        end

        def stream_interaction_events(request : Crig::Providers::Gemini::Interactions::CreateInteractionRequest) : Crig::Providers::Gemini::Interactions::Streaming::InteractionEventStream
          response = post_json("/v1beta/interactions", request.to_json, sse: true)
          raise Crig::Completion::CompletionError.new(response.body) if response.status_code >= 400
          Crig::Providers::Gemini::Interactions::Streaming.parse_event_stream(response.body)
        end

        def stream_interaction_events_by_id(interaction_id : String, last_event_id : String? = nil) : Crig::Providers::Gemini::Interactions::Streaming::InteractionEventStream
          response = get(Crig::Providers::Gemini::Interactions.build_interaction_stream_path(interaction_id, last_event_id), sse: true)
          raise Crig::Completion::CompletionError.new(response.body) if response.status_code >= 400
          Crig::Providers::Gemini::Interactions::Streaming.parse_event_stream(response.body)
        end
      end
    end
  end
end
