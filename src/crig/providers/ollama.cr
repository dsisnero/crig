require "http/client"

module Crig
  module Providers
    module Ollama
      OLLAMA_API_BASE_URL = "http://localhost:11434"

      ALL_MINILM       = "all-minilm"
      NOMIC_EMBED_TEXT = "nomic-embed-text"
      LLAMA3_2         = "llama3.2"
      LLAVA            = "llava"
      MISTRAL          = "mistral"

      struct OllamaExt
      end

      struct OllamaBuilder
      end

      def self.model_dimensions_from_identifier(identifier : String) : Int32?
        case identifier
        when ALL_MINILM       then 384
        when NOMIC_EMBED_TEXT then 768
        end
      end

      struct ClientBuilder
        getter api_key : Crig::Nothing
        getter base_url : String

        def initialize(@api_key : Crig::Nothing = Crig::Nothing.new, @base_url : String = OLLAMA_API_BASE_URL)
        end

        def api_key(api_key : Crig::Nothing) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          Client.new(@api_key, @base_url)
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

      struct EmbeddingResponse
        include JSON::Serializable

        getter model : String
        getter embeddings : Array(Array(Float64))
        getter total_duration : Int64?
        getter load_duration : Int64?
        getter prompt_eval_count : Int64?

        def initialize(
          @model : String,
          @embeddings : Array(Array(Float64)),
          @total_duration : Int64? = nil,
          @load_duration : Int64? = nil,
          @prompt_eval_count : Int64? = nil,
        )
        end
      end

      struct Client
        getter api_key : Crig::Nothing
        getter base_url : String

        def initialize(@api_key : Crig::Nothing = Crig::Nothing.new, @base_url : String = OLLAMA_API_BASE_URL)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          base_url = ENV["OLLAMA_API_BASE_URL"]? || raise "OLLAMA_API_BASE_URL not set"
          new(Crig::Nothing.new, base_url)
        end

        def self.from_val(input : Crig::Nothing) : self
          new(input, OLLAMA_API_BASE_URL)
        end

        def embedding_model(model : String, ndims : Int32? = nil) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims || Ollama.model_dimensions_from_identifier(model) || 0)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def post_json(path : String, body : String) : HTTP::Client::Response
          headers = HTTP::Headers{
            "Content-Type" => "application/json",
            "Accept"       => "application/json",
          }
          HTTP::Client.exec("POST", build_uri(path), headers: headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
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

        def self.make(client : Client, model : String, dims : Int32? = nil) : self
          new(client, model, dims || Ollama.model_dimensions_from_identifier(model) || 0)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array do
                  documents.each { |document| json.string(document) }
                end
              end
            end
          end

          response = @client.post_json("/api/embed", payload.to_json)
          body = response.body
          raise Crig::Embeddings::EmbeddingError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          result = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = result.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end

          embedding_response = result.ok || raise Crig::Embeddings::EmbeddingError.new("Ollama response did not include a success payload")
          raise Crig::Embeddings::EmbeddingError.new("Number of returned embeddings does not match input") unless embedding_response.embeddings.size == documents.size

          embedding_response.embeddings.zip(documents).map do |vec, document|
            Crig::Embeddings::Embedding.new(document, vec)
          end
        end
      end

      struct Function
        include JSON::Serializable

        getter name : String
        getter arguments : JSON::Any

        def initialize(@name : String, @arguments : JSON::Any)
        end
      end

      enum ToolType
        Function

        def to_json(json : JSON::Builder) : Nil
          json.string("function")
        end
      end

      struct ToolCall
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : ToolType = ToolType::Function
        getter function : Function

        def initialize(@function : Function, @type : ToolType = ToolType::Function)
        end

        def self.from_core(tool_call : Crig::Completion::ToolCall) : self
          new(Function.new(tool_call.function.name, tool_call.function.arguments))
        end
      end

      struct ToolDefinition
        getter type_field : String
        getter function : Crig::Completion::ToolDefinition

        def initialize(@function : Crig::Completion::ToolDefinition, @type_field : String = "function")
        end

        def self.from_core(tool : Crig::Completion::ToolDefinition) : self
          new(
            Crig::Completion::ToolDefinition.new(
              tool.name,
              tool.description,
              tool.parameters,
            )
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", @type_field
            json.field "function" { @function.to_json(json) }
          end
        end
      end

      struct ImageUrl
        include JSON::Serializable

        getter url : String
        getter detail : Crig::Completion::ImageDetail

        def initialize(@url : String, @detail : Crig::Completion::ImageDetail = Crig::Completion::ImageDetail::Auto)
        end
      end

      struct SystemContent
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : SystemContentType = SystemContentType::Text
        getter text : String

        def initialize(@text : String, @type : SystemContentType = SystemContentType::Text)
        end

        def self.from(value : String) : self
          new(value)
        end
      end

      enum SystemContentType
        Text

        def to_json(json : JSON::Builder) : Nil
          json.string("text")
        end
      end

      struct AssistantContent
        include JSON::Serializable

        getter text : String

        def initialize(@text : String)
        end

        def self.from(value : String) : self
          new(value)
        end
      end

      struct UserContent
        enum Kind
          Text
          Image
        end

        getter kind : Kind
        getter text : String?
        getter image_url : ImageUrl?

        def initialize(@kind : Kind, @text : String? = nil, @image_url : ImageUrl? = nil)
        end

        def self.text(value : String) : self
          new(Kind::Text, text: value)
        end

        def self.image(url : ImageUrl) : self
          new(Kind::Image, image_url: url)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "type", "text"
              json.field "text", @text
            in .image?
              image_url = @image_url
              raise Crig::Completion::CompletionError.new("Ollama image content is missing image_url") unless image_url
              json.field "type", "image"
              json.field "image_url" { image_url.to_json(json) }
            end
          end
        end
      end

      struct Message
        enum Kind
          User
          Assistant
          System
          ToolResult
        end

        getter kind : Kind
        getter content : String
        getter images : Array(String)?
        getter name : String?
        getter thinking : String?
        getter tool_calls : Array(ToolCall)

        def initialize(
          @kind : Kind,
          @content : String,
          @images : Array(String)? = nil,
          @name : String? = nil,
          @thinking : String? = nil,
          @tool_calls : Array(ToolCall) = [] of ToolCall,
        )
        end

        def self.user(content : String, images : Array(String)? = nil, name : String? = nil) : self
          new(Kind::User, content, images, name)
        end

        def self.assistant(
          content : String,
          thinking : String? = nil,
          images : Array(String)? = nil,
          name : String? = nil,
          tool_calls : Array(ToolCall) = [] of ToolCall,
        ) : self
          new(Kind::Assistant, content, images, name, thinking, tool_calls)
        end

        def self.system(content : String) : self
          new(Kind::System, content)
        end

        def self.tool_result(name : String, content : String) : self
          new(Kind::ToolResult, content, name: name)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          role = hash["role"].as_s
          case role
          when "user"
            user(
              hash["content"].as_s,
              hash["images"]?.try(&.as_a?.try(&.map(&.as_s))),
              hash["name"]?.try(&.as_s?),
            )
          when "assistant"
            assistant(
              hash["content"]?.try(&.as_s?) || "",
              hash["thinking"]?.try(&.as_s?),
              hash["images"]?.try(&.as_a?.try(&.map(&.as_s))),
              hash["name"]?.try(&.as_s?),
              hash["tool_calls"]?.try(&.as_a?.try(&.map { |item| ToolCall.from_json(item.to_json) })) || [] of ToolCall,
            )
          when "system"
            system(hash["content"].as_s)
          when "tool"
            tool_result(hash["tool_name"].as_s, hash["content"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown Ollama role: #{role}")
          end
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
        end

        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          return from_core_user_message(message) if message.role.user?
          from_core_assistant_message(message)
        end

        private def self.from_core_user_message(message : Crig::Completion::Message) : Array(self)
          user_contents = message.content.to_a.map(&.as(Crig::Completion::UserContent))
          tool_results, other_content = user_contents.partition(&.kind.tool_result?)
          return tool_results.map { |content| tool_result_from_user_content(content) } unless tool_results.empty?
          [build_user_message(other_content)]
        end

        private def self.tool_result_from_user_content(content : Crig::Completion::UserContent) : self
          tool_result = content.tool_result
          raise Crig::Completion::CompletionError.new("Ollama tool result content missing tool_result") unless tool_result

          content_string = tool_result.content.to_a.map do |tool_result_content|
            if tool_result_content.kind.text?
              text = tool_result_content.text
              raise Crig::Completion::CompletionError.new("Ollama tool result text content missing text payload") unless text
              text.text
            else
              "[Non-text content]"
            end
          end.join('\n')

          Message.tool_result(tool_result.id, content_string)
        end

        private def self.build_user_message(contents : Array(Crig::Completion::UserContent)) : self
          texts = [] of String
          images = [] of String

          contents.each do |content|
            case content.kind
            in .text?
              append_user_text!(texts, content)
            in .image?
              append_user_image!(images, content)
            in .document?
              append_user_document!(texts, content)
            in .audio?, .video?, .tool_result?
            end
          end

          Message.user(texts.join(' '), images.empty? ? nil : images)
        end

        private def self.append_user_text!(texts : Array(String), content : Crig::Completion::UserContent) : Nil
          text = content.text
          raise Crig::Completion::CompletionError.new("Ollama user text content missing text payload") unless text
          texts << text.text
        end

        private def self.append_user_image!(images : Array(String), content : Crig::Completion::UserContent) : Nil
          image = content.image
          raise Crig::Completion::CompletionError.new("Ollama image content missing image payload") unless image
          return unless image.data.kind.base64?

          string_value = image.data.string_value
          raise Crig::Completion::CompletionError.new("Ollama base64 image is missing string data") unless string_value
          images << string_value
        end

        private def self.append_user_document!(texts : Array(String), content : Crig::Completion::UserContent) : Nil
          document = content.document
          raise Crig::Completion::CompletionError.new("Ollama document content missing document payload") unless document
          return unless document.data.kind.base64? || document.data.kind.string? || document.data.kind.url?

          string_value = document.data.string_value
          raise Crig::Completion::CompletionError.new("Ollama document text is missing string data") unless string_value
          texts << string_value
        end

        private def self.from_core_assistant_message(message : Crig::Completion::Message) : Array(self)
          text_content = [] of String
          thinking = nil
          tool_calls = [] of ToolCall

          message.content.to_a.each do |item|
            content = item.as(Crig::Completion::AssistantContent)
            case content.kind
            in .text?
              text = content.text
              raise Crig::Completion::CompletionError.new("Ollama assistant text content missing text payload") unless text
              text_content << text.text
            in .tool_call?
              tool_call = content.tool_call
              raise Crig::Completion::CompletionError.new("Ollama assistant tool call missing payload") unless tool_call
              tool_calls << ToolCall.from_core(tool_call)
            in .reasoning?
              reasoning = content.reasoning
              raise Crig::Completion::CompletionError.new("Ollama assistant reasoning missing payload") unless reasoning
              display = reasoning.display_text
              thinking = display unless display.empty?
            in .image?
              raise Crig::Completion::MessageError.new("Ollama currently doesn't support images.")
            end
          end

          [Message.assistant(text_content.join(' '), thinking, nil, nil, tool_calls)]
        end

        def to_core_message : Crig::Completion::Message
          case @kind
          in .user?
            Crig::Completion::Message.user(@content)
          in .assistant?
            assistant_contents = [] of Crig::Completion::AssistantContent
            assistant_contents << Crig::Completion::AssistantContent.text(@content)
            @tool_calls.each do |tool_call|
              assistant_contents << Crig::Completion::AssistantContent.tool_call(
                tool_call.function.name,
                tool_call.function.name,
                tool_call.function.arguments,
              )
            end
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::Assistant,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                assistant_contents.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
              ),
            )
          in .system?
            Crig::Completion::Message.user(@content)
          in .tool_result?
            Crig::Completion::Message.tool_result(@name || "", @content)
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .user?
              json.field "role", "user"
              json.field "content", @content
              json.field "images", @images unless @images.nil?
              json.field "name", @name unless @name.nil?
            in .assistant?
              json.field "role", "assistant"
              json.field "content", @content
              json.field "thinking", @thinking unless @thinking.nil?
              json.field "images", @images unless @images.nil?
              json.field "name", @name unless @name.nil?
              unless @tool_calls.empty?
                json.field "tool_calls" do
                  json.array do
                    @tool_calls.each(&.to_json(json))
                  end
                end
              end
            in .system?
              json.field "role", "system"
              json.field "content", @content
              json.field "images", @images unless @images.nil?
              json.field "name", @name unless @name.nil?
            in .tool_result?
              json.field "role", "tool"
              json.field "tool_name", @name
              json.field "content", @content
            end
          end
        end
      end

      struct CompletionResponse
        include JSON::Serializable

        getter model : String
        getter created_at : String
        getter message : Message
        getter? done : Bool
        getter done_reason : String?
        getter total_duration : Int64?
        getter load_duration : Int64?
        getter prompt_eval_count : Int64?
        getter prompt_eval_duration : Int64?
        getter eval_count : Int64?
        getter eval_duration : Int64?

        def initialize(
          @model : String,
          @created_at : String,
          @message : Message,
          @done : Bool,
          @done_reason : String? = nil,
          @total_duration : Int64? = nil,
          @load_duration : Int64? = nil,
          @prompt_eval_count : Int64? = nil,
          @prompt_eval_duration : Int64? = nil,
          @eval_count : Int64? = nil,
          @eval_duration : Int64? = nil,
        )
        end

        def done : Bool
          @done
        end

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          raise Crig::Completion::CompletionError.new("Chat response does not include an assistant message") unless @message.kind.assistant?

          assistant_contents = [] of Crig::Completion::AssistantContent
          assistant_contents << Crig::Completion::AssistantContent.text(@message.content) unless @message.content.empty?
          @message.tool_calls.each do |tool_call|
            assistant_contents << Crig::Completion::AssistantContent.tool_call(
              tool_call.function.name,
              tool_call.function.name,
              tool_call.function.arguments,
            )
          end
          raise Crig::Completion::CompletionError.new("No content provided") if assistant_contents.empty?
          choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(assistant_contents)
          prompt_tokens = @prompt_eval_count || 0_i64
          completion_tokens = @eval_count || 0_i64

          Crig::Completion::CompletionResponse(self).new(
            choice,
            Crig::Completion::Usage.new(
              input_tokens: prompt_tokens,
              output_tokens: completion_tokens,
              total_tokens: prompt_tokens + completion_tokens,
              cached_input_tokens: 0_i64,
            ),
            CompletionResponse.new(
              @model,
              @created_at,
              Message.assistant(@message.content, @message.thinking, nil, nil, @message.tool_calls.dup),
              @done,
              @done_reason,
              @total_duration,
              @load_duration,
              @prompt_eval_count,
              @prompt_eval_duration,
              @eval_count,
              @eval_duration,
            ),
          )
        end
      end

      struct OllamaCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter temperature : Float64?
        getter tools : Array(ToolDefinition)
        getter? stream : Bool
        getter think : Bool | String
        getter max_tokens : Int64?
        getter keep_alive : String?
        getter format : JSON::Any?
        getter options : JSON::Any

        def initialize(
          @model : String,
          @messages : Array(Message),
          @temperature : Float64? = nil,
          @tools : Array(ToolDefinition) = [] of ToolDefinition,
          @stream : Bool = false,
          @think : Bool | String = false,
          @max_tokens : Int64? = nil,
          @keep_alive : String? = nil,
          @format : JSON::Any? = nil,
          @options : JSON::Any = JSON.parse(%({"temperature":null})),
        )
        end

        def stream : Bool
          @stream
        end

        def think? : Bool
          @think.is_a?(Bool) && @think
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          model = req.model || default_model
          partial_history = [] of Crig::Completion::Message
          if docs = req.normalized_documents
            partial_history << docs
          end
          partial_history.concat(req.chat_history.to_a)

          full_history = [] of Message
          if preamble = req.preamble
            full_history << Message.system(preamble)
          end
          partial_history.each do |message|
            Message.from_core_message(message).each do |provider_message|
              full_history << provider_message
            end
          end

          think = false.as(Bool | String)
          keep_alive = nil
          temperature_value = req.temperature
          options_hash = {"temperature" => temperature_value.nil? ? JSON.parse("null") : JSON::Any.new(temperature_value)}

          if extra = req.additional_params
            object = extra.as_h?.try(&.dup) || raise Crig::Completion::CompletionError.new("Ollama additional_params must be an object")
            if think_value = object.delete("think")
              if think_value.as_bool?
                think = think_value.as_bool
              elsif think_s = think_value.as_s?
                level = think_s.downcase
                case level
                when "low", "medium", "high"
                  think = level
                else
                  raise Crig::Completion::CompletionError.new("`think` must be a 'low', 'medium', 'high', or bool")
                end
              else
                raise Crig::Completion::CompletionError.new("`think` must be a 'low', 'medium', 'high', or bool")
              end
            end
            if keep_alive_value = object.delete("keep_alive")
              keep_alive_text = keep_alive_value.as_s?
              raise Crig::Completion::CompletionError.new("`keep_alive` must be a string") if keep_alive_text.nil?
              keep_alive = keep_alive_text
            end
            options_hash = Crig::Providers::OpenAI.merge_json_hashes(options_hash, object)
          end

          new(
            model,
            full_history,
            req.temperature,
            req.tools.map { |tool| ToolDefinition.from_core(tool) },
            false,
            think,
            req.max_tokens,
            keep_alive,
            req.output_schema,
            JSON.parse(options_hash.to_json),
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "model", @model
            json.field "messages" do
              json.array do
                @messages.each(&.to_json(json))
              end
            end
            json.field "temperature", @temperature unless @temperature.nil?
            unless @tools.empty?
              json.field "tools" do
                json.array do
                  @tools.each(&.to_json(json))
                end
              end
            end
            json.field "stream", @stream
            json.field "think", @think
            json.field "max_tokens", @max_tokens unless @max_tokens.nil?
            json.field "keep_alive", @keep_alive unless @keep_alive.nil?
            json.field "format", @format unless @format.nil?
            json.field "options", @options
          end
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter done_reason : String?
        getter total_duration : Int64?
        getter load_duration : Int64?
        getter prompt_eval_count : Int64?
        getter prompt_eval_duration : Int64?
        getter eval_count : Int64?
        getter eval_duration : Int64?

        def initialize(
          @done_reason : String? = nil,
          @total_duration : Int64? = nil,
          @load_duration : Int64? = nil,
          @prompt_eval_count : Int64? = nil,
          @prompt_eval_duration : Int64? = nil,
          @eval_count : Int64? = nil,
          @eval_duration : Int64? = nil,
        )
        end

        def token_usage : Crig::Completion::Usage?
          input_tokens = @prompt_eval_count || 0_i64
          output_tokens = @eval_count || 0_i64
          Crig::Completion::Usage.new(
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: input_tokens + output_tokens,
            cached_input_tokens: 0_i64,
          )
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
          span = Crig::Span.chat_span("ollama", @model, request.preamble, nil)

          payload = OllamaCompletionRequest.from_request(@model, request)
          response = @client.post_json("/api/chat", payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          result = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = result.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          completion_response = result.ok || raise Crig::Completion::CompletionError.new("Ollama response did not include a success payload")
          response = completion_response.to_completion_response
          if raw = response.raw_response
            span.record_response_metadata(raw) if raw.responds_to?(:get_response_id)
            span.record_token_usage(response.usage) if response.usage.responds_to?(:token_usage)
          end
          response
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = OllamaCompletionRequest.from_request(@model, request)
          payload = OllamaCompletionRequest.new(
            payload.model,
            payload.messages,
            payload.temperature,
            payload.tools,
            true,
            payload.think,
            payload.max_tokens,
            payload.keep_alive,
            payload.format,
            payload.options,
          )
          response = @client.post_json("/api/chat", payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(parse_streaming_choices(body))
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          tool_calls_final = [] of ToolCall
          text_response = ""
          thinking_response = ""

          text.each_line do |line|
            stripped = line.strip
            next if stripped.empty?
            response = CompletionResponse.from_json(stripped)

            if response.message.kind.assistant?
              if thinking = response.message.thinking
                unless thinking.empty?
                  thinking_response += thinking
                  raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, thinking)
                end
              end

              unless response.message.content.empty?
                text_response += response.message.content
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(response.message.content)
              end

              response.message.tool_calls.each do |tool_call|
                tool_calls_final << tool_call
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
                  Crig::RawStreamingToolCall.new("", tool_call.function.name, tool_call.function.arguments)
                )
              end
            end

            next unless response.done

            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
              StreamingCompletionResponse.new(
                response.done_reason,
                response.total_duration,
                response.load_duration,
                response.prompt_eval_count,
                response.prompt_eval_duration,
                response.eval_count,
                response.eval_duration,
              )
            )
            break
          end

          raw_choices
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Ollama::CompletionModel)
        include Crig::EmbeddingsClient(Crig::Providers::Ollama::EmbeddingModel)
      end

      struct OllamaModelLister
        include Crig::Client::ModelLister(Crig::Providers::Ollama::Client)

        getter client : Crig::Providers::Ollama::Client

        def initialize(@client : Crig::Providers::Ollama::Client)
        end

        def list_all : Crig::ModelList
          path = "/api/tags"
          uri = "#{@client.base_url.rstrip('/')}/#{path.lstrip('/')}"
          headers = HTTP::Headers{"Accept" => "application/json"}
          response = HTTP::Client.get(uri, headers: headers)
          raise Crig::ModelListingError.api_error(response.status_code, response.body) unless response.success?

          parsed = JSON.parse(response.body)
          entries = parsed["models"].as_a.map do |entry|
            Crig::Model::Model.new(
              entry["name"].as_s,
            )
          end

          Crig::ModelList.new(entries)
        end
      end
    end
  end
end
