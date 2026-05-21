module Crig
  module Providers
    module Perplexity
      SONAR_PRO = "sonar_pro"
      SONAR     = "sonar"

      enum Role
        System
        User
        Assistant

        def to_wire : String
          to_s.downcase
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      struct Message
        getter role : Role
        getter content : String

        def initialize(@role : Role, @content : String)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(Role.from_json_value(hash["role"]), hash["content"].as_s)
        end

        def self.from_core_message(message : Crig::Completion::Message) : self
          case message.role
          in .user?
            collapsed = message.content.map do |content|
              user_content = content.as?(Crig::Completion::UserContent) || raise Crig::Completion::MessageError.new("Only text content is supported by Perplexity")
              if user_content.kind.text?
                user_content.text.try(&.text) || ""
              else
                raise Crig::Completion::MessageError.new("Only text content is supported by Perplexity")
              end
            end.join('\n')
            new(Role::User, collapsed)
          in .assistant?
            collapsed = message.content.map do |content|
              assistant_content = content.as?(Crig::Completion::AssistantContent) || raise Crig::Completion::MessageError.new("Only text assistant message content is supported by Perplexity")
              if assistant_content.kind.text?
                assistant_content.text.try(&.text) || ""
              else
                raise Crig::Completion::MessageError.new("Only text assistant message content is supported by Perplexity")
              end
            end.join('\n')
            new(Role::Assistant, collapsed)
          end
        end

        def to_core_message : Crig::Completion::Message
          case @role
          in .user?
            Crig::Completion::Message.user(@content)
          in .assistant?
            Crig::Completion::Message.assistant(@content)
          in .system?
            Crig::Completion::Message.user(@content)
          end
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "role", @role.to_wire
              json.field "content", @content
            end
          end
        end
      end

      struct Delta
        getter role : Role
        getter content : String

        def initialize(@role : Role, @content : String)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(Role.from_json_value(hash["role"]), hash["content"].as_s)
        end
      end

      struct Choice
        getter index : Int32
        getter finish_reason : String
        getter message : Message
        getter delta : Delta

        def initialize(@index : Int32, @finish_reason : String, @message : Message, @delta : Delta)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          message = Message.from_json_value(hash["message"])
          delta = if raw = hash["delta"]?
                    Delta.from_json_value(raw)
                  else
                    Delta.new(message.role, message.content)
                  end
          new(hash["index"].as_i, hash["finish_reason"].as_s, message, delta)
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter prompt_tokens : Int32
        getter completion_tokens : Int32
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @completion_tokens : Int32, @total_tokens : Int32)
        end

        def token_usage : Crig::Completion::Usage?
          Crig::Completion::Usage.new(
            @prompt_tokens.to_i64,
            @completion_tokens.to_i64,
            @total_tokens.to_i64,
            0_i64,
          )
        end

        def to_s(io : IO) : Nil
          io << "Prompt tokens: " << @prompt_tokens << '\n'
          io << "Completion tokens: " << @completion_tokens << " Total tokens: " << @total_tokens
        end
      end

      struct CompletionResponse
        getter id : String
        getter model : String
        getter object : String
        getter created : Int64
        getter choices : Array(Choice)
        getter usage : Usage

        def initialize(@id : String, @model : String, @object : String, @created : Int64, @choices : Array(Choice), @usage : Usage)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            hash["model"].as_s,
            hash["object"].as_s,
            hash["created"].as_i64,
            hash["choices"]?.try(&.as_a.map { |entry| Choice.from_json_value(entry) }) || [] of Choice,
            Usage.from_json(hash["usage"].to_json),
          )
        end

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          unless choice.message.role.assistant?
            raise Crig::Completion::CompletionError.new("Response contained no assistant message")
          end

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text(choice.message.content)),
            @usage.token_usage || Crig::Completion::Usage.new,
            self,
          )
        end
      end

      struct PerplexityCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter temperature : Float64?
        getter max_tokens : Int64?
        getter additional_params : JSON::Any?
        getter? stream : Bool

        def initialize(
          @model : String,
          @messages : Array(Message),
          @temperature : Float64? = nil,
          @max_tokens : Int64? = nil,
          @additional_params : JSON::Any? = nil,
          @stream : Bool = false,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest, stream : Bool = false) : self
          model = req.model || default_model
          full_history = [] of Message
          if preamble = req.preamble
            full_history << Message.new(Role::System, preamble)
          end
          if docs = req.normalized_documents
            full_history << Message.from_core_message(docs)
          end
          req.chat_history.each do |entry|
            full_history << Message.from_core_message(entry)
          end

          new(model, full_history, req.temperature, req.max_tokens, req.additional_params, stream)
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
              json.field "max_tokens", @max_tokens unless @max_tokens.nil?
              json.field "stream", @stream
            end
          end

          if additional_params = @additional_params
            JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
          else
            payload
          end
        end
      end

      struct StreamingDelta
        getter role : Role?
        getter content : String?

        def initialize(@role : Role? = nil, @content : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["role"]?.try { |entry| Role.from_json_value(entry) },
            hash["content"]?.try(&.as_s?),
          )
        end
      end

      struct StreamingChoice
        getter index : Int32
        getter finish_reason : String?
        getter delta : StreamingDelta

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
            hash["usage"]?.try(&.as_h?).try { |entry| Usage.from_json(entry.to_json) },
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
          span = Crig::Span.chat_span("perplexity", @model, request.preamble, nil)

          payload = PerplexityCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/v1/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json_value(value) }
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("Perplexity response did not include a success payload")
          result = response_body.to_crig_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = PerplexityCompletionRequest.from_request(@model, request, true).to_json_value
          response = @client.post_json("/chat/completions", payload.to_json, {"Accept" => "text/event-stream"})
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          raw_choices = parse_streaming_choices(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          final_usage = Usage.new(0, 0, 0)
          message_id : String? = nil

          text.each_line do |line|
            next unless line.starts_with?("data:")
            data = line.lchop("data:").strip
            next if data.empty? || data == "[DONE]"

            chunk = StreamingCompletionChunk.from_json_value(JSON.parse(data))
            unless message_id
              message_id = chunk.id
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message_id(chunk.id)
            end
            if usage = chunk.usage
              final_usage = usage
            end
            choice = chunk.choices.first?
            next unless choice
            if content = choice.delta.content
              next if content.empty?
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(content)
            end
          end

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(final_usage.token_usage)
          )
          raw_choices
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Perplexity::CompletionModel)
      end
    end
  end
end
