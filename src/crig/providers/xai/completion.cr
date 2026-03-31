module Crig
  module Providers
    module XAI
      GROK_2_1212        = "grok-2-1212"
      GROK_2_VISION_1212 = "grok-2-vision-1212"
      GROK_3             = "grok-3"
      GROK_3_FAST        = "grok-3-fast"
      GROK_3_MINI        = "grok-3-mini"
      GROK_3_MINI_FAST   = "grok-3-mini-fast"
      GROK_2_IMAGE_1212  = "grok-2-image-1212"
      GROK_4             = "grok-4-0709"

      struct CompletionResponse
        include JSON::Serializable

        getter id : String
        getter model : String
        @[JSON::Field(converter: JSON::ArrayConverter(Crig::Providers::OpenAI::OutputConverter))]
        getter output : Array(Crig::Providers::OpenAI::Output)
        getter created : Int64 = 0_i64
        getter object : String = ""
        getter status : String?
        getter usage : Crig::Providers::OpenAI::ResponsesUsage?

        def initialize(
          @id : String,
          @model : String,
          @output : Array(Crig::Providers::OpenAI::Output),
          @created : Int64 = 0_i64,
          @object : String = "",
          @status : String? = nil,
          @usage : Crig::Providers::OpenAI::ResponsesUsage? = nil,
        )
        end

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          content = @output.flat_map(&.to_assistant_content)
          choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(content)
          raise Crig::Completion::CompletionError.new("Response contained no output") unless choice

          Crig::Completion::CompletionResponse(self).new(
            choice,
            @usage.try(&.to_crig_usage) || Crig::Completion::Usage.new,
            self,
          )
        end
      end

      struct XAICompletionRequest
        getter model : String
        getter input : Array(Message)
        getter temperature : Float64?
        getter max_output_tokens : Int64?
        getter tools : Array(ToolDefinition)
        getter tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @input : Array(Message),
          @temperature : Float64? = nil,
          @max_output_tokens : Int64? = nil,
          @tools : Array(ToolDefinition) = [] of ToolDefinition,
          @tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, request : Crig::Completion::Request::CompletionRequest) : self
          model = request.model || default_model
          input = [] of Message
          if preamble = request.preamble
            input << Message.system(preamble)
          end
          request.chat_history.each do |message|
            input.concat(Message.from_completion_message(message))
          end

          tool_choice = request.tool_choice.try do |choice|
            case choice.kind
            when .auto?     then Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            when .none?     then Crig::Providers::OpenAI::Chat::ToolChoice::None
            when .required? then Crig::Providers::OpenAI::Chat::ToolChoice::Required
            when .specific?
              raise Crig::Completion::CompletionError.new("xAI does not support named tool-choice functions")
            end
          end

          new(
            model,
            input,
            request.temperature,
            request.max_tokens,
            request.tools.map { |tool| ToolDefinition.from(tool) },
            tool_choice,
            request.additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array do
                  @input.each(&.to_json_value.to_json(json))
                end
              end
              if temperature = @temperature
                json.field "temperature", temperature
              end
              if max_output_tokens = @max_output_tokens
                json.field "max_output_tokens", max_output_tokens
              end
              unless @tools.empty?
                json.field "tools" do
                  json.array do
                    @tools.each(&.to_json.to_json(json))
                  end
                end
              end
              if tool_choice = @tool_choice
                json.field "tool_choice", tool_choice.to_wire
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

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          payload = XAICompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/v1/responses", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          body = JSON.parse(text)
          parsed = ApiResponse(CompletionResponse).from_json_value(body) { |value| CompletionResponse.from_json(value.to_json) }
          if error = parsed.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = parsed.ok || raise Crig::Completion::CompletionError.new("xAI response did not include a success payload")
          response_body.to_crig_response
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          XAI.send_xai_streaming_request(@client, @model, XAICompletionRequest.from_request(@model, request))
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::XAI::CompletionModel)
      end
    end
  end
end
