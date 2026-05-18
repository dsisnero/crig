module Crig
  module Providers
    module OpenAI
      def self.require_call_id(call_id : String?, context : String) : String
        call_id || raise Crig::Completion::CompletionError.new("#{context} `call_id` is required for OpenAI Responses API")
      end

      def self.build_json_any(& : JSON::Builder ->) : JSON::Any
        JSON.parse(JSON.build do |json|
          yield json
        end)
      end

      enum Include
        FileSearchCallResults
        MessageInputImageImageUrl
        ComputerCallOutputOutputImageUrl
        ReasoningEncryptedContent
        CodeInterpreterCallOutputs

        def to_wire : String
          case self
          in .file_search_call_results?
            "file_search_call.results"
          in .message_input_image_image_url?
            "message.input_image.image_url"
          in .computer_call_output_output_image_url?
            "computer_call.output.image_url"
          in .reasoning_encrypted_content?
            "reasoning.encrypted_content"
          in .code_interpreter_call_outputs?
            "code_interpreter_call.outputs"
          end
        end
      end

      enum TruncationStrategy
        Auto
        Disabled

        def to_wire : String
          disabled? ? "disabled" : "auto"
        end

        def self.from_wire(value : String) : self
          case value.downcase
          when "auto"
            Auto
          when "disabled"
            Disabled
          else
            raise ArgumentError.new("Unknown truncation strategy: #{value}")
          end
        end
      end

      enum OpenAIServiceTier
        Auto
        Default
        Flex

        def to_wire : String
          to_s.downcase
        end

        def self.from_wire(value : String) : self
          case value.downcase
          when "auto"
            Auto
          when "default"
            Default
          when "flex"
            Flex
          else
            raise ArgumentError.new("Unknown OpenAI service tier: #{value}")
          end
        end
      end

      enum ReasoningEffort
        None
        Minimal
        Low
        Medium
        High
        Xhigh

        def to_wire : String
          to_s.downcase
        end

        def self.from_wire(value : String) : self
          case value.downcase
          when "none"
            None
          when "minimal"
            Minimal
          when "low"
            Low
          when "medium"
            Medium
          when "high"
            High
          when "xhigh"
            Xhigh
          else
            raise ArgumentError.new("Unknown reasoning effort: #{value}")
          end
        end
      end

      enum ReasoningSummaryLevel
        Auto
        Concise
        Detailed

        def to_wire : String
          to_s.downcase
        end

        def self.from_wire(value : String) : self
          case value.downcase
          when "auto"
            Auto
          when "concise"
            Concise
          when "detailed"
            Detailed
          else
            raise ArgumentError.new("Unknown reasoning summary level: #{value}")
          end
        end
      end

      struct StructuredOutputsInput
        getter name : String
        getter schema : JSON::Any
        getter? strict : Bool

        def initialize(@name : String, @schema : JSON::Any, @strict : Bool = true)
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              json.field "name", @name
              json.field "schema" do
                @schema.to_json(json)
              end
              json.field "strict", @strict
            end
          end
        end
      end

      struct TextFormat
        enum Kind
          Text
          JsonSchema
        end

        getter kind : Kind
        getter json_schema : StructuredOutputsInput?

        def initialize(@kind : Kind = Kind::Text, @json_schema : StructuredOutputsInput? = nil)
        end

        def self.text : self
          new
        end

        def self.structured_output(name : String, schema : JSON::Any) : self
          new(Kind::JsonSchema, StructuredOutputsInput.new(name, schema))
        end

        def to_json_value : JSON::Any
          case @kind
          in .text?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "text"
              end
            end
          in .json_schema?
            schema = @json_schema || raise Crig::Completion::CompletionError.new("Missing OpenAI structured output schema")
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "json_schema"
                json.field "name", schema.name
                json.field "schema" do
                  schema.schema.to_json(json)
                end
                json.field "strict", schema.strict?
              end
            end
          end
        end
      end

      struct TextConfig
        getter format : TextFormat

        def initialize(@format : TextFormat = TextFormat.text)
        end

        def self.structured_output(name : String, schema : JSON::Any) : self
          new(TextFormat.structured_output(name, schema))
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              json.field "format" do
                @format.to_json_value.to_json(json)
              end
            end
          end
        end
      end

      struct Reasoning
        getter effort : ReasoningEffort?
        getter summary : ReasoningSummaryLevel?

        def initialize(@effort : ReasoningEffort? = nil, @summary : ReasoningSummaryLevel? = nil)
        end

        def with_effort(reasoning_effort : ReasoningEffort) : self
          self.class.new(reasoning_effort, @summary)
        end

        def with_summary_level(reasoning_summary_level : ReasoningSummaryLevel) : self
          self.class.new(@effort, reasoning_summary_level)
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              if effort = @effort
                json.field "effort", effort.to_wire
              end
              if summary = @summary
                json.field "summary", summary.to_wire
              end
            end
          end
        end
      end

      struct AdditionalParameters
        getter background : Bool?
        getter text : TextConfig?
        getter include : Array(Include)?
        getter top_p : Float64?
        getter truncation : TruncationStrategy?
        getter user : String?
        getter metadata : Hash(String, JSON::Any)
        getter parallel_tool_calls : Bool?
        getter previous_response_id : String?
        getter reasoning : Reasoning?
        getter service_tier : OpenAIServiceTier?
        getter store : Bool?

        def initialize(
          @background : Bool? = nil,
          @text : TextConfig? = nil,
          @include : Array(Include)? = nil,
          @top_p : Float64? = nil,
          @truncation : TruncationStrategy? = nil,
          @user : String? = nil,
          @metadata : Hash(String, JSON::Any) = {} of String => JSON::Any,
          @parallel_tool_calls : Bool? = nil,
          @previous_response_id : String? = nil,
          @reasoning : Reasoning? = nil,
          @service_tier : OpenAIServiceTier? = nil,
          @store : Bool? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h? || {} of String => JSON::Any
          include_values = hash["include"]?.try(&.as_a?).try do |entries|
            entries.compact_map { |entry| include_from_wire?(entry.as_s) }
          end

          reasoning = hash["reasoning"]?.try(&.as_h?).try do |reasoning_hash|
            reasoning_value = Reasoning.new
            if effort = reasoning_hash["effort"]?.try(&.as_s?)
              reasoning_value = reasoning_value.with_effort(ReasoningEffort.from_wire(effort))
            end
            if summary = reasoning_hash["summary"]?.try(&.as_s?)
              reasoning_value = reasoning_value.with_summary_level(ReasoningSummaryLevel.from_wire(summary))
            end
            reasoning_value
          end

          text = hash["text"]?.try(&.as_h?).try do |text_hash|
            format_hash = text_hash["format"]?.try(&.as_h?)
            if format_hash && format_hash["type"]?.try(&.as_s?) == "json_schema"
              TextConfig.structured_output(
                format_hash["name"].as_s,
                format_hash["schema"],
              )
            else
              TextConfig.new(TextFormat.text)
            end
          end

          new(
            background: hash["background"]?.try(&.as_bool?),
            text: text,
            include: include_values,
            top_p: hash["top_p"]?.try(&.as_f?),
            truncation: hash["truncation"]?.try(&.as_s?).try { |wire_value| TruncationStrategy.from_wire(wire_value) },
            user: hash["user"]?.try(&.as_s?),
            metadata: hash["metadata"]?.try(&.as_h?) || {} of String => JSON::Any,
            parallel_tool_calls: hash["parallel_tool_calls"]?.try(&.as_bool?),
            previous_response_id: hash["previous_response_id"]?.try(&.as_s?),
            reasoning: reasoning,
            service_tier: hash["service_tier"]?.try(&.as_s?).try { |wire_value| OpenAIServiceTier.from_wire(wire_value) },
            store: hash["store"]?.try(&.as_bool?),
          )
        end

        def ensure_reasoning_include : self
          return self unless @reasoning

          values = @include.try(&.dup) || [] of Include
          unless values.includes?(Include::ReasoningEncryptedContent)
            values << Include::ReasoningEncryptedContent
          end
          self.class.new(
            background: @background,
            text: @text,
            include: values,
            top_p: @top_p,
            truncation: @truncation,
            user: @user,
            metadata: @metadata,
            parallel_tool_calls: @parallel_tool_calls,
            previous_response_id: @previous_response_id,
            reasoning: @reasoning,
            service_tier: @service_tier,
            store: @store,
          )
        end

        def with_text(text : TextConfig) : self
          self.class.new(
            background: @background,
            text: text,
            include: @include,
            top_p: @top_p,
            truncation: @truncation,
            user: @user,
            metadata: @metadata,
            parallel_tool_calls: @parallel_tool_calls,
            previous_response_id: @previous_response_id,
            reasoning: @reasoning,
            service_tier: @service_tier,
            store: @store,
          )
        end

        def with_reasoning(reasoning : Reasoning) : self
          self.class.new(
            background: @background,
            text: @text,
            include: @include,
            top_p: @top_p,
            truncation: @truncation,
            user: @user,
            metadata: @metadata,
            parallel_tool_calls: @parallel_tool_calls,
            previous_response_id: @previous_response_id,
            reasoning: reasoning,
            service_tier: @service_tier,
            store: @store,
          )
        end

        def to_json_value : JSON::Any
          value = {} of String => JSON::Any
          append_scalar(value, "background", @background)
          append_text(value)
          append_include(value)
          append_scalar(value, "top_p", @top_p)
          append_wire_enum(value, "truncation", @truncation)
          append_scalar(value, "user", @user)
          append_metadata(value)
          append_scalar(value, "parallel_tool_calls", @parallel_tool_calls)
          append_scalar(value, "previous_response_id", @previous_response_id)
          append_reasoning(value)
          append_wire_enum(value, "service_tier", @service_tier)
          append_scalar(value, "store", @store)
          JSON.parse(value.to_json)
        end

        private def self.include_from_wire?(value : String) : Include?
          case value
          when "file_search_call.results"
            Include::FileSearchCallResults
          when "message.input_image.image_url"
            Include::MessageInputImageImageUrl
          when "computer_call.output.image_url"
            Include::ComputerCallOutputOutputImageUrl
          when "reasoning.encrypted_content"
            Include::ReasoningEncryptedContent
          when "code_interpreter_call.outputs"
            Include::CodeInterpreterCallOutputs
          end
        end

        private def append_text(value : Hash(String, JSON::Any))
          if text = @text
            value["text"] = text.to_json_value
          end
        end

        private def append_include(value : Hash(String, JSON::Any))
          if include_values = @include
            unless include_values.empty?
              value["include"] = JSON.parse(include_values.map(&.to_wire).to_json)
            end
          end
        end

        private def append_metadata(value : Hash(String, JSON::Any))
          unless @metadata.empty?
            value["metadata"] = JSON.parse(@metadata.to_json)
          end
        end

        private def append_reasoning(value : Hash(String, JSON::Any))
          if reasoning = @reasoning
            value["reasoning"] = reasoning.to_json_value
          end
        end

        private def append_scalar(value : Hash(String, JSON::Any), key : String, scalar : Bool?)
          value[key] = JSON::Any.new(scalar) unless scalar.nil?
        end

        private def append_scalar(value : Hash(String, JSON::Any), key : String, scalar : Float64?)
          value[key] = JSON::Any.new(scalar) unless scalar.nil?
        end

        private def append_scalar(value : Hash(String, JSON::Any), key : String, scalar : String?)
          value[key] = JSON::Any.new(scalar) unless scalar.nil?
        end

        private def append_wire_enum(value : Hash(String, JSON::Any), key : String, enum_value : TruncationStrategy?)
          if enum_value
            value[key] = JSON::Any.new(enum_value.to_wire)
          end
        end

        private def append_wire_enum(value : Hash(String, JSON::Any), key : String, enum_value : OpenAIServiceTier?)
          if enum_value
            value[key] = JSON::Any.new(enum_value.to_wire)
          end
        end
      end

      struct ResponsesUsage
        include JSON::Serializable

        struct InputTokensDetails
          include JSON::Serializable

          @[JSON::Field(key: "cached_tokens")]
          getter cached_tokens : Int64

          def initialize(@cached_tokens : Int64 = 0_i64)
          end
        end

        struct OutputTokensDetails
          include JSON::Serializable

          @[JSON::Field(key: "reasoning_tokens")]
          getter reasoning_tokens : Int64

          def initialize(@reasoning_tokens : Int64 = 0_i64)
          end
        end

        @[JSON::Field(key: "input_tokens")]
        getter input_tokens : Int64
        @[JSON::Field(key: "input_tokens_details")]
        getter input_tokens_details : InputTokensDetails?
        @[JSON::Field(key: "output_tokens")]
        getter output_tokens : Int64
        @[JSON::Field(key: "output_tokens_details")]
        getter output_tokens_details : OutputTokensDetails?
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int64

        def initialize(
          @input_tokens : Int64 = 0_i64,
          @input_tokens_details : InputTokensDetails? = nil,
          @output_tokens : Int64 = 0_i64,
          @output_tokens_details : OutputTokensDetails? = nil,
          @total_tokens : Int64 = 0_i64,
        )
        end

        def to_crig_usage : Crig::Completion::Usage
          Crig::Completion::Usage.new(
            input_tokens: @input_tokens,
            output_tokens: @output_tokens,
            total_tokens: @total_tokens,
            cached_input_tokens: @input_tokens_details.try(&.cached_tokens) || 0_i64,
          )
        end
      end

      enum Role
        User
        Assistant
        System

        def to_wire : String
          to_s.downcase
        end
      end

      enum ToolStatus
        InProgress
        Completed
        Incomplete

        def to_wire : String
          case self
          in .in_progress?
            "in_progress"
          in .completed?
            "completed"
          in .incomplete?
            "incomplete"
          end
        end
      end

      module ToolStatusConverter
        def self.from_json(pull : JSON::PullParser) : ToolStatus
          ToolStatus.parse(pull.read_string.camelcase)
        end

        def self.to_json(value : ToolStatus, json : JSON::Builder)
          json.string(value.to_wire)
        end
      end

      module ResponseObjectConverter
        def self.from_json(pull : JSON::PullParser) : ResponseObject
          ResponseObject.parse(pull.read_string.camelcase)
        end

        def self.to_json(value : ResponseObject, json : JSON::Builder)
          json.string(value.to_wire)
        end
      end

      module ResponseStatusConverter
        def self.from_json(pull : JSON::PullParser) : ResponseStatus
          ResponseStatus.parse(pull.read_string.camelcase)
        end

        def self.to_json(value : ResponseStatus, json : JSON::Builder)
          json.string(value.to_wire)
        end
      end

      module OutputConverter
        def self.from_json(pull : JSON::PullParser) : Output
          Output.from_json_value(JSON::Any.new(pull))
        end

        def self.to_json(value : Output, json : JSON::Builder)
          value.to_json_value.to_json(json)
        end
      end

      enum ResponseObject
        Response

        def to_wire : String
          "response"
        end
      end

      enum ResponseStatus
        InProgress
        Completed
        Failed
        Cancelled
        Queued
        Incomplete

        def to_wire : String
          case self
          in .in_progress?
            "in_progress"
          in .completed?
            "completed"
          in .failed?
            "failed"
          in .cancelled?
            "cancelled"
          in .queued?
            "queued"
          in .incomplete?
            "incomplete"
          end
        end
      end

      struct IncompleteDetailsReason
        include JSON::Serializable

        getter reason : String

        def initialize(@reason : String = "")
        end
      end

      struct ResponseError
        include JSON::Serializable

        getter code : String
        getter message : String

        def initialize(@code : String = "", @message : String = "")
        end
      end

      struct CompletionResponsePayload
        include JSON::Serializable
        include JSON::Serializable::Unmapped

        getter id : String
        @[JSON::Field(converter: Crig::Providers::OpenAI::ResponseObjectConverter)]
        getter object : ResponseObject
        @[JSON::Field(key: "created_at")]
        getter created_at : Int64
        @[JSON::Field(converter: Crig::Providers::OpenAI::ResponseStatusConverter)]
        getter status : ResponseStatus
        getter error : ResponseError?
        @[JSON::Field(key: "incomplete_details")]
        getter incomplete_details : IncompleteDetailsReason?
        getter instructions : String?
        @[JSON::Field(key: "max_output_tokens")]
        getter max_output_tokens : Int64?
        getter model : String
        getter usage : ResponsesUsage?
        @[JSON::Field(converter: JSON::ArrayConverter(Crig::Providers::OpenAI::OutputConverter))]
        getter output : Array(Output)
        getter tools : Array(ResponsesToolDefinition)

        def initialize(
          @id : String,
          @object : ResponseObject,
          @created_at : Int64,
          @status : ResponseStatus,
          @error : ResponseError? = nil,
          @incomplete_details : IncompleteDetailsReason? = nil,
          @instructions : String? = nil,
          @max_output_tokens : Int64? = nil,
          @model : String = "",
          @usage : ResponsesUsage? = nil,
          @output : Array(Output) = [] of Output,
          @tools : Array(ResponsesToolDefinition) = [] of ResponsesToolDefinition,
        )
        end

        def additional_parameters : JSON::Any
          JSON.parse(json_unmapped.to_json)
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end

        def to_completion_response : Crig::Completion::CompletionResponse(JSON::Any)
          raise Crig::Completion::CompletionError.new("Response contained no parts") if @output.empty?

          content = @output.flat_map(&.to_assistant_content)
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") if content.empty?

          Crig::Completion::CompletionResponse(JSON::Any).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
            @usage.try(&.to_crig_usage) || Crig::Completion::Usage.new,
            to_json_value,
            @output.compact_map(&.message_id).first? || @id,
          )
        end
      end

      struct ResponsesToolDefinition
        include JSON::Serializable

        getter name : String
        getter parameters : JSON::Any
        getter? strict : Bool
        @[JSON::Field(key: "type")]
        getter kind : String
        getter description : String
        include JSON::Serializable::Unmapped

        def initialize(
          @name : String,
          @parameters : JSON::Any,
          @description : String,
          @strict : Bool = true,
          @kind : String = "function",
        )
        end

        def self.from_tool_definition(tool : Crig::Completion::ToolDefinition) : self
          new(
            name: tool.name,
            parameters: OpenAI.sanitize_schema(tool.parameters),
            description: tool.description,
          )
        end

        def self.function(name : String, description : String, parameters : JSON::Any) : self
          new(
            name: name,
            parameters: OpenAI.sanitize_schema(parameters),
            description: description,
            strict: true,
            kind: "function",
          )
        end

        def self.hosted(kind : String) : self
          new(
            name: "",
            parameters: JSON.parse("null"),
            description: "",
            strict: false,
            kind: kind,
          )
        end

        def self.web_search : self
          hosted("web_search")
        end

        def self.file_search : self
          hosted("file_search")
        end

        def self.computer_use : self
          hosted("computer_use")
        end

        def with_config(key : String, value : JSON::Any) : self
          mapped = json_unmapped.dup
          mapped[key] = value
          copy = self.class.from_json(to_json_value.to_json)
          mapped.each { |config_key, config_value| copy.json_unmapped[config_key] = config_value }
          copy
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      enum OutputRole
        Assistant

        def to_wire : String
          "assistant"
        end
      end

      module OutputRoleConverter
        def self.from_json(pull : JSON::PullParser) : OutputRole
          OutputRole.parse(pull.read_string.camelcase)
        end

        def self.to_json(value : OutputRole, json : JSON::Builder)
          json.string(value.to_wire)
        end
      end

      struct OutputMessage
        include JSON::Serializable

        getter id : String
        @[JSON::Field(converter: Crig::Providers::OpenAI::OutputRoleConverter)]
        getter role : OutputRole
        @[JSON::Field(converter: Crig::Providers::OpenAI::ResponseStatusConverter)]
        getter status : ResponseStatus
        getter content : Array(AssistantContent)

        def initialize(
          @id : String,
          @role : OutputRole,
          @status : ResponseStatus,
          @content : Array(AssistantContent),
        )
        end
      end

      struct OutputReasoning
        include JSON::Serializable

        getter id : String
        getter summary : Array(ReasoningSummary)
        @[JSON::Field(key: "encrypted_content")]
        getter encrypted_content : String?
        @[JSON::Field(converter: Crig::Providers::OpenAI::ToolStatusConverter)]
        getter status : ToolStatus?

        def initialize(
          @id : String,
          @summary : Array(ReasoningSummary),
          @encrypted_content : String? = nil,
          @status : ToolStatus? = nil,
        )
        end

        def to_completion_content : Crig::Completion::AssistantContent
          content = @summary.map { |entry| Crig::Completion::ReasoningContent.summary(entry.text) }
          if encrypted_content = @encrypted_content
            content << Crig::Completion::ReasoningContent.encrypted(encrypted_content)
          end
          Crig::Completion::AssistantContent.new(
            Crig::Completion::AssistantContent::Kind::Reasoning,
            reasoning: Crig::Completion::Reasoning.new(content, @id),
          )
        end
      end

      struct Output
        enum Kind
          Message
          FunctionCall
          Reasoning
        end

        getter kind : Kind
        getter message : OutputMessage?
        getter function_call : OutputFunctionCall?
        getter reasoning : OutputReasoning?

        def initialize(
          @kind : Kind,
          @message : OutputMessage? = nil,
          @function_call : OutputFunctionCall? = nil,
          @reasoning : OutputReasoning? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "message"
            new(Kind::Message, message: OutputMessage.from_json(value.to_json))
          when "function_call"
            new(Kind::FunctionCall, function_call: OutputFunctionCall.from_json(value.to_json))
          when "reasoning"
            new(Kind::Reasoning, reasoning: OutputReasoning.from_json(value.to_json))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI output type: #{value["type"].as_s}")
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .message?
            message = @message || raise Crig::Completion::CompletionError.new("Missing OpenAI output message")
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "message"
                json.field "id", message.id
                json.field "role", message.role.to_wire
                json.field "status", message.status.to_wire
                json.field "content" do
                  json.array do
                    message.content.each do |content|
                      content.to_json_value.to_json(json)
                    end
                  end
                end
              end
            end
          in .function_call?
            function_call = @function_call || raise Crig::Completion::CompletionError.new("Missing OpenAI output function call")
            function_call.to_json_value
          in .reasoning?
            reasoning = @reasoning || raise Crig::Completion::CompletionError.new("Missing OpenAI output reasoning")
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "reasoning"
                json.field "id", reasoning.id
                json.field "summary" do
                  json.array do
                    reasoning.summary.each do |summary|
                      summary.to_json_value.to_json(json)
                    end
                  end
                end
                json.field "encrypted_content", reasoning.encrypted_content
                json.field "status", reasoning.status.try(&.to_wire)
              end
            end
          end
        end

        def to_assistant_content : Array(Crig::Completion::AssistantContent)
          case @kind
          in .message?
            message = @message || raise Crig::Completion::CompletionError.new("Missing OpenAI output message")
            message.content.map(&.to_completion_content)
          in .function_call?
            function_call = @function_call || raise Crig::Completion::CompletionError.new("Missing OpenAI output function call")
            [Crig::Completion::AssistantContent.tool_call_with_call_id(
              function_call.id,
              function_call.call_id,
              function_call.name,
              function_call.arguments,
            )]
          in .reasoning?
            reasoning = @reasoning || raise Crig::Completion::CompletionError.new("Missing OpenAI output reasoning")
            [reasoning.to_completion_content]
          end
        end

        def message_id : String?
          if message = @message
            message.id
          end
        end
      end

      struct ReasoningSummary
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String = "summary_text"
        getter text : String

        def initialize(@text : String)
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      enum ToolResultContentType
        Text

        def to_wire : String
          "text"
        end
      end

      struct OpenAIReasoning
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String = "reasoning"
        getter id : String
        getter summary : Array(ReasoningSummary)
        @[JSON::Field(key: "encrypted_content")]
        getter encrypted_content : String?
        @[JSON::Field(converter: Crig::Providers::OpenAI::ToolStatusConverter)]
        getter status : ToolStatus?

        def initialize(
          @id : String,
          @summary : Array(ReasoningSummary),
          @encrypted_content : String? = nil,
          @status : ToolStatus? = nil,
        )
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end

        def self.from_core(reasoning : Crig::Completion::Reasoning) : self
          id = reasoning.id || raise Crig::Completion::CompletionError.new("An OpenAI-generated ID is required when using OpenAI reasoning items")
          summary = [] of ReasoningSummary
          encrypted_content = nil.as(String?)

          reasoning.content.each do |content|
            case content.kind
            in .text?
              summary << ReasoningSummary.new(content.text || "")
            in .summary?
              summary << ReasoningSummary.new(content.summary || "")
            in .encrypted?, .redacted?
              encrypted_content ||= content.data
            end
          end

          new(id, summary, encrypted_content)
        end
      end

      struct OutputFunctionCall
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String = "function_call"
        getter arguments : JSON::Any
        @[JSON::Field(key: "call_id")]
        getter call_id : String
        getter id : String
        getter name : String
        @[JSON::Field(converter: Crig::Providers::OpenAI::ToolStatusConverter)]
        getter status : ToolStatus

        def initialize(
          @arguments : JSON::Any,
          @call_id : String,
          @id : String,
          @name : String,
          @status : ToolStatus = ToolStatus::Completed,
        )
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      struct ToolResult
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String = "function_call_output"
        @[JSON::Field(key: "call_id")]
        getter call_id : String
        getter output : String
        @[JSON::Field(converter: Crig::Providers::OpenAI::ToolStatusConverter)]
        getter status : ToolStatus

        def initialize(
          @call_id : String,
          @output : String,
          @status : ToolStatus = ToolStatus::Completed,
        )
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      struct InputAudio
        getter data : String
        getter format : String

        def initialize(@data : String, @format : String)
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              json.field "input_audio" do
                json.object do
                  json.field "data", @data
                  json.field "format", @format
                end
              end
              json.field "type", "audio"
            end
          end
        end
      end

      struct SystemContent
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String = "input_text"
        getter text : String

        def initialize(@text : String)
        end

        def self.text(text : String) : self
          new(text)
        end

        def self.from_string(text : String) : self
          new(text)
        end

        def self.from_json_value(value : JSON::Any) : self
          from_json(value.to_json)
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json)
        end
      end

      struct UserContent
        enum Kind
          InputText
          InputImage
          InputFile
          Audio
          ToolResult
        end

        getter kind : Kind
        getter text : String?
        getter image_url : String?
        getter detail : String?
        getter file_url : String?
        getter file_data : String?
        getter filename : String?
        getter input_audio : InputAudio?
        getter tool_call_id : String?
        getter output : String?

        def initialize(
          @kind : Kind,
          @text : String? = nil,
          @image_url : String? = nil,
          @detail : String? = nil,
          @file_url : String? = nil,
          @file_data : String? = nil,
          @filename : String? = nil,
          @input_audio : InputAudio? = nil,
          @tool_call_id : String? = nil,
          @output : String? = nil,
        )
        end

        def self.text(text : String) : self
          new(Kind::InputText, text: text)
        end

        def self.from_string(text : String) : self
          text(text)
        end

        def self.image(image_url : String, detail : String = "auto") : self
          new(Kind::InputImage, image_url: image_url, detail: detail)
        end

        def self.file(file_url : String? = nil, file_data : String? = nil, filename : String? = nil) : self
          new(Kind::InputFile, file_url: file_url, file_data: file_data, filename: filename)
        end

        def self.audio(input_audio : InputAudio) : self
          new(Kind::Audio, input_audio: input_audio)
        end

        def self.tool_result(tool_call_id : String, output : String) : self
          new(Kind::ToolResult, tool_call_id: tool_call_id, output: output)
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "input_text"
            text(value["text"].as_s)
          when "input_image"
            image(value["image_url"].as_s, value["detail"]?.try(&.as_s?) || "auto")
          when "input_file"
            file(
              file_url: value["file_url"]?.try(&.as_s?),
              file_data: value["file_data"]?.try(&.as_s?),
              filename: value["filename"]?.try(&.as_s?),
            )
          when "audio"
            input_audio = value["input_audio"]
            audio(InputAudio.new(
              input_audio["data"].as_s,
              input_audio["format"].as_s,
            ))
          when "tool"
            tool_result(value["tool_call_id"].as_s, value["output"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI user content type: #{value["type"].as_s}")
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .input_text?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "input_text"
                json.field "text", @text
              end
            end
          in .input_image?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "input_image"
                json.field "image_url", @image_url
                json.field "detail", @detail || "auto"
              end
            end
          in .input_file?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "input_file"
                json.field "file_url", @file_url
                json.field "file_data", @file_data
                json.field "filename", @filename
              end
            end
          in .audio?
            input_audio = @input_audio || raise Crig::Completion::CompletionError.new("Missing OpenAI input audio content")
            input_audio.to_json_value
          in .tool_result?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "tool"
                json.field "tool_call_id", @tool_call_id
                json.field "output", @output
              end
            end
          end
        end
      end

      struct AssistantContent
        include JSON::Serializable

        enum Kind
          OutputText
          Refusal
        end

        getter kind : Kind
        getter text : String

        def initialize(@kind : Kind, @text : String)
        end

        def initialize(pull : JSON::PullParser)
          kind = nil.as(Kind?)
          text = nil.as(String?)

          pull.read_object do |key|
            case key
            when "type"
              kind = case pull.read_string
                     when "output_text"
                       Kind::OutputText
                     when "refusal"
                       Kind::Refusal
                     else
                       raise Crig::Completion::CompletionError.new("Unsupported OpenAI assistant content type")
                     end
            when "text"
              text = pull.read_string
            when "refusal"
              text = pull.read_string
            else
              pull.skip
            end
          end

          @kind = kind || raise Crig::Completion::CompletionError.new("Missing OpenAI assistant content type")
          @text = text || ""
        end

        def self.output_text(text : String) : self
          new(Kind::OutputText, text)
        end

        def self.refusal(text : String) : self
          new(Kind::Refusal, text)
        end

        def self.from_json_value(value : JSON::Any) : self
          from_json(value.to_json)
        end

        def to_completion_content : Crig::Completion::AssistantContent
          case @kind
          in .output_text?
            Crig::Completion::AssistantContent.text(@text)
          in .refusal?
            Crig::Completion::AssistantContent.text(@text)
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .output_text?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "output_text"
                json.field "text", @text
              end
            end
          in .refusal?
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", "refusal"
                json.field "refusal", @text
              end
            end
          end
        end
      end

      struct AssistantContentType
        enum Kind
          Text
          ToolCall
          Reasoning
        end

        getter kind : Kind
        getter text : AssistantContent?
        getter tool_call : OutputFunctionCall?
        getter reasoning : OpenAIReasoning?

        def initialize(
          @kind : Kind,
          @text : AssistantContent? = nil,
          @tool_call : OutputFunctionCall? = nil,
          @reasoning : OpenAIReasoning? = nil,
        )
        end

        def self.text(text : AssistantContent) : self
          new(Kind::Text, text: text)
        end

        def self.tool_call(tool_call : OutputFunctionCall) : self
          new(Kind::ToolCall, tool_call: tool_call)
        end

        def self.reasoning(reasoning : OpenAIReasoning) : self
          new(Kind::Reasoning, reasoning: reasoning)
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "output_text", "refusal"
            text(AssistantContent.from_json_value(value))
          when "function_call"
            tool_call(OutputFunctionCall.from_json(value.to_json))
          when "reasoning"
            reasoning(OpenAIReasoning.from_json(value.to_json))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI assistant content type: #{value["type"].as_s}")
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .text?
            text = @text || raise Crig::Completion::CompletionError.new("Missing OpenAI assistant text content")
            text.to_json_value
          in .tool_call?
            tool_call = @tool_call || raise Crig::Completion::CompletionError.new("Missing OpenAI assistant tool call content")
            tool_call.to_json_value
          in .reasoning?
            reasoning = @reasoning || raise Crig::Completion::CompletionError.new("Missing OpenAI assistant reasoning content")
            reasoning.to_json_value
          end
        end
      end

      struct Message
        enum Kind
          System
          User
          Assistant
          ToolResult
        end

        getter kind : Kind
        getter system_content : Array(SystemContent)?
        getter user_content : Array(UserContent)?
        getter assistant_content : Array(AssistantContentType)?
        getter tool_call_id : String?
        getter output : String?
        getter id : String?
        getter name : String?
        getter status : ToolStatus?

        def initialize(
          @kind : Kind,
          @system_content : Array(SystemContent)? = nil,
          @user_content : Array(UserContent)? = nil,
          @assistant_content : Array(AssistantContentType)? = nil,
          @tool_call_id : String? = nil,
          @output : String? = nil,
          @id : String? = nil,
          @name : String? = nil,
          @status : ToolStatus? = nil,
        )
        end

        def self.system(content : String) : self
          new(Kind::System, system_content: [SystemContent.from_string(content)])
        end

        def self.user(content : Array(UserContent)) : self
          new(Kind::User, user_content: content)
        end

        def self.assistant(content : Array(AssistantContentType), id : String, status : ToolStatus = ToolStatus::Completed) : self
          new(Kind::Assistant, assistant_content: content, id: id, status: status)
        end

        def self.tool_result(tool_call_id : String, output : String) : self
          new(Kind::ToolResult, tool_call_id: tool_call_id, output: output)
        end

        def self.from_json_value(value : JSON::Any) : self
          role = value["role"]?.try(&.as_s?) || "tool"
          case role
          when "developer", "system"
            system_contents = parse_system_contents(value["content"])
            new(Kind::System, system_content: system_contents, name: value["name"]?.try(&.as_s?))
          when "user"
            user_contents = parse_user_contents(value["content"])
            new(Kind::User, user_content: user_contents, name: value["name"]?.try(&.as_s?))
          when "assistant"
            assistant_contents = value["content"].as_a.map { |entry| AssistantContentType.from_json_value(entry) }
            new(
              Kind::Assistant,
              assistant_content: assistant_contents,
              id: value["id"]?.try(&.as_s?),
              name: value["name"]?.try(&.as_s?),
              status: value["status"]?.try(&.as_s?).try { |wire| ToolStatus.parse(wire.camelcase) },
            )
          when "tool"
            tool_result(value["tool_call_id"].as_s, value["output"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI message role: #{role}")
          end
        end

        def role : Role
          case @kind
          in .system?
            Role::System
          in .user?
            Role::User
          in .assistant?
            Role::Assistant
          in .tool_result?
            Role::User
          end
        end

        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          case message.role
          in .user?
            from_core_user_message(message)
          in .assistant?
            from_core_assistant_message(message)
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .system?
            build_message_json(Role::System, (@system_content || [] of SystemContent).map(&.to_json_value))
          in .user?
            build_message_json(Role::User, (@user_content || [] of UserContent).map(&.to_json_value))
          in .assistant?
            build_message_json(Role::Assistant, (@assistant_content || [] of AssistantContentType).map(&.to_json_value))
          in .tool_result?
            JSON.parse({
              "type"         => "tool",
              "tool_call_id" => @tool_call_id,
              "output"       => @output,
            }.to_json)
          end
        end

        private def build_message_json(role : Role, content : Array(JSON::Any)) : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              json.field "type", "message"
              json.field "role", role.to_wire
              json.field "content" do
                json.array do
                  content.each do |entry|
                    entry.to_json(json)
                  end
                end
              end
              if id = @id
                json.field "id", id
              end
              if name = @name
                json.field "name", name
              end
              if status = @status
                json.field "status", status.to_wire
              end
            end
          end
        end

        private def self.parse_system_contents(value : JSON::Any) : Array(SystemContent)
          if text = value.as_s?
            [SystemContent.from_string(text)]
          else
            value.as_a.map { |entry| SystemContent.from_json_value(entry) }
          end
        end

        private def self.parse_user_contents(value : JSON::Any) : Array(UserContent)
          if text = value.as_s?
            [UserContent.from_string(text)]
          else
            value.as_a.map { |entry| UserContent.from_json_value(entry) }
          end
        end

        private def self.from_core_user_message(message : Crig::Completion::Message) : Array(self)
          user_contents = message.content.to_a.compact_map(&.as?(Crig::Completion::UserContent))
          tool_results, other_contents = user_contents.partition(&.kind.tool_result?)

          if !tool_results.empty?
            return tool_results.map do |content|
              tool_result = content.tool_result || raise Crig::Completion::CompletionError.new("Missing tool result content")
              entry = tool_result.content.first
              output = entry.text.try(&.text) || raise Crig::Completion::CompletionError.new("This API only currently supports text tool results")
              tool_result(
                OpenAI.require_call_id(tool_result.call_id, "Tool result"),
                output,
              )
            end
          end

          converted = other_contents.map { |content| InputItem.convert_user_content(content) }
          raise Crig::Completion::CompletionError.new("User message did not contain OpenAI Responses-compatible content") if converted.empty?
          [user(converted)]
        end

        private def self.from_core_assistant_message(message : Crig::Completion::Message) : Array(self)
          assistant_id = message.id || raise Crig::Completion::CompletionError.new("Assistant message ID is required for OpenAI Responses API")
          assistant_content = message.content.first.as?(Crig::Completion::AssistantContent)
          return [] of self unless assistant_content

          case assistant_content.kind
          in .text?
            text = assistant_content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
            [assistant([AssistantContentType.text(AssistantContent.output_text(text.text))], assistant_id)]
          in .tool_call?
            tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool call content")
            call_id = OpenAI.require_call_id(tool_call.call_id, "Assistant tool call")
            [assistant([
              AssistantContentType.tool_call(
                OutputFunctionCall.new(
                  tool_call.function.arguments,
                  call_id,
                  tool_call.id,
                  tool_call.function.name
                )
              ),
            ], assistant_id)]
          in .reasoning?
            reasoning = assistant_content.reasoning || raise Crig::Completion::CompletionError.new("Missing assistant reasoning content")
            [assistant([AssistantContentType.reasoning(OpenAIReasoning.from_core(reasoning))], assistant_id)]
          in .image?
            raise Crig::Completion::CompletionError.new("Assistant image content is not supported in OpenAI Responses API")
          end
        end
      end

      struct InputContent
        enum Kind
          Message
          Reasoning
          FunctionCall
          FunctionCallOutput
        end

        getter kind : Kind
        getter message : Message?
        getter reasoning : OpenAIReasoning?
        getter function_call : OutputFunctionCall?
        getter function_call_output : ToolResult?

        def initialize(
          @kind : Kind,
          @message : Message? = nil,
          @reasoning : OpenAIReasoning? = nil,
          @function_call : OutputFunctionCall? = nil,
          @function_call_output : ToolResult? = nil,
        )
        end

        def self.message(message : Message) : self
          new(Kind::Message, message: message)
        end

        def self.reasoning(reasoning : OpenAIReasoning) : self
          new(Kind::Reasoning, reasoning: reasoning)
        end

        def self.function_call(function_call : OutputFunctionCall) : self
          new(Kind::FunctionCall, function_call: function_call)
        end

        def self.function_call_output(function_call_output : ToolResult) : self
          new(Kind::FunctionCallOutput, function_call_output: function_call_output)
        end

        def self.from_json_value(value : JSON::Any) : self
          case value["type"].as_s
          when "message"
            message(Message.from_json_value(value))
          when "reasoning"
            reasoning(OpenAIReasoning.from_json(value.to_json))
          when "function_call"
            function_call(OutputFunctionCall.from_json(value.to_json))
          when "function_call_output"
            function_call_output(ToolResult.from_json(value.to_json))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenAI input content type: #{value["type"].as_s}")
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .message?
            message = @message || raise Crig::Completion::CompletionError.new("Missing OpenAI message input content")
            message.to_json_value
          in .reasoning?
            reasoning = @reasoning || raise Crig::Completion::CompletionError.new("Missing OpenAI reasoning input content")
            reasoning.to_json_value
          in .function_call?
            function_call = @function_call || raise Crig::Completion::CompletionError.new("Missing OpenAI function call input content")
            function_call.to_json_value
          in .function_call_output?
            function_call_output = @function_call_output || raise Crig::Completion::CompletionError.new("Missing OpenAI function call output input content")
            function_call_output.to_json_value
          end
        end
      end

      struct InputItem
        getter role : Role?
        getter input : InputContent

        def initialize(@input : InputContent, @role : Role? = nil)
        end

        def self.system_message(content : String) : self
          new(InputContent.message(Message.system(content)), Role::System)
        end

        def self.from_completion_message(message : Crig::Completion::Message) : Array(self)
          case message.role
          in .user?
            from_user_message(message)
          in .assistant?
            from_assistant_message(message)
          end
        end

        def self.from_message(message : Message) : self
          case message.kind
          in .system?
            new(InputContent.message(message), Role::System)
          in .user?
            new(InputContent.message(message), Role::User)
          in .assistant?
            assistant_content = message.assistant_content || [] of AssistantContentType
            role = assistant_content.any?(&.kind.reasoning?) ? nil : Role::Assistant
            new(InputContent.message(message), role)
          in .tool_result?
            new(
              InputContent.function_call_output(
                ToolResult.new(
                  (message.tool_call_id || raise Crig::Completion::CompletionError.new("Tool result `call_id` is required for OpenAI Responses API")),
                  message.output || raise Crig::Completion::CompletionError.new("Missing tool result output"),
                )
              )
            )
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          if value["type"].as_s == "tool"
            return from_message(Message.from_json_value(value))
          end

          if role = value["role"]?.try(&.as_s?)
            parsed_role = case role
                          when "system", "developer"
                            Role::System
                          when "user"
                            Role::User
                          when "assistant"
                            Role::Assistant
                          end
            new(
              InputContent.from_json_value(value),
              parsed_role
            )
          else
            new(InputContent.from_json_value(value))
          end
        end

        def to_json_value : JSON::Any
          if role = @role
            value = @input.to_json_value.as_h
            unless value.has_key?("role")
              value = value.merge({"role" => JSON::Any.new(role.to_wire)})
            end
            JSON.parse(value.to_json)
          else
            @input.to_json_value
          end
        end

        private def self.from_user_message(message : Crig::Completion::Message) : Array(self)
          user_contents = message.content.to_a.compact_map(&.as?(Crig::Completion::UserContent))
          tool_results, other_contents = user_contents.partition(&.kind.tool_result?)

          if tool_results.empty?
            converted = other_contents.map { |content| convert_user_content(content) }
            return [] of self if converted.empty?
            [new(InputContent.message(Message.user(converted)), Role::User)]
          else
            tool_results.flat_map do |content|
              tool_result = content.tool_result || raise Crig::Completion::CompletionError.new("Missing tool result content")
              call_id = OpenAI.require_call_id(tool_result.call_id, "Tool result")
              tool_result.content.to_a.map do |entry|
                output = entry.text.try(&.text) || raise Crig::Completion::CompletionError.new("This API only currently supports text tool results")
                new(InputContent.function_call_output(ToolResult.new(call_id, output)))
              end
            end
          end
        end

        private def self.from_assistant_message(message : Crig::Completion::Message) : Array(self)
          assistant_id = message.id || raise Crig::Completion::CompletionError.new("Assistant message ID is required for OpenAI Responses API")
          assistant_content = message.content.to_a.first?.try(&.as?(Crig::Completion::AssistantContent))
          return [] of self unless assistant_content

          item = case assistant_content.kind
                 in .text?
                   text = assistant_content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
                   new(
                     InputContent.message(
                       Message.assistant([AssistantContentType.text(AssistantContent.output_text(text.text))], assistant_id)
                     ),
                     Role::Assistant
                   )
                 in .tool_call?
                   tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool call content")
                   call_id = OpenAI.require_call_id(tool_call.call_id, "Assistant tool call")
                   new(
                     InputContent.function_call(
                       OutputFunctionCall.new(
                         tool_call.function.arguments,
                         call_id,
                         tool_call.id,
                         tool_call.function.name
                       )
                     )
                   )
                 in .reasoning?
                   reasoning = assistant_content.reasoning || raise Crig::Completion::CompletionError.new("Missing assistant reasoning content")
                   new(InputContent.reasoning(OpenAIReasoning.from_core(reasoning)))
                 in .image?
                   raise Crig::Completion::CompletionError.new("Assistant image content is not supported in OpenAI Responses API")
                 end

          [item]
        end

        def self.convert_user_content(content : Crig::Completion::UserContent) : UserContent
          case content.kind
          in .text?
            UserContent.text(content.text.try(&.text) || "")
          in .document?
            document = content.document || raise Crig::Completion::CompletionError.new("Missing document content")
            convert_document_content(document)
          in .image?
            image = content.image || raise Crig::Completion::CompletionError.new("Missing image content")
            convert_image_content(image)
          in .audio?
            audio = content.audio || raise Crig::Completion::CompletionError.new("Missing audio content")
            convert_audio_content(audio)
          in .tool_result?
            raise Crig::Completion::CompletionError.new("Tool results should be partitioned before content conversion")
          in .video?
            raise Crig::Completion::CompletionError.new("Unsupported message: #{content.kind}")
          end
        end

        private def self.convert_document_content(document : Crig::Completion::Document) : UserContent
          case document.data.kind
          in .base64?, .string?
            UserContent.text(document.data.string_value || "")
          in .url?
            if document.media_type == Crig::Completion::DocumentMediaType::PDF
              UserContent.file(file_url: document.data.string_value || "", filename: "document.pdf")
            else
              raise Crig::Completion::CompletionError.new("Unsupported document type: #{document.data.kind}")
            end
          in .raw?, .file_id?, .unknown?
            raise Crig::Completion::CompletionError.new("Raw file data not supported, encode as base64 first")
          end
        end

        private def self.convert_image_content(image : Crig::Completion::Image) : UserContent
          url = case image.data.kind
                in .base64?
                  media_type = image.media_type.try { |value| Crig::Completion::MimeType.image_to_mime_type(value) } || ""
                  "data:#{media_type};base64,#{image.data.string_value}"
                in .url?
                  image.data.string_value || ""
                in .raw?, .string?, .file_id?, .unknown?
                  raise Crig::Completion::CompletionError.new("Raw file data not supported, encode as base64 first")
                end

          UserContent.image(url, image.detail.try(&.to_s.downcase) || "auto")
        end

        private def self.convert_audio_content(audio : Crig::Completion::Audio) : UserContent
          case audio.data.kind
          in .base64?
            UserContent.audio(InputAudio.new(
              audio.data.string_value || "",
              Crig::Completion::MimeType.audio_to_mime_type(audio.media_type || Crig::Completion::AudioMediaType::MP3).sub("audio/", "")
            ))
          in .url?, .raw?, .file_id?, .string?, .unknown?
            raise Crig::Completion::CompletionError.new("Unsupported message: #{audio.data.kind}")
          end
        end
      end

      struct CompletionRequest
        getter input : Crig::OneOrMany(InputItem)
        getter model : String
        getter instructions : String?
        getter max_output_tokens : Int64?
        getter stream : Bool?
        getter temperature : Float64?
        getter tool_choice : JSON::Any?
        getter tools : Array(ResponsesToolDefinition)
        getter additional_parameters : AdditionalParameters

        def initialize(
          @input : Crig::OneOrMany(InputItem),
          @model : String,
          @instructions : String? = nil,
          @max_output_tokens : Int64? = nil,
          @stream : Bool? = nil,
          @temperature : Float64? = nil,
          @tool_choice : JSON::Any? = nil,
          @tools : Array(ResponsesToolDefinition) = [] of ResponsesToolDefinition,
          @additional_parameters : AdditionalParameters = AdditionalParameters.new,
        )
        end

        def with_structured_outputs(schema_name : String, schema : JSON::Any) : self
          self.class.new(
            input: @input,
            model: @model,
            instructions: @instructions,
            max_output_tokens: @max_output_tokens,
            stream: @stream,
            temperature: @temperature,
            tool_choice: @tool_choice,
            tools: @tools,
            additional_parameters: @additional_parameters.with_text(TextConfig.structured_output(schema_name, schema)),
          )
        end

        def with_reasoning(reasoning : Reasoning) : self
          self.class.new(
            input: @input,
            model: @model,
            instructions: @instructions,
            max_output_tokens: @max_output_tokens,
            stream: @stream,
            temperature: @temperature,
            tool_choice: @tool_choice,
            tools: @tools,
            additional_parameters: @additional_parameters.with_reasoning(reasoning),
          )
        end

        def with_tool(tool : ResponsesToolDefinition) : self
          self.class.new(
            input: @input,
            model: @model,
            instructions: @instructions,
            max_output_tokens: @max_output_tokens,
            stream: @stream,
            temperature: @temperature,
            tool_choice: @tool_choice,
            tools: @tools + [tool],
            additional_parameters: @additional_parameters,
          )
        end

        def with_tools(tools : Enumerable(ResponsesToolDefinition)) : self
          tools.reduce(self) { |request, tool| request.with_tool(tool) }
        end

        def with_stream(stream : Bool) : self
          self.class.new(
            input: @input,
            model: @model,
            instructions: @instructions,
            max_output_tokens: @max_output_tokens,
            stream: stream,
            temperature: @temperature,
            tool_choice: @tool_choice,
            tools: @tools,
            additional_parameters: @additional_parameters,
          )
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              json.field "input" do
                json.array do
                  @input.each do |item|
                    item.to_json_value.to_json(json)
                  end
                end
              end
              json.field "model", @model
              if instructions = @instructions
                json.field "instructions", instructions
              end
              if max_output_tokens = @max_output_tokens
                json.field "max_output_tokens", max_output_tokens
              end
              if stream = @stream
                json.field "stream", stream
              end
              if temperature = @temperature
                json.field "temperature", temperature
              end
              if tool_choice = @tool_choice
                json.field "tool_choice" do
                  tool_choice.to_json(json)
                end
              end
              unless @tools.empty?
                json.field "tools" do
                  json.array do
                    @tools.each do |tool|
                      tool.to_json_value.to_json(json)
                    end
                  end
                end
              end
              @additional_parameters.to_json_value.as_h.each do |key, value|
                json.field key do
                  value.to_json(json)
                end
              end
            end
          end
        end
      end

      struct ResponsesCompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.with_model(client : Client, model : String) : self
          new(client, model)
        end

        def with_model(model : String) : self
          self.class.new(@client, model)
        end

        def completions_api : Crig::Providers::OpenAI::CompletionModel
          @client.completions_api.completion_model(@model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          payload = create_completion_request(request)
          response = @client.post_json("/responses", payload.to_json_value.to_json)
          text = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(text)
          end

          body = CompletionResponsePayload.from_json(text)
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end

          parse_completion_response(body)
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = create_completion_request(request).with_stream(true).to_json_value.as_h
          response = @client.post_json(
            "/responses",
            payload.to_json,
            {"Accept" => "text/event-stream"}
          )
          text = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(text)
          end

          raw_choices = parse_streaming_choices(text)
          Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse).stream_raw_choices(raw_choices)
        end

        def create_completion_request(request : Crig::Completion::Request::CompletionRequest) : CompletionRequest
          input_items = [] of InputItem
          if preamble = request.preamble
            input_items << InputItem.system_message(preamble)
          end

          if documents = request.normalized_documents
            input_items.concat(InputItem.from_completion_message(documents))
          end

          request.chat_history.each do |message|
            input_items.concat(InputItem.from_completion_message(message))
          end

          raise Crig::Completion::CompletionError.new("OpenAI Responses request input must contain at least one item") if input_items.empty?

          additional_parameters = if additional_params = request.additional_params
                                    parse_additional_parameters(additional_params)
                                  else
                                    AdditionalParameters.new
                                  end
          additional_parameters = additional_parameters.ensure_reasoning_include

          completion_request = CompletionRequest.new(
            input: Crig::OneOrMany(InputItem).many(input_items),
            model: request.model || @model,
            max_output_tokens: request.max_tokens,
            temperature: request.temperature,
            tool_choice: convert_tool_choice(request.tool_choice),
            tools: request.tools.map { |tool| ResponsesToolDefinition.from_tool_definition(tool) },
            additional_parameters: additional_parameters,
          )

          if output_schema = request.output_schema
            completion_request = completion_request.with_structured_outputs(
              request.output_schema_name || "response_schema",
              OpenAI.sanitize_schema(output_schema)
            )
          end

          completion_request
        end

        private def parse_additional_parameters(value : JSON::Any) : AdditionalParameters
          unless value.raw.is_a?(Hash)
            raise Crig::Completion::CompletionError.new("Invalid OpenAI Responses additional_params payload")
          end

          AdditionalParameters.from_json_value(value)
        end

        private def convert_tool_choice(tool_choice : Crig::Completion::ToolChoice?) : JSON::Any?
          return unless tool_choice

          case tool_choice.kind
          in .auto?
            JSON::Any.new("auto")
          in .none?
            JSON::Any.new("none")
          in .required?
            JSON::Any.new("required")
          in .specific?
            raise Crig::Completion::CompletionError.new("Provider doesn't support only using specific tools")
          end
        end

        private def parse_completion_response(body : CompletionResponsePayload) : Crig::Completion::CompletionResponse(JSON::Any)
          body.to_completion_response
        end

        private def parse_usage(value : JSON::Any?) : Crig::Completion::Usage
          return Crig::Completion::Usage.new unless value
          ResponsesUsage.from_json(value.to_json).to_crig_usage
        end

        private def merge_json_hashes(
          left : Hash(String, JSON::Any),
          right : Hash(String, JSON::Any),
        ) : Hash(String, JSON::Any)
          merged = left.dup
          right.each do |key, value|
            merged[key] = if existing = merged[key]?
                            merge_json_values(existing, value)
                          else
                            value
                          end
          end
          merged
        end

        private def merge_json_values(left : JSON::Any, right : JSON::Any) : JSON::Any
          left_hash = left.as_h?
          right_hash = right.as_h?
          return right unless left_hash && right_hash
          JSON.parse(merge_json_hashes(left_hash, right_hash).to_json)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::OpenAI::ResponsesCompletionModel)

        def completion_model(model : String) : Crig::Providers::OpenAI::ResponsesCompletionModel
          Crig::Providers::OpenAI::ResponsesCompletionModel.new(self, model)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
        end

        private def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end
    end
  end
end
