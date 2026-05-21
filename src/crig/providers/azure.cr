require "base64"
require "http/formdata"

module Crig
  module Providers
    module Azure
      DEFAULT_API_VERSION = "2024-10-21"

      O1                      = "o1"
      O1_PREVIEW              = "o1-preview"
      O1_MINI                 = "o1-mini"
      GPT_4O                  = "gpt-4o"
      GPT_4O_MINI             = "gpt-4o-mini"
      GPT_4O_REALTIME_PREVIEW = "gpt-4o-realtime-preview"
      GPT_4_TURBO             = "gpt-4"
      GPT_4                   = "gpt-4"
      GPT_4_32K               = "gpt-4-32k"
      GPT_4_32K_0613          = "gpt-4-32k"
      GPT_35_TURBO            = "gpt-3.5-turbo"
      GPT_35_TURBO_INSTRUCT   = "gpt-3.5-turbo-instruct"
      GPT_35_TURBO_16K        = "gpt-3.5-turbo-16k"

      TEXT_EMBEDDING_3_LARGE = "text-embedding-3-large"
      TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small"
      TEXT_EMBEDDING_ADA_002 = "text-embedding-ada-002"

      alias Usage = Crig::Providers::OpenAI::OpenAIUsage
      alias EmbeddingData = Crig::Providers::OpenAI::EmbeddingData
      alias ImageGenerationData = Crig::Providers::OpenAI::ImageGenerationData
      alias ImageGenerationResponse = Crig::Providers::OpenAI::ImageGenerationResponse
      alias TranscriptionResponse = Crig::Providers::OpenAI::TranscriptionResponse

      struct AzureExt
        getter endpoint : String
        getter api_version : String

        def initialize(@endpoint : String, @api_version : String = DEFAULT_API_VERSION)
        end
      end

      struct AzureExtBuilder
        getter endpoint : String?
        getter api_version : String

        def initialize(@endpoint : String? = nil, @api_version : String = DEFAULT_API_VERSION)
        end

        def azure_endpoint(endpoint : String) : self
          self.class.new(endpoint, @api_version)
        end

        def api_version(api_version : String) : self
          self.class.new(@endpoint, api_version)
        end
      end

      struct AzureOpenAIClientParams
        getter api_key : String
        getter version : String
        getter header : String

        def initialize(@api_key : String, @version : String, @header : String)
        end
      end

      struct AzureOpenAIAuth
        enum Kind
          ApiKey
          Token
        end

        getter kind : Kind
        getter value : String

        def initialize(@kind : Kind, @value : String)
        end

        def self.api_key(value : String) : self
          new(Kind::ApiKey, value)
        end

        def self.token(value : String) : self
          new(Kind::Token, value)
        end

        def headers : Hash(String, String)
          case @kind
          in .api_key?
            {"api-key" => @value}
          in .token?
            {"Authorization" => "Bearer #{@value}"}
          end
        end
      end

      struct ClientBuilder
        getter auth : AzureOpenAIAuth?
        getter endpoint : String?
        getter api_version : String

        def initialize(
          @auth : AzureOpenAIAuth? = nil,
          @endpoint : String? = nil,
          @api_version : String = DEFAULT_API_VERSION,
        )
        end

        def api_key(auth : AzureOpenAIAuth) : self
          self.class.new(auth, @endpoint, @api_version)
        end

        def api_key(token : String) : self
          api_key(AzureOpenAIAuth.token(token))
        end

        def azure_endpoint(endpoint : String) : self
          self.class.new(@auth, endpoint, @api_version)
        end

        def api_version(api_version : String) : self
          self.class.new(@auth, @endpoint, api_version)
        end

        def build : Client
          auth = @auth || raise "Neither Azure API key nor token is set"
          endpoint = @endpoint || raise "AZURE_ENDPOINT not set"
          Client.new(auth, endpoint, @api_version)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct Client
        getter auth : AzureOpenAIAuth
        getter endpoint : String
        getter api_version : String

        def initialize(@auth : AzureOpenAIAuth, @endpoint : String, @api_version : String = DEFAULT_API_VERSION)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          auth = if api_key = ENV["AZURE_API_KEY"]?
                   AzureOpenAIAuth.api_key(api_key)
                 elsif token = ENV["AZURE_TOKEN"]?
                   AzureOpenAIAuth.token(token)
                 else
                   raise "Neither AZURE_API_KEY nor AZURE_TOKEN is set"
                 end

          api_version = ENV["AZURE_API_VERSION"]? || raise "AZURE_API_VERSION not set"
          endpoint = ENV["AZURE_ENDPOINT"]? || raise "AZURE_ENDPOINT not set"
          new(auth, endpoint, api_version)
        end

        def self.from_val(input : AzureOpenAIClientParams) : self
          new(AzureOpenAIAuth.api_key(input.api_key), input.header, input.version)
        end

        def embedding_model(model : String) : EmbeddingModel
          EmbeddingModel.make(self, model, nil)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.make(self, model, ndims)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def transcription_model(model : String) : TranscriptionModel
          TranscriptionModel.make(self, model)
        end

        def image_generation_model(model : String) : ImageGenerationModel
          ImageGenerationModel.make(self, model)
        end

        def audio_generation_model(model : String) : AudioGenerationModel
          AudioGenerationModel.make(self, model)
        end

        def post_embedding(deployment_id : String, body : String) : HTTP::Client::Response
          post_json(deployment_path(deployment_id, "embeddings"), body)
        end

        def post_chat_completion(deployment_id : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          post_json(deployment_path(deployment_id, "chat/completions"), body, headers)
        end

        def post_transcription(deployment_id : String, body : String, content_type : String) : HTTP::Client::Response
          post(deployment_path(deployment_id, "audio/translations"), body, content_type, "application/json")
        end

        def post_image_generation(deployment_id : String, body : String) : HTTP::Client::Response
          post_json(deployment_path(deployment_id, "images/generations"), body)
        end

        def post_audio_generation(deployment_id : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          post_json(deployment_path(deployment_id, "audio/speech"), body, {"Accept" => "application/octet-stream"}.merge(headers))
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          post(path, body, "application/json", headers["Accept"]? || "application/json", headers)
        end

        private def post(path : String, body : String, content_type : String, accept : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Content-Type" => content_type,
            "Accept"       => accept,
          }
          @auth.headers.each { |key, value| all_headers[key] = value }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", path, headers: all_headers, body: body)
        end

        private def deployment_path(deployment_id : String, suffix : String) : String
          "#{@endpoint.rstrip('/')}/openai/deployments/#{deployment_id.lstrip('/')}/#{suffix}?api-version=#{@api_version}"
        end
      end

      struct EmbeddingResponse
        include JSON::Serializable

        getter object : String
        getter data : Array(EmbeddingData)
        getter model : String
        getter usage : Usage

        def initialize(@object : String, @data : Array(EmbeddingData), @model : String, @usage : Usage)
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32)
        end

        def self.make(client : Client, model : String, ndims : Int32?) : self
          dims = ndims || model_dimensions_from_identifier(model) || 0
          new(client, model, dims)
        end

        def self.with_model(client : Client, model : String, ndims : Int32?) : self
          new(client, model, ndims || 0)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a

          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "input" do
                json.array do
                  documents.each { |document| json.string(document) }
                end
              end
              if @ndims > 0 && @model != TEXT_EMBEDDING_ADA_002
                json.field "dimensions", @ndims
              end
            end
          end

          response = @client.post_embedding(@model, payload.to_json)
          text = response.body
          raise Crig::Embeddings::EmbeddingError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          if error = parsed["message"]?
            raise Crig::Embeddings::EmbeddingError.new(error.as_s)
          end

          embedding_response = EmbeddingResponse.from_json(text)
          if embedding_response.data.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embedding_response.data.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end

        private def self.model_dimensions_from_identifier(identifier : String) : Int32?
          case identifier
          when TEXT_EMBEDDING_3_LARGE
            3072
          when TEXT_EMBEDDING_3_SMALL, TEXT_EMBEDDING_ADA_002
            1536
          end
        end
      end

      struct AzureOpenAICompletionRequest
        getter model : String
        getter messages : Array(Crig::Providers::OpenAI::Chat::Message)
        getter temperature : Float64?
        getter tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition)
        getter tool_choice : JSON::Any?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Crig::Providers::OpenAI::Chat::Message),
          @temperature : Float64? = nil,
          @tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition) = [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
          @tool_choice : JSON::Any? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, request : Crig::Completion::Request::CompletionRequest) : self
          params = Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(default_model, request)
          payload = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(params).to_json_value.as_h
          new(
            payload["model"].as_s,
            payload["messages"].as_a.map { |value| Crig::Providers::OpenAI::Chat::Message.from_json_value(value) },
            payload["temperature"]?.try(&.as_f?),
            payload["tools"]?.try(&.as_a?).try do |values|
              values.map do |value|
                function = value["function"]
                Crig::Providers::OpenAI::Chat::ToolDefinition.new(
                  Crig::Providers::OpenAI::Chat::FunctionDefinition.new(
                    function["name"].as_s,
                    function["description"].as_s,
                    function["parameters"],
                    function["strict"]?.try(&.as_bool?),
                  ),
                  value["type"].as_s,
                )
              end
            end || [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
            payload["tool_choice"]?,
            request.output_schema ? payload.reject { |key, _| {"model", "messages", "temperature", "tools", "tool_choice"}.includes?(key) }.empty? ? nil : JSON.parse(payload.reject { |key, _| {"model", "messages", "temperature", "tools", "tool_choice"}.includes?(key) }.to_json) : request.additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" do
                json.array do
                  @messages.each(&.to_json_value.to_json(json))
                end
              end
              if temperature = @temperature
                json.field "temperature", temperature
              end
              unless @tools.empty?
                json.field "tools" do
                  json.array do
                    @tools.each(&.to_json_value.to_json(json))
                  end
                end
              end
              if tool_choice = @tool_choice
                json.field "tool_choice" do
                  tool_choice.to_json(json)
                end
              end
            end
          end

          if additional_params = @additional_params
            JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
          else
            payload
          end
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

        def completion_request : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.new(self)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.current
          span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "chat")
          span.set_attribute(Crig::Telemetry::GEN_AI_PROVIDER_NAME, "azure")
          span.set_attribute(Crig::Telemetry::GEN_AI_REQUEST_MODEL, @model)
          if preamble = request.preamble
            span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
          end

          payload = AzureOpenAICompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_chat_completion(@model, payload.to_json)
          text = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(text)
          end

          parsed = JSON.parse(text)
          if error = parsed["message"]?
            raise Crig::Completion::CompletionError.new(error.as_s)
          elsif error = parsed["error"]?
            raise Crig::Completion::CompletionError.new(error["message"].as_s)
          end

          result = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(parsed).to_completion_response(parsed)
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = AzureOpenAICompletionRequest.from_request(@model, request).to_json_value.as_h
          payload = OpenAI.merge_json_hashes(
            payload,
            {
              "stream"         => JSON::Any.new(true),
              "stream_options" => JSON.parse(%({"include_usage":true})),
            }
          )
          response = @client.post_chat_completion(@model, payload.to_json, {"Accept" => "text/event-stream"})
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          raw_choices = parse_streaming_choices(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        def with_model(model : String) : self
          self.class.new(@client, model)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        # ameba:disable Metrics/CyclomaticComplexity
        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
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
            final_response = chunk.response || final_response

            chunk.choices.each do |choice|
              delta = choice.delta
              if content = delta.content
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(content)
              end

              delta.tool_calls.each do |tool_call|
                index = tool_call.index
                id = tool_call.id || tool_calls[index]?.try(&.[0]) || ""
                name = tool_call.function.name || tool_calls[index]?.try(&.[1]) || ""
                arguments = tool_call.function.arguments || tool_calls[index]?.try(&.[2]) || ""
                tool_calls[index] = {id, name, arguments}

                if tool_call.function.name
                  raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                    id,
                    id.empty? ? index.to_s : id,
                    Crig::ToolCallDeltaContent.name(name),
                  )
                end

                if tool_call.function.arguments
                  raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                    id,
                    id.empty? ? index.to_s : id,
                    Crig::ToolCallDeltaContent.delta(arguments),
                  )
                end
              end

              if choice.finish_reason.try(&.tool_calls?)
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
            end
          end

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

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(final_response.token_usage)
          )
          raw_choices
        end

        # ameba:enable Metrics/CyclomaticComplexity

        private def parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON::Any.new(value)
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
          form.file("file", IO::Memory.new(request.data), HTTP::FormData::FileMetadata.new(filename: request.filename))
          if prompt = request.prompt
            form.field("prompt", prompt)
          end
          if temperature = request.temperature
            form.field("temperature", temperature.to_s)
          end
          if additional_params = request.additional_params
            additional_params.as_h.each do |key, value|
              form.field(key, value.to_s)
            end
          end
          form.finish

          response = @client.post_transcription(@model, io.to_s, form.content_type)
          text = response.body
          raise Crig::TranscriptionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          if error = parsed["message"]?
            raise Crig::TranscriptionError.new(error.as_s)
          elsif error = parsed["error"]?
            raise Crig::TranscriptionError.new(error["message"].as_s)
          end

          TranscriptionResponse.from_json(text).to_crig_response
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

        def image_generation_request : Crig::ImageGenerationRequestBuilder
          Crig::ImageGenerationRequestBuilder.new(self)
        end

        def image_generation(request : Crig::ImageGenerationRequest)
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "prompt", request.prompt
              json.field "size", "#{request.width}x#{request.height}"
              json.field "response_format", "b64_json"
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_image_generation(@model, merged_payload.to_json)
          text = response.body
          raise Crig::ImageGenerationError.new("#{response.status}: #{text}") unless response.success?

          parsed = JSON.parse(text)
          if error = parsed["message"]?
            raise Crig::ImageGenerationError.new(error.as_s)
          elsif error = parsed["error"]?
            raise Crig::ImageGenerationError.new(error["message"].as_s)
          end

          ImageGenerationResponse.from_json(text).to_crig_response
        end
      end

      struct AudioGenerationModel
        include Crig::AudioGenerationModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def audio_generation_request : Crig::AudioGenerationRequestBuilder
          Crig::AudioGenerationRequestBuilder.new(self)
        end

        def audio_generation(request : Crig::AudioGenerationRequest)
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input", request.text
              json.field "voice", request.voice
              json.field "speed", request.speed
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_audio_generation(@model, merged_payload.to_json)
          raise Crig::AudioGenerationError.new("#{response.status}: #{response.body}") unless response.status_code < 400

          bytes = response.body.to_slice
          Crig::AudioGenerationResponse(Bytes).new(bytes, Bytes.new(bytes.size) { |i| bytes[i] })
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Azure::CompletionModel)
      end
    end
  end
end
