module Crig
  module Completion
    module Request
      struct ProviderToolDefinition
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter kind : String
        include JSON::Serializable::Unmapped

        def initialize(@kind : String)
        end

        def with_config(key : String, value : JSON::Any) : self
          copy = self.class.from_json(to_json)
          copy.json_unmapped[key] = value
          copy
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      struct Document
        include JSON::Serializable

        getter id : String
        getter text : String
        @[JSON::Field(key: "additional_props")]
        getter additional_props : Hash(String, String)

        def initialize(@id : String, @text : String, @additional_props : Hash(String, String) = {} of String => String)
        end

        def to_s(io : IO) : Nil
          io << "<file id: " << @id << ">\n"
          if @additional_props.empty?
            io << @text
          else
            metadata = @additional_props.to_a.sort_by(&.[0]).map { |key, value| %(#{key}: #{value.inspect}) }.join(" ")
            io << "<metadata " << metadata << " />\n"
            io << @text
          end
          io << "\n</file>\n"
        end
      end

      struct CompletionRequest
        getter model : String?
        getter preamble : String?
        getter chat_history : Crig::OneOrMany(Crig::Completion::Message)
        getter documents : Array(Document)
        getter tools : Array(Crig::Completion::ToolDefinition)
        getter provider_tools : Array(ProviderToolDefinition)
        getter temperature : Float64?
        getter max_tokens : Int64?
        getter tool_choice : Crig::Completion::ToolChoice?
        getter additional_params : JSON::Any?
        getter output_schema : JSON::Any?

        def initialize(
          @chat_history : Crig::OneOrMany(Crig::Completion::Message),
          @model : String? = nil,
          @preamble : String? = nil,
          @documents : Array(Document) = [] of Document,
          @tools : Array(Crig::Completion::ToolDefinition) = [] of Crig::Completion::ToolDefinition,
          @provider_tools : Array(ProviderToolDefinition) = [] of ProviderToolDefinition,
          @temperature : Float64? = nil,
          @max_tokens : Int64? = nil,
          @tool_choice : Crig::Completion::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
          @output_schema : JSON::Any? = nil,
        )
        end

        def output_schema_name : String?
          schema = @output_schema
          return unless schema
          schema["title"]?.try(&.as_s?) || "response_schema"
        end

        def normalized_documents : Crig::Completion::Message?
          return if @documents.empty?

          contents = @documents.map do |document|
            Crig::Completion::UserContent.new(
              Crig::Completion::UserContent::Kind::Document,
              document: Crig::Completion::Document.new(
                Crig::Completion::DocumentSourceKind.string(document.to_s),
                Crig::Completion::DocumentMediaType::TXT,
              ),
            )
          end

          Crig::Completion::Message.new(
            Crig::Completion::Message::Role::User,
            Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
              contents.map { |content| content.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
            ),
          )
        end

        def with_provider_tool(tool : ProviderToolDefinition) : self
          self.class.new(
            @chat_history,
            model: @model,
            preamble: @preamble,
            documents: @documents,
            tools: @tools,
            provider_tools: @provider_tools + [tool],
            temperature: @temperature,
            max_tokens: @max_tokens,
            tool_choice: @tool_choice,
            additional_params: with_provider_tools_in_params(@additional_params, @provider_tools + [tool]),
            output_schema: @output_schema,
          )
        end

        def with_provider_tools(tools : Array(ProviderToolDefinition)) : self
          tools.reduce(self) { |request, tool| request.with_provider_tool(tool) }
        end

        private def with_provider_tools_in_params(
          additional_params : JSON::Any?,
          provider_tools : Array(ProviderToolDefinition),
        ) : JSON::Any?
          params_hash = additional_params.try(&.as_h?.try(&.dup)) || {} of String => JSON::Any
          existing = params_hash["tools"]?.try(&.as_a?.dup) || [] of JSON::Any
          params_hash["tools"] = JSON.parse((existing + provider_tools.map(&.to_json_value)).to_json)
          JSON.parse(params_hash.to_json)
        end
      end

      struct CompletionRequestBuilder
        getter prompt : Crig::Completion::Message
        getter request_model : String?
        getter preamble : String?
        getter chat_history : Array(Crig::Completion::Message)
        getter documents : Array(Document)
        getter tools : Array(Crig::Completion::ToolDefinition)
        getter provider_tools : Array(ProviderToolDefinition)
        getter temperature : Float64?
        getter max_tokens : Int64?
        getter tool_choice : Crig::Completion::ToolChoice?
        getter additional_params : JSON::Any?
        getter output_schema : JSON::Any?

        def initialize(
          @prompt : Crig::Completion::Message,
          @request_model : String? = nil,
          @preamble : String? = nil,
          @chat_history : Array(Crig::Completion::Message) = [] of Crig::Completion::Message,
          @documents : Array(Document) = [] of Document,
          @tools : Array(Crig::Completion::ToolDefinition) = [] of Crig::Completion::ToolDefinition,
          @provider_tools : Array(ProviderToolDefinition) = [] of ProviderToolDefinition,
          @temperature : Float64? = nil,
          @max_tokens : Int64? = nil,
          @tool_choice : Crig::Completion::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
          @output_schema : JSON::Any? = nil,
        )
        end

        def self.new(prompt : Crig::Completion::Message | String) : self
          prompt_message = prompt.is_a?(String) ? Crig::Completion::Message.user(prompt) : prompt
          new(prompt_message)
        end

        def self.from_prompt(prompt : Crig::Completion::Message | String) : self
          new(prompt)
        end

        def preamble(value : String) : self
          self.class.new(@prompt, @request_model, value, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def model(value : String) : self
          self.class.new(@prompt, value, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def model_opt(value : String?) : self
          self.class.new(@prompt, value, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def without_preamble : self
          self.class.new(@prompt, @request_model, nil, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def message(value : Crig::Completion::Message) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history + [value], @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def messages(values : Array(Crig::Completion::Message)) : self
          values.reduce(self) { |builder, value| builder.message(value) }
        end

        def document(value : Document) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents + [value], @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def documents(values : Array(Document)) : self
          values.reduce(self) { |builder, value| builder.document(value) }
        end

        def tool(value : Crig::Completion::ToolDefinition) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools + [value], @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def tools(values : Array(Crig::Completion::ToolDefinition)) : self
          values.reduce(self) { |builder, value| builder.tool(value) }
        end

        def provider_tool(value : ProviderToolDefinition) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools + [value], @temperature, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def provider_tools(values : Array(ProviderToolDefinition)) : self
          values.reduce(self) { |builder, value| builder.provider_tool(value) }
        end

        def additional_params(value : JSON::Any) : self
          merged = @additional_params ? merge_json(@additional_params.as(JSON::Any), value) : value
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, merged, @output_schema)
        end

        def additional_params_opt(value : JSON::Any?) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, value, @output_schema)
        end

        def temperature(value : Float64) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, value, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def temperature_opt(value : Float64?) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, value, @max_tokens, @tool_choice, @additional_params, @output_schema)
        end

        def max_tokens(value : Int64) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, value, @tool_choice, @additional_params, @output_schema)
        end

        def max_tokens_opt(value : Int64?) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, value, @tool_choice, @additional_params, @output_schema)
        end

        def tool_choice(value : Crig::Completion::ToolChoice) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, value, @additional_params, @output_schema)
        end

        def output_schema(value : JSON::Any) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, value)
        end

        def output_schema_opt(value : JSON::Any?) : self
          self.class.new(@prompt, @request_model, @preamble, @chat_history, @documents, @tools, @provider_tools, @temperature, @max_tokens, @tool_choice, @additional_params, value)
        end

        def build : CompletionRequest
          merged_additional_params = if @provider_tools.empty?
                                       @additional_params
                                     else
                                       params = @additional_params.try(&.as_h?.try(&.dup)) || {} of String => JSON::Any
                                       existing = params["tools"]?.try(&.as_a?.dup) || [] of JSON::Any
                                       params["tools"] = JSON.parse((existing + @provider_tools.map(&.to_json_value)).to_json)
                                       JSON.parse(params.to_json)
                                     end
          CompletionRequest.new(
            Crig::OneOrMany(Crig::Completion::Message).many(@chat_history + [@prompt]),
            model: @request_model,
            preamble: @preamble,
            documents: @documents,
            tools: @tools,
            provider_tools: @provider_tools,
            temperature: @temperature,
            max_tokens: @max_tokens,
            tool_choice: @tool_choice,
            additional_params: merged_additional_params,
            output_schema: @output_schema,
          )
        end

        def send(model)
          model.completion(build)
        end

        def send_async(model)
          model.completion_async(build)
        end

        def stream(model)
          model.stream(build)
        end

        def stream_async(model)
          model.stream_async(build)
        end

        private def merge_json(left : JSON::Any, right : JSON::Any) : JSON::Any
          left_hash = left.as_h?
          right_hash = right.as_h?
          return right unless left_hash && right_hash

          merged = left_hash.dup
          right_hash.each do |key, value|
            merged[key] = if existing = merged[key]?
                            merge_json(existing, value)
                          else
                            value
                          end
          end

          JSON.parse(merged.to_json)
        end
      end
    end
  end
end
