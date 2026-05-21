require "uri"

module Crig
  module Providers
    module Gemini
      module Interactions
        struct AdditionalParameters
          include JSON::Serializable

          getter agent : String?
          @[JSON::Field(key: "agent_config")]
          getter agent_config : AgentConfig?
          getter background : Bool?
          @[JSON::Field(key: "generation_config")]
          getter generation_config : GenerationConfig?
          @[JSON::Field(key: "previous_interaction_id")]
          getter previous_interaction_id : String?
          @[JSON::Field(key: "response_modalities")]
          getter response_modalities : Array(ResponseModality)?
          @[JSON::Field(key: "response_format")]
          getter response_format : JSON::Any?
          @[JSON::Field(key: "response_mime_type")]
          getter response_mime_type : String?
          getter store : Bool?
          getter stream : Bool?
          @[JSON::Field(key: "system_instruction")]
          getter system_instruction : String?
          getter tools : Array(Tool)?
          @[JSON::Field(ignore: true)]
          getter additional_params : JSON::Any?

          def initialize(
            @agent : String? = nil,
            @agent_config : AgentConfig? = nil,
            @background : Bool? = nil,
            @generation_config : GenerationConfig? = nil,
            @previous_interaction_id : String? = nil,
            @response_modalities : Array(ResponseModality)? = nil,
            @response_format : JSON::Any? = nil,
            @response_mime_type : String? = nil,
            @store : Bool? = nil,
            @stream : Bool? = nil,
            @system_instruction : String? = nil,
            @tools : Array(Tool)? = nil,
            @additional_params : JSON::Any? = nil,
          )
          end

          def self.from_json_value(value : JSON::Any) : self
            hash = value.as_h
            known = {
              "agent", "agent_config", "background", "generation_config", "previous_interaction_id",
              "response_modalities", "response_format", "response_mime_type", "store", "stream",
              "system_instruction", "tools",
            }
            additional = hash.reject { |key, _| known.includes?(key) }
            new(
              agent: hash["agent"]?.try(&.as_s?),
              agent_config: hash["agent_config"]?.try { |entry| AgentConfig.from_json(entry.to_json) },
              background: hash["background"]?.try(&.as_bool?),
              generation_config: hash["generation_config"]?.try { |entry| GenerationConfig.from_json(entry.to_json) },
              previous_interaction_id: hash["previous_interaction_id"]?.try(&.as_s?),
              response_modalities: hash["response_modalities"]?.try { |entry| Array(ResponseModality).from_json(entry.to_json) },
              response_format: hash["response_format"]?,
              response_mime_type: hash["response_mime_type"]?.try(&.as_s?),
              store: hash["store"]?.try(&.as_bool?),
              stream: hash["stream"]?.try(&.as_bool?),
              system_instruction: hash["system_instruction"]?.try(&.as_s?),
              tools: hash["tools"]?.try { |entry| Array(Tool).from_json(entry.to_json) },
              additional_params: additional.empty? ? nil : JSON.parse(additional.to_json),
            )
          end
        end

        enum ResponseModality
          Text
          Image
          Audio

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.downcase)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string)
          end
        end

        enum ThinkingLevel
          Minimal
          Low
          Medium
          High

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.downcase)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string)
          end
        end

        enum ThinkingSummaries
          Auto
          None

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.downcase)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string)
          end
        end

        enum ToolChoiceType
          Auto
          Any
          None
          Validated

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.underscore)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string.camelcase)
          end
        end

        struct AllowedTools
          include JSON::Serializable

          getter mode : ToolChoiceType?
          getter tools : Array(String)?

          def initialize(@mode : ToolChoiceType? = nil, @tools : Array(String)? = nil)
          end
        end

        struct ToolChoiceConfig
          include JSON::Serializable

          @[JSON::Field(key: "allowed_tools")]
          getter allowed_tools : AllowedTools

          def initialize(@allowed_tools : AllowedTools)
          end
        end

        struct ToolChoice
          enum Kind
            Type
            Config
          end

          getter kind : Kind
          getter type : ToolChoiceType?
          getter config : ToolChoiceConfig?

          def initialize(@kind : Kind, @type : ToolChoiceType? = nil, @config : ToolChoiceConfig? = nil)
          end

          def self.type(type : ToolChoiceType) : self
            new(Kind::Type, type: type)
          end

          def self.config(config : ToolChoiceConfig) : self
            new(Kind::Config, config: config)
          end

          def to_json(json : JSON::Builder) : Nil
            case @kind
            in .type?
              @type.as(ToolChoiceType).to_json(json)
            in .config?
              @config.as(ToolChoiceConfig).to_json(json)
            end
          end

          def self.new(pull : JSON::PullParser)
            case pull.kind
            when .string?
              type(ToolChoiceType.new(pull))
            when .begin_object?
              config(ToolChoiceConfig.new(pull))
            else
              raise Crig::Completion::CompletionError.new("Unknown Gemini interactions tool choice payload")
            end
          end

          def self.from_core(choice : Crig::Completion::ToolChoice) : self
            case choice.kind
            in .auto?
              type(ToolChoiceType::Auto)
            in .none?
              type(ToolChoiceType::None)
            in .required?
              type(ToolChoiceType::Any)
            in .specific?
              config(
                ToolChoiceConfig.new(
                  AllowedTools.new(
                    mode: ToolChoiceType::Validated,
                    tools: choice.function_names
                  )
                )
              )
            end
          end
        end

        struct SpeechConfig
          include JSON::Serializable

          getter voice : String?
          getter language : String?
          getter speaker : String?

          def initialize(@voice : String? = nil, @language : String? = nil, @speaker : String? = nil)
          end
        end

        struct GenerationConfig
          include JSON::Serializable

          property temperature : Float64?
          @[JSON::Field(key: "top_p")]
          getter top_p : Float64?
          getter seed : Int64?
          @[JSON::Field(key: "stop_sequences")]
          getter stop_sequences : Array(String)?
          @[JSON::Field(key: "tool_choice")]
          property tool_choice : ToolChoice?
          @[JSON::Field(key: "thinking_level")]
          getter thinking_level : ThinkingLevel?
          @[JSON::Field(key: "thinking_summaries")]
          getter thinking_summaries : ThinkingSummaries?
          @[JSON::Field(key: "max_output_tokens")]
          property max_output_tokens : Int64?
          @[JSON::Field(key: "speech_config")]
          getter speech_config : Array(SpeechConfig)?

          def initialize(
            @temperature : Float64? = nil,
            @top_p : Float64? = nil,
            @seed : Int64? = nil,
            @stop_sequences : Array(String)? = nil,
            @tool_choice : ToolChoice? = nil,
            @thinking_level : ThinkingLevel? = nil,
            @thinking_summaries : ThinkingSummaries? = nil,
            @max_output_tokens : Int64? = nil,
            @speech_config : Array(SpeechConfig)? = nil,
          )
          end

          def empty? : Bool
            @temperature.nil? && @top_p.nil? && @seed.nil? && @stop_sequences.nil? &&
              @tool_choice.nil? && @thinking_level.nil? && @thinking_summaries.nil? &&
              @max_output_tokens.nil? && @speech_config.nil?
          end
        end

        enum Role
          User
          Model

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.downcase)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string.camelcase)
          end
        end

        struct TurnContent
          enum Kind
            Text
            Contents
          end

          getter kind : Kind
          getter text : String?
          getter contents : Array(Content)?

          def initialize(@kind : Kind, @text : String? = nil, @contents : Array(Content)? = nil)
          end

          def self.text(text : String) : self
            new(Kind::Text, text: text)
          end

          def self.contents(contents : Array(Content)) : self
            new(Kind::Contents, contents: contents)
          end

          def to_json(json : JSON::Builder) : Nil
            case @kind
            in .text?
              json.string(@text || "")
            in .contents?
              json.array do
                @contents.try(&.each(&.to_json(json)))
              end
            end
          end
        end

        struct Annotation
          include JSON::Serializable

          @[JSON::Field(key: "start_index")]
          getter start_index : Int32?
          @[JSON::Field(key: "end_index")]
          getter end_index : Int32?
          getter source : String?

          def initialize(@start_index : Int32? = nil, @end_index : Int32? = nil, @source : String? = nil)
          end
        end

        struct Citation
          getter start_index : Int32
          getter end_index : Int32
          getter source : String

          def initialize(@start_index : Int32, @end_index : Int32, @source : String)
          end
        end

        struct TextContent
          include JSON::Serializable

          getter text : String
          getter annotations : Array(Annotation)?

          def initialize(@text : String, @annotations : Array(Annotation)? = nil)
          end

          def citations : Array(Citation)
            citations = [] of Citation
            @annotations.try &.each do |entry|
              start_index = entry.start_index
              end_index = entry.end_index
              source = entry.source
              next unless start_index && end_index && source
              next if start_index < 0 || end_index < 0 || end_index <= start_index
              next if end_index > @text.bytesize
              next unless @text.byte_index_to_char_index(start_index)
              next unless @text.byte_index_to_char_index(end_index)
              citations << Citation.new(start_index, end_index, source)
            end
            citations.sort_by { |item| {item.start_index, item.end_index} }
          end

          def with_inline_citations : String
            citations = citations()
            return @text if citations.empty?

            source_order = [] of String
            citations.each do |citation|
              source_order << citation.source unless source_order.includes?(citation.source)
            end

            inserts = citations.map do |citation|
              index = (source_order.index(citation.source) || -1) + 1
              {citation.start_index, citation.end_index, index, citation.source}
            end
            inserts.sort_by! { |tuple| {-tuple[1], -tuple[0]} }

            text = @text.dup
            inserts.each do |(_, end_index, index, source)|
              next if index <= 0
              text = "#{text[0, end_index]}[#{index}](#{source})#{text[end_index..]}"
            end
            text
          end
        end

        struct ImageContent
          include JSON::Serializable
          getter data : String?
          getter uri : String?
          @[JSON::Field(key: "mime_type")]
          getter mime_type : String?
          getter resolution : MediaResolution?

          def initialize(@data : String? = nil, @uri : String? = nil, @mime_type : String? = nil, @resolution : MediaResolution? = nil)
          end
        end

        struct AudioContent
          include JSON::Serializable
          getter data : String?
          getter uri : String?
          @[JSON::Field(key: "mime_type")]
          getter mime_type : String?

          def initialize(@data : String? = nil, @uri : String? = nil, @mime_type : String? = nil)
          end
        end

        struct DocumentContent
          include JSON::Serializable
          getter data : String?
          getter uri : String?
          @[JSON::Field(key: "mime_type")]
          getter mime_type : String?

          def initialize(@data : String? = nil, @uri : String? = nil, @mime_type : String? = nil)
          end
        end

        struct VideoContent
          include JSON::Serializable
          getter data : String?
          getter uri : String?
          @[JSON::Field(key: "mime_type")]
          getter mime_type : String?
          getter resolution : MediaResolution?

          def initialize(@data : String? = nil, @uri : String? = nil, @mime_type : String? = nil, @resolution : MediaResolution? = nil)
          end
        end

        struct ThoughtContent
          include JSON::Serializable

          getter signature : String?
          getter summary : Array(ThoughtSummaryContent)?

          def initialize(@signature : String? = nil, @summary : Array(ThoughtSummaryContent)? = nil)
          end
        end

        struct ThoughtSummaryContent
          enum Kind
            Text
            Image
          end

          getter kind : Kind
          getter text : TextContent?
          getter image : ImageContent?

          def initialize(@kind : Kind, @text : TextContent? = nil, @image : ImageContent? = nil)
          end

          def self.text(text : TextContent) : self
            new(Kind::Text, text: text)
          end

          def self.image(image : ImageContent) : self
            new(Kind::Image, image: image)
          end

          def to_json(json : JSON::Builder) : Nil
            case @kind
            in .text?
              @text.as(TextContent).to_json(json)
            in .image?
              @image.as(ImageContent).to_json(json)
            end
          end

          def self.new(pull : JSON::PullParser)
            any = JSON::Any.new(pull)
            hash = any.as_h
            if hash["text"]?
              text(TextContent.from_json(any.to_json))
            else
              image(ImageContent.from_json(any.to_json))
            end
          end
        end

        struct FunctionCallContent
          include JSON::Serializable
          getter name : String?
          getter arguments : JSON::Any?
          getter id : String?

          def initialize(@name : String? = nil, @arguments : JSON::Any? = nil, @id : String? = nil)
          end
        end

        struct FunctionResultContent
          include JSON::Serializable
          getter name : String?
          @[JSON::Field(key: "is_error")]
          getter is_error : Bool?
          getter result : JSON::Any?
          @[JSON::Field(key: "call_id")]
          getter call_id : String?

          def initialize(@name : String? = nil, @is_error : Bool? = nil, @result : JSON::Any? = nil, @call_id : String? = nil)
          end
        end

        struct CodeExecutionCallArguments
          include JSON::Serializable
          getter language : String?
          getter code : String?

          def initialize(@language : String? = nil, @code : String? = nil)
          end
        end

        struct CodeExecutionCallContent
          include JSON::Serializable
          getter arguments : CodeExecutionCallArguments?
          getter id : String?

          def initialize(@arguments : CodeExecutionCallArguments? = nil, @id : String? = nil)
          end
        end

        struct CodeExecutionResultContent
          include JSON::Serializable
          getter result : String?
          @[JSON::Field(key: "is_error")]
          getter is_error : Bool?
          getter signature : String?
          @[JSON::Field(key: "call_id")]
          getter call_id : String?

          def initialize(@result : String? = nil, @is_error : Bool? = nil, @signature : String? = nil, @call_id : String? = nil)
          end
        end

        struct UrlContextCallArguments
          include JSON::Serializable
          getter urls : Array(String)?

          def initialize(@urls : Array(String)? = nil)
          end
        end

        struct UrlContextCallContent
          include JSON::Serializable
          getter arguments : UrlContextCallArguments?
          getter id : String?

          def initialize(@arguments : UrlContextCallArguments? = nil, @id : String? = nil)
          end
        end

        struct UrlContextResult
          include JSON::Serializable
          getter url : String?
          getter status : String?

          def initialize(@url : String? = nil, @status : String? = nil)
          end
        end

        struct UrlContextResultContent
          include JSON::Serializable
          getter signature : String?
          getter result : Array(UrlContextResult)?
          @[JSON::Field(key: "is_error")]
          getter is_error : Bool?
          @[JSON::Field(key: "call_id")]
          getter call_id : String?

          def initialize(@signature : String? = nil, @result : Array(UrlContextResult)? = nil, @is_error : Bool? = nil, @call_id : String? = nil)
          end
        end

        struct GoogleSearchCallArguments
          include JSON::Serializable
          getter queries : Array(String)?

          def initialize(@queries : Array(String)? = nil)
          end
        end

        struct GoogleSearchCallContent
          include JSON::Serializable
          getter arguments : GoogleSearchCallArguments?
          getter id : String?

          def initialize(@arguments : GoogleSearchCallArguments? = nil, @id : String? = nil)
          end
        end

        struct GoogleSearchResult
          include JSON::Serializable
          getter url : String?
          getter title : String?
          @[JSON::Field(key: "rendered_content")]
          getter rendered_content : String?

          def initialize(@url : String? = nil, @title : String? = nil, @rendered_content : String? = nil)
          end
        end

        struct GoogleSearchResultContent
          include JSON::Serializable
          getter signature : String?
          getter result : Array(GoogleSearchResult)?
          @[JSON::Field(key: "is_error")]
          getter is_error : Bool?
          @[JSON::Field(key: "call_id")]
          getter call_id : String?

          def initialize(@signature : String? = nil, @result : Array(GoogleSearchResult)? = nil, @is_error : Bool? = nil, @call_id : String? = nil)
          end
        end

        struct McpServerToolCallContent
          include JSON::Serializable
          getter name : String?
          @[JSON::Field(key: "server_name")]
          getter server_name : String?
          getter arguments : JSON::Any?
          getter id : String?

          def initialize(@name : String? = nil, @server_name : String? = nil, @arguments : JSON::Any? = nil, @id : String? = nil)
          end
        end

        struct McpServerToolResultContent
          include JSON::Serializable
          getter name : String?
          @[JSON::Field(key: "server_name")]
          getter server_name : String?
          getter result : JSON::Any?
          @[JSON::Field(key: "call_id")]
          getter call_id : String?

          def initialize(@name : String? = nil, @server_name : String? = nil, @result : JSON::Any? = nil, @call_id : String? = nil)
          end
        end

        struct FileSearchResult
          include JSON::Serializable
          getter title : String
          getter text : String
          @[JSON::Field(key: "file_search_store")]
          getter file_search_store : String

          def initialize(@title : String, @text : String, @file_search_store : String)
          end
        end

        struct FileSearchResultContent
          include JSON::Serializable
          getter result : Array(FileSearchResult)?

          def initialize(@result : Array(FileSearchResult)? = nil)
          end
        end

        struct Content
          enum Kind
            Text
            Image
            Audio
            Document
            Video
            Thought
            FunctionCall
            FunctionResult
            CodeExecutionCall
            CodeExecutionResult
            UrlContextCall
            UrlContextResult
            GoogleSearchCall
            GoogleSearchResult
            McpServerToolCall
            McpServerToolResult
            FileSearchResult
          end

          getter kind : Kind
          getter text : TextContent?
          getter image : ImageContent?
          getter audio : AudioContent?
          getter document : DocumentContent?
          getter video : VideoContent?
          getter thought : ThoughtContent?
          getter function_call : FunctionCallContent?
          getter function_result : FunctionResultContent?
          getter code_execution_call : CodeExecutionCallContent?
          getter code_execution_result : CodeExecutionResultContent?
          getter url_context_call : UrlContextCallContent?
          getter url_context_result : UrlContextResultContent?
          getter google_search_call : GoogleSearchCallContent?
          getter google_search_result : GoogleSearchResultContent?
          getter mcp_server_tool_call : McpServerToolCallContent?
          getter mcp_server_tool_result : McpServerToolResultContent?
          getter file_search_result : FileSearchResultContent?

          def initialize(
            @kind : Kind,
            @text : TextContent? = nil,
            @image : ImageContent? = nil,
            @audio : AudioContent? = nil,
            @document : DocumentContent? = nil,
            @video : VideoContent? = nil,
            @thought : ThoughtContent? = nil,
            @function_call : FunctionCallContent? = nil,
            @function_result : FunctionResultContent? = nil,
            @code_execution_call : CodeExecutionCallContent? = nil,
            @code_execution_result : CodeExecutionResultContent? = nil,
            @url_context_call : UrlContextCallContent? = nil,
            @url_context_result : UrlContextResultContent? = nil,
            @google_search_call : GoogleSearchCallContent? = nil,
            @google_search_result : GoogleSearchResultContent? = nil,
            @mcp_server_tool_call : McpServerToolCallContent? = nil,
            @mcp_server_tool_result : McpServerToolResultContent? = nil,
            @file_search_result : FileSearchResultContent? = nil,
          )
          end

          def self.text(text : TextContent) : self
            new(Kind::Text, text: text)
          end

          def self.image(image : ImageContent) : self
            new(Kind::Image, image: image)
          end

          def self.audio(audio : AudioContent) : self
            new(Kind::Audio, audio: audio)
          end

          def self.document(document : DocumentContent) : self
            new(Kind::Document, document: document)
          end

          def self.video(video : VideoContent) : self
            new(Kind::Video, video: video)
          end

          def self.thought(thought : ThoughtContent) : self
            new(Kind::Thought, thought: thought)
          end

          def self.function_call(function_call : FunctionCallContent) : self
            new(Kind::FunctionCall, function_call: function_call)
          end

          def self.function_result(function_result : FunctionResultContent) : self
            new(Kind::FunctionResult, function_result: function_result)
          end

          def self.code_execution_call(content : CodeExecutionCallContent) : self
            new(Kind::CodeExecutionCall, code_execution_call: content)
          end

          def self.code_execution_result(content : CodeExecutionResultContent) : self
            new(Kind::CodeExecutionResult, code_execution_result: content)
          end

          def self.url_context_call(content : UrlContextCallContent) : self
            new(Kind::UrlContextCall, url_context_call: content)
          end

          def self.url_context_result(content : UrlContextResultContent) : self
            new(Kind::UrlContextResult, url_context_result: content)
          end

          def self.google_search_call(content : GoogleSearchCallContent) : self
            new(Kind::GoogleSearchCall, google_search_call: content)
          end

          def self.google_search_result(content : GoogleSearchResultContent) : self
            new(Kind::GoogleSearchResult, google_search_result: content)
          end

          def self.mcp_server_tool_call(content : McpServerToolCallContent) : self
            new(Kind::McpServerToolCall, mcp_server_tool_call: content)
          end

          def self.mcp_server_tool_result(content : McpServerToolResultContent) : self
            new(Kind::McpServerToolResult, mcp_server_tool_result: content)
          end

          def self.file_search_result(content : FileSearchResultContent) : self
            new(Kind::FileSearchResult, file_search_result: content)
          end

          def to_json(json : JSON::Builder) : Nil
            json.object do
              case @kind
              in .text?
                json.field "type", "text"
                json.field "text", @text.as(TextContent).text
                if annotations = @text.as(TextContent).annotations
                  json.field "annotations", annotations
                end
              in .image?
                json.field "type", "image"
                image = @image.as(ImageContent)
                image.to_json(json)
              in .audio?
                json.field "type", "audio"
                @audio.as(AudioContent).to_json(json)
              in .document?
                json.field "type", "document"
                @document.as(DocumentContent).to_json(json)
              in .video?
                json.field "type", "video"
                @video.as(VideoContent).to_json(json)
              in .thought?
                json.field "type", "thought"
                @thought.as(ThoughtContent).to_json(json)
              in .function_call?
                json.field "type", "function_call"
                @function_call.as(FunctionCallContent).to_json(json)
              in .function_result?
                json.field "type", "function_result"
                @function_result.as(FunctionResultContent).to_json(json)
              in .code_execution_call?
                json.field "type", "code_execution_call"
                @code_execution_call.as(CodeExecutionCallContent).to_json(json)
              in .code_execution_result?
                json.field "type", "code_execution_result"
                @code_execution_result.as(CodeExecutionResultContent).to_json(json)
              in .url_context_call?
                json.field "type", "url_context_call"
                @url_context_call.as(UrlContextCallContent).to_json(json)
              in .url_context_result?
                json.field "type", "url_context_result"
                @url_context_result.as(UrlContextResultContent).to_json(json)
              in .google_search_call?
                json.field "type", "google_search_call"
                @google_search_call.as(GoogleSearchCallContent).to_json(json)
              in .google_search_result?
                json.field "type", "google_search_result"
                @google_search_result.as(GoogleSearchResultContent).to_json(json)
              in .mcp_server_tool_call?
                json.field "type", "mcp_server_tool_call"
                @mcp_server_tool_call.as(McpServerToolCallContent).to_json(json)
              in .mcp_server_tool_result?
                json.field "type", "mcp_server_tool_result"
                @mcp_server_tool_result.as(McpServerToolResultContent).to_json(json)
              in .file_search_result?
                json.field "type", "file_search_result"
                @file_search_result.as(FileSearchResultContent).to_json(json)
              end
            end
          end

          # ameba:disable Metrics/CyclomaticComplexity
          def self.new(pull : JSON::PullParser)
            value = JSON::Any.new(pull)
            hash = value.as_h
            type = hash["type"].as_s
            case type
            when "text"                   then text(TextContent.from_json(value.to_json))
            when "image"                  then image(ImageContent.from_json(value.to_json))
            when "audio"                  then audio(AudioContent.from_json(value.to_json))
            when "document"               then document(DocumentContent.from_json(value.to_json))
            when "video"                  then video(VideoContent.from_json(value.to_json))
            when "thought"                then thought(ThoughtContent.from_json(value.to_json))
            when "function_call"          then function_call(FunctionCallContent.from_json(value.to_json))
            when "function_result"        then function_result(FunctionResultContent.from_json(value.to_json))
            when "code_execution_call"    then code_execution_call(CodeExecutionCallContent.from_json(value.to_json))
            when "code_execution_result"  then code_execution_result(CodeExecutionResultContent.from_json(value.to_json))
            when "url_context_call"       then url_context_call(UrlContextCallContent.from_json(value.to_json))
            when "url_context_result"     then url_context_result(UrlContextResultContent.from_json(value.to_json))
            when "google_search_call"     then google_search_call(GoogleSearchCallContent.from_json(value.to_json))
            when "google_search_result"   then google_search_result(GoogleSearchResultContent.from_json(value.to_json))
            when "mcp_server_tool_call"   then mcp_server_tool_call(McpServerToolCallContent.from_json(value.to_json))
            when "mcp_server_tool_result" then mcp_server_tool_result(McpServerToolResultContent.from_json(value.to_json))
            when "file_search_result"     then file_search_result(FileSearchResultContent.from_json(value.to_json))
            else
              raise Crig::Completion::CompletionError.new("Unknown Gemini interactions content type: #{type}")
            end
          end

          # ameba:enable Metrics/CyclomaticComplexity

          def self.from_user_content(content : Crig::Completion::UserContent) : self
            case content.kind
            in .text?
              text(TextContent.new(content.text.as(Crig::Completion::Text).text))
            in .tool_result?
              tool_result = content.tool_result.as(Crig::Completion::ToolResult)
              call_id = tool_result.call_id || raise Crig::Completion::MessageError.new("Tool results require call_id for Gemini Interactions API")
              item = tool_result.content.first
              raise Crig::Completion::MessageError.new("Tool result content must be text") unless item.kind.text?
              text_value = item.text.as(Crig::Completion::Text).text
              result = begin
                JSON.parse(text_value)
              rescue
                JSON.parse(text_value.to_json)
              end
              function_result(
                FunctionResultContent.new(
                  name: tool_result.id,
                  result: result,
                  call_id: call_id
                )
              )
            in .image?
              image_content(content.image.as(Crig::Completion::Image))
            in .audio?
              audio_content(content.audio.as(Crig::Completion::Audio))
            in .video?
              video_content(content.video.as(Crig::Completion::Video))
            in .document?
              document_content(content.document.as(Crig::Completion::Document))
            end
          end

          def self.from_assistant_content(content : Crig::Completion::AssistantContent) : self
            case content.kind
            in .text?
              text(TextContent.new(content.text.as(Crig::Completion::Text).text))
            in .tool_call?
              tool_call = content.tool_call.as(Crig::Completion::ToolCall)
              function_call(
                FunctionCallContent.new(
                  name: tool_call.function.name,
                  arguments: tool_call.function.arguments,
                  id: tool_call.call_id || tool_call.id,
                )
              )
            in .reasoning?
              reasoning = content.reasoning.as(Crig::Completion::Reasoning)
              signature = nil.as(String?)
              summary = reasoning.content.map do |item|
                text = case item.kind
                       in .text?
                         signature ||= item.signature
                         item.text || ""
                       in .summary?
                         item.summary || ""
                       in .encrypted?, .redacted?
                         item.data || ""
                       end
                ThoughtSummaryContent.text(TextContent.new(text))
              end
              thought(ThoughtContent.new(signature: signature, summary: summary))
            in .image?
              image_content(content.image.as(Crig::Completion::Image))
            end
          end

          private def self.image_content(image : Crig::Completion::Image) : self
            media_type = image.media_type || raise Crig::Completion::MessageError.new("Media type for image is required for Gemini")
            mime_type = Crig::Completion::MimeType.image_to_mime_type(media_type)
            case image.data.kind
            in .url?
              image(ImageContent.new(uri: image.data.string_value, mime_type: mime_type))
            in .base64?, .string?
              image(ImageContent.new(data: image.data.string_value, mime_type: mime_type))
            in .raw?, .file_id?, .unknown?
              raise Crig::Completion::MessageError.new("Raw content is not supported, encode as base64 first")
            end
          end

          private def self.audio_content(audio : Crig::Completion::Audio) : self
            media_type = audio.media_type || raise Crig::Completion::MessageError.new("Media type for audio is required for Gemini")
            mime_type = Crig::Completion::MimeType.audio_to_mime_type(media_type)
            case audio.data.kind
            in .url?
              audio(AudioContent.new(uri: audio.data.string_value, mime_type: mime_type))
            in .base64?, .string?
              audio(AudioContent.new(data: audio.data.string_value, mime_type: mime_type))
            in .raw?, .file_id?, .unknown?
              raise Crig::Completion::MessageError.new("Raw content is not supported, encode as base64 first")
            end
          end

          private def self.document_content(document : Crig::Completion::Document) : self
            media_type = document.media_type || raise Crig::Completion::MessageError.new("Media type for document is required for Gemini")
            mime_type = Crig::Completion::MimeType.document_to_mime_type(media_type)
            case document.data.kind
            in .url?
              document(DocumentContent.new(uri: document.data.string_value, mime_type: mime_type))
            in .base64?, .string?
              document(DocumentContent.new(data: document.data.string_value, mime_type: mime_type))
            in .raw?, .file_id?, .unknown?
              raise Crig::Completion::MessageError.new("Raw content is not supported, encode as base64 first")
            end
          end

          private def self.video_content(video : Crig::Completion::Video) : self
            media_type = video.media_type || raise Crig::Completion::MessageError.new("Media type for video is required for Gemini")
            mime_type = Crig::Completion::MimeType.video_to_mime_type(media_type)
            case video.data.kind
            in .url?
              video(VideoContent.new(uri: video.data.string_value, mime_type: mime_type))
            in .base64?, .string?
              video(VideoContent.new(data: video.data.string_value, mime_type: mime_type))
            in .raw?, .file_id?, .unknown?
              raise Crig::Completion::MessageError.new("Raw content is not supported, encode as base64 first")
            end
          end
        end

        struct Turn
          include JSON::Serializable

          getter role : Role
          getter content : TurnContent

          def initialize(@role : Role, @content : TurnContent)
          end

          def self.from_completion_message(message : Crig::Completion::Message) : self
            case message.role
            in .user?
              contents = message.content.to_a.map { |content| Content.from_user_content(content.as(Crig::Completion::UserContent)) }
              new(Role::User, TurnContent.contents(contents))
            in .assistant?
              contents = message.content.to_a.map { |content| Content.from_assistant_content(content.as(Crig::Completion::AssistantContent)) }
              new(Role::Model, TurnContent.contents(contents))
            end
          end
        end

        struct InteractionInput
          enum Kind
            Text
            Content
            Turns
            Contents
          end

          getter kind : Kind
          getter text : String?
          getter content : Content?
          getter turns : Array(Turn)?
          getter contents : Array(Content)?

          def initialize(@kind : Kind, @text : String? = nil, @content : Content? = nil, @turns : Array(Turn)? = nil, @contents : Array(Content)? = nil)
          end

          def self.turns(turns : Array(Turn)) : self
            new(Kind::Turns, turns: turns)
          end

          def to_json(json : JSON::Builder) : Nil
            case @kind
            in .text?
              json.string(@text || "")
            in .content?
              @content.as(Content).to_json(json)
            in .turns?
              json.array do
                @turns.try(&.each(&.to_json(json)))
              end
            in .contents?
              json.array do
                @contents.try(&.each(&.to_json(json)))
              end
            end
          end
        end

        struct FunctionTool
          include JSON::Serializable
          getter name : String?
          getter description : String?
          getter parameters : JSON::Any?

          def initialize(@name : String? = nil, @description : String? = nil, @parameters : JSON::Any? = nil)
          end
        end

        struct ComputerUseTool
          include JSON::Serializable
          getter environment : String?
          @[JSON::Field(key: "excluded_predefined_functions")]
          getter excluded_predefined_functions : Array(String)?

          def initialize(@environment : String? = nil, @excluded_predefined_functions : Array(String)? = nil)
          end
        end

        struct McpServerTool
          include JSON::Serializable
          getter name : String?
          getter url : String?
          getter headers : JSON::Any?
          @[JSON::Field(key: "allowed_tools")]
          getter allowed_tools : AllowedTools?

          def initialize(@name : String? = nil, @url : String? = nil, @headers : JSON::Any? = nil, @allowed_tools : AllowedTools? = nil)
          end
        end

        struct FileSearchTool
          include JSON::Serializable
          @[JSON::Field(key: "file_search_store_names")]
          getter file_search_store_names : Array(String)?
          @[JSON::Field(key: "top_k")]
          getter top_k : Int64?
          @[JSON::Field(key: "metadata_filter")]
          getter metadata_filter : String?

          def initialize(@file_search_store_names : Array(String)? = nil, @top_k : Int64? = nil, @metadata_filter : String? = nil)
          end
        end

        struct Tool
          enum Kind
            Function
            GoogleSearch
            CodeExecution
            UrlContext
            ComputerUse
            McpServer
            FileSearch
          end

          getter kind : Kind
          getter function : FunctionTool?
          getter computer_use : ComputerUseTool?
          getter mcp_server : McpServerTool?
          getter file_search : FileSearchTool?

          def initialize(@kind : Kind, @function : FunctionTool? = nil, @computer_use : ComputerUseTool? = nil, @mcp_server : McpServerTool? = nil, @file_search : FileSearchTool? = nil)
          end

          def self.function(function : FunctionTool) : self
            new(Kind::Function, function: function)
          end

          def self.google_search : self
            new(Kind::GoogleSearch)
          end

          def self.code_execution : self
            new(Kind::CodeExecution)
          end

          def self.url_context : self
            new(Kind::UrlContext)
          end

          def self.computer_use(computer_use : ComputerUseTool) : self
            new(Kind::ComputerUse, computer_use: computer_use)
          end

          def self.mcp_server(mcp_server : McpServerTool) : self
            new(Kind::McpServer, mcp_server: mcp_server)
          end

          def self.file_search(file_search : FileSearchTool) : self
            new(Kind::FileSearch, file_search: file_search)
          end

          def to_json(json : JSON::Builder) : Nil
            json.object do
              case @kind
              in .function?
                json.field "type", "function"
                write_function_fields(json, @function.as(FunctionTool))
              in .google_search?
                json.field "type", "google_search"
              in .code_execution?
                json.field "type", "code_execution"
              in .url_context?
                json.field "type", "url_context"
              in .computer_use?
                json.field "type", "computer_use"
                write_computer_use_fields(json, @computer_use.as(ComputerUseTool))
              in .mcp_server?
                json.field "type", "mcp_server"
                write_mcp_server_fields(json, @mcp_server.as(McpServerTool))
              in .file_search?
                json.field "type", "file_search"
                write_file_search_fields(json, @file_search.as(FileSearchTool))
              end
            end
          end

          def self.new(pull : JSON::PullParser)
            value = JSON::Any.new(pull)
            type = value["type"].as_s
            case type
            when "function"
              function(FunctionTool.from_json(value.to_json))
            when "google_search"
              google_search
            when "code_execution"
              code_execution
            when "url_context"
              url_context
            when "computer_use"
              computer_use(ComputerUseTool.from_json(value.to_json))
            when "mcp_server"
              mcp_server(McpServerTool.from_json(value.to_json))
            when "file_search"
              file_search(FileSearchTool.from_json(value.to_json))
            else
              raise Crig::Completion::CompletionError.new("Unknown Gemini interactions tool type: #{type}")
            end
          end

          def self.from_tool_definition(tool : Crig::Completion::ToolDefinition) : self
            function(FunctionTool.new(name: tool.name, description: tool.description, parameters: tool.parameters))
          end

          private def write_function_fields(json : JSON::Builder, function : FunctionTool) : Nil
            json.field "name", function.name if function.name
            json.field "description", function.description if function.description
            if parameters = function.parameters
              json.field "parameters" do
                parameters.to_json(json)
              end
            end
          end

          private def write_computer_use_fields(json : JSON::Builder, computer_use : ComputerUseTool) : Nil
            json.field "environment", computer_use.environment if computer_use.environment
            json.field "excluded_predefined_functions", computer_use.excluded_predefined_functions if computer_use.excluded_predefined_functions
          end

          private def write_mcp_server_fields(json : JSON::Builder, mcp_server : McpServerTool) : Nil
            json.field "name", mcp_server.name if mcp_server.name
            json.field "url", mcp_server.url if mcp_server.url
            if headers = mcp_server.headers
              json.field "headers" do
                headers.to_json(json)
              end
            end
            json.field "allowed_tools", mcp_server.allowed_tools if mcp_server.allowed_tools
          end

          private def write_file_search_fields(json : JSON::Builder, file_search : FileSearchTool) : Nil
            json.field "file_search_store_names", file_search.file_search_store_names if file_search.file_search_store_names
            json.field "top_k", file_search.top_k if file_search.top_k
            json.field "metadata_filter", file_search.metadata_filter if file_search.metadata_filter
          end
        end

        enum MediaResolution
          Low
          Medium
          High
          UltraHigh

          def to_json(json : JSON::Builder) : Nil
            json.string(to_s.underscore)
          end

          def self.new(pull : JSON::PullParser)
            parse(pull.read_string.camelcase)
          end
        end

        struct AgentConfig
          enum Kind
            Dynamic
            DeepResearch
          end

          getter kind : Kind
          getter thinking_summaries : ThinkingSummaries?

          def initialize(@kind : Kind, @thinking_summaries : ThinkingSummaries? = nil)
          end

          def self.dynamic : self
            new(Kind::Dynamic)
          end

          def self.deep_research(thinking_summaries : ThinkingSummaries? = nil) : self
            new(Kind::DeepResearch, thinking_summaries)
          end

          def to_json(json : JSON::Builder) : Nil
            json.object do
              case @kind
              in .dynamic?
                json.field "type", "dynamic"
              in .deep_research?
                json.field "type", "deep-research"
                if thinking_summaries = @thinking_summaries
                  json.field "thinking_summaries", thinking_summaries
                end
              end
            end
          end

          def self.new(pull : JSON::PullParser)
            value = JSON::Any.new(pull)
            kind = value["type"].as_s
            case kind
            when "dynamic"
              dynamic
            when "deep-research"
              deep_research(
                value["thinking_summaries"]?.try { |entry| ThinkingSummaries.from_json(entry.to_json) }
              )
            else
              raise Crig::Completion::CompletionError.new("Unknown Gemini interactions agent config")
            end
          end
        end

        struct InteractionStatus
          enum Kind
            InProgress
            RequiresAction
            Completed
            Failed
            Cancelled
          end

          getter kind : Kind

          def initialize(@kind : Kind)
          end

          def self.completed : self
            new(Kind::Completed)
          end

          def self.in_progress : self
            new(Kind::InProgress)
          end

          # ameba:disable Naming/PredicateName
          def is_terminal : Bool
            @kind.completed? || @kind.failed? || @kind.cancelled?
          end

          # ameba:enable Naming/PredicateName

          def to_json(json : JSON::Builder) : Nil
            json.string(@kind.to_s.underscore)
          end

          def self.new(pull : JSON::PullParser)
            case pull.read_string
            when "in_progress"     then in_progress
            when "requires_action" then new(Kind::RequiresAction)
            when "completed"       then completed
            when "failed"          then new(Kind::Failed)
            when "cancelled"       then new(Kind::Cancelled)
            else
              raise Crig::Completion::CompletionError.new("Unknown Gemini interactions status")
            end
          end
        end

        struct InteractionUsage
          include JSON::Serializable
          @[JSON::Field(key: "total_input_tokens")]
          getter total_input_tokens : Int64?
          @[JSON::Field(key: "total_output_tokens")]
          getter total_output_tokens : Int64?
          @[JSON::Field(key: "total_tokens")]
          getter total_tokens : Int64?

          def initialize(@total_input_tokens : Int64? = nil, @total_output_tokens : Int64? = nil, @total_tokens : Int64? = nil)
          end

          def token_usage : Crig::Completion::Usage
            input = @total_input_tokens || 0_i64
            output = @total_output_tokens || 0_i64
            Crig::Completion::Usage.new(
              input_tokens: input,
              output_tokens: output,
              total_tokens: @total_tokens || (input + output),
            )
          end
        end

        struct Interaction
          include JSON::Serializable

          getter id : String = ""
          getter model : String?
          getter agent : String?
          getter status : InteractionStatus?
          getter object : String?
          getter created : String?
          getter updated : String?
          getter role : String?
          getter outputs : Array(Content) = [] of Content
          getter usage : InteractionUsage?
          @[JSON::Field(key: "system_instruction")]
          getter system_instruction : String?
          getter tools : Array(Tool)?
          getter background : Bool?
          @[JSON::Field(key: "response_modalities")]
          getter response_modalities : Array(ResponseModality)?
          @[JSON::Field(key: "response_format")]
          getter response_format : JSON::Any?
          @[JSON::Field(key: "response_mime_type")]
          getter response_mime_type : String?
          @[JSON::Field(key: "previous_interaction_id")]
          getter previous_interaction_id : String?
          getter input : JSON::Any?

          def initialize(
            @id : String = "",
            @model : String? = nil,
            @agent : String? = nil,
            @status : InteractionStatus? = nil,
            @object : String? = nil,
            @created : String? = nil,
            @updated : String? = nil,
            @role : String? = nil,
            @outputs : Array(Content) = [] of Content,
            @usage : InteractionUsage? = nil,
            @system_instruction : String? = nil,
            @tools : Array(Tool)? = nil,
            @background : Bool? = nil,
            @response_modalities : Array(ResponseModality)? = nil,
            @response_format : JSON::Any? = nil,
            @response_mime_type : String? = nil,
            @previous_interaction_id : String? = nil,
            @input : JSON::Any? = nil,
          )
          end

          def token_usage : Crig::Completion::Usage?
            @usage.try(&.token_usage)
          end

          # ameba:disable Naming/PredicateName
          def is_terminal : Bool
            @status.try(&.is_terminal) || false
          end

          # ameba:disable Naming/PredicateName
          def is_completed : Bool
            @status.try(&.kind.completed?) || false
          end

          # ameba:enable Naming/PredicateName

          def google_search_exchanges : Array(GoogleSearchExchange)
            group_exchanges(GoogleSearchExchange)
          end

          def google_search_call_contents : Array(GoogleSearchCallContent)
            google_search_exchanges.flat_map(&.calls)
          end

          def google_search_result_contents : Array(GoogleSearchResultContent)
            google_search_exchanges.flat_map(&.results)
          end

          def google_search_queries : Array(String)
            google_search_exchanges.flat_map(&.queries)
          end

          def google_search_results : Array(GoogleSearchResult)
            google_search_exchanges.flat_map(&.result_items)
          end

          def url_context_exchanges : Array(UrlContextExchange)
            group_exchanges(UrlContextExchange)
          end

          def url_context_call_contents : Array(UrlContextCallContent)
            url_context_exchanges.flat_map(&.calls)
          end

          def url_context_result_contents : Array(UrlContextResultContent)
            url_context_exchanges.flat_map(&.results)
          end

          def url_context_urls : Array(String)
            url_context_exchanges.flat_map(&.urls)
          end

          def url_context_results : Array(UrlContextResult)
            url_context_exchanges.flat_map(&.result_items)
          end

          def code_execution_exchanges : Array(CodeExecutionExchange)
            group_exchanges(CodeExecutionExchange)
          end

          def code_execution_call_contents : Array(CodeExecutionCallContent)
            code_execution_exchanges.flat_map(&.calls)
          end

          def code_execution_result_contents : Array(CodeExecutionResultContent)
            code_execution_exchanges.flat_map(&.results)
          end

          def code_execution_snippets : Array(String)
            code_execution_exchanges.flat_map(&.code_snippets)
          end

          def code_execution_outputs : Array(String)
            code_execution_exchanges.flat_map(&.outputs)
          end

          def text_with_inline_citations : String?
            text = @outputs.compact_map { |content| content.kind.text? ? content.text.as(TextContent).with_inline_citations : nil }.join('\n')
            text.empty? ? nil : text
          end

          private def group_exchanges(type : GoogleSearchExchange.class) : Array(GoogleSearchExchange)
            exchanges = [] of GoogleSearchExchange
            last_index = nil.as(Int32?)
            @outputs.each do |content|
              case content.kind
              in .google_search_call?
                call = content.google_search_call.as(GoogleSearchCallContent)
                index = append_call_exchange(GoogleSearchExchange, exchanges, call.id, call) { |exchange, item| exchange.calls << item }
                last_index = index
              in .google_search_result?
                result = content.google_search_result.as(GoogleSearchResultContent)
                append_result_exchange(GoogleSearchExchange, exchanges, result.call_id, result, last_index) { |exchange, item| exchange.results << item }
                last_index ||= (exchanges.size - 1).to_i32 unless exchanges.empty?
              in .text?, .image?, .audio?, .document?, .video?, .thought?, .function_call?, .function_result?, .code_execution_call?,
                 .code_execution_result?, .url_context_call?, .url_context_result?, .mcp_server_tool_call?, .mcp_server_tool_result?, .file_search_result?
              end
            end
            exchanges
          end

          private def group_exchanges(type : UrlContextExchange.class) : Array(UrlContextExchange)
            exchanges = [] of UrlContextExchange
            last_index = nil.as(Int32?)
            @outputs.each do |content|
              case content.kind
              in .url_context_call?
                call = content.url_context_call.as(UrlContextCallContent)
                index = append_call_exchange(UrlContextExchange, exchanges, call.id, call) { |exchange, item| exchange.calls << item }
                last_index = index
              in .url_context_result?
                result = content.url_context_result.as(UrlContextResultContent)
                append_result_exchange(UrlContextExchange, exchanges, result.call_id, result, last_index) { |exchange, item| exchange.results << item }
                last_index ||= (exchanges.size - 1).to_i32 unless exchanges.empty?
              in .text?, .image?, .audio?, .document?, .video?, .thought?, .function_call?, .function_result?, .code_execution_call?,
                 .code_execution_result?, .google_search_call?, .google_search_result?, .mcp_server_tool_call?, .mcp_server_tool_result?, .file_search_result?
              end
            end
            exchanges
          end

          private def group_exchanges(type : CodeExecutionExchange.class) : Array(CodeExecutionExchange)
            exchanges = [] of CodeExecutionExchange
            last_index = nil.as(Int32?)
            @outputs.each do |content|
              case content.kind
              in .code_execution_call?
                call = content.code_execution_call.as(CodeExecutionCallContent)
                index = append_call_exchange(CodeExecutionExchange, exchanges, call.id, call) { |exchange, item| exchange.calls << item }
                last_index = index
              in .code_execution_result?
                result = content.code_execution_result.as(CodeExecutionResultContent)
                append_result_exchange(CodeExecutionExchange, exchanges, result.call_id, result, last_index) { |exchange, item| exchange.results << item }
                last_index ||= (exchanges.size - 1).to_i32 unless exchanges.empty?
              in .text?, .image?, .audio?, .document?, .video?, .thought?, .function_call?, .function_result?, .url_context_call?,
                 .url_context_result?, .google_search_call?, .google_search_result?, .mcp_server_tool_call?, .mcp_server_tool_result?, .file_search_result?
              end
            end
            exchanges
          end

          private def append_call_exchange(type, exchanges, call_id, call, &)
            if call_id
              if index = exchanges.index { |exchange| exchange.call_id == call_id }
                yield exchanges[index], call
                index.to_i32
              else
                exchange = type.new(call_id: call_id)
                yield exchange, call
                exchanges << exchange
                (exchanges.size - 1).to_i32
              end
            else
              exchange = type.new(call_id: nil)
              yield exchange, call
              exchanges << exchange
              (exchanges.size - 1).to_i32
            end
          end

          private def append_result_exchange(type, exchanges, call_id, result, last_index, &)
            if call_id
              if index = exchanges.index { |exchange| exchange.call_id == call_id }
                yield exchanges[index], result
              else
                exchange = type.new(call_id: call_id)
                yield exchange, result
                exchanges << exchange
              end
            elsif last_index
              yield exchanges[last_index], result
            else
              exchange = type.new(call_id: nil)
              yield exchange, result
              exchanges << exchange
            end
          end
        end

        struct GoogleSearchExchange
          getter call_id : String?
          getter calls : Array(GoogleSearchCallContent)
          getter results : Array(GoogleSearchResultContent)

          def initialize(@call_id : String? = nil, @calls : Array(GoogleSearchCallContent) = [] of GoogleSearchCallContent, @results : Array(GoogleSearchResultContent) = [] of GoogleSearchResultContent)
          end

          def queries : Array(String)
            @calls.flat_map { |call| call.arguments.try(&.queries) || [] of String }
          end

          def result_items : Array(GoogleSearchResult)
            @results.flat_map { |result| result.result || [] of GoogleSearchResult }
          end
        end

        struct UrlContextExchange
          getter call_id : String?
          getter calls : Array(UrlContextCallContent)
          getter results : Array(UrlContextResultContent)

          def initialize(@call_id : String? = nil, @calls : Array(UrlContextCallContent) = [] of UrlContextCallContent, @results : Array(UrlContextResultContent) = [] of UrlContextResultContent)
          end

          def urls : Array(String)
            @calls.flat_map { |call| call.arguments.try(&.urls) || [] of String }
          end

          def result_items : Array(UrlContextResult)
            @results.flat_map { |result| result.result || [] of UrlContextResult }
          end
        end

        struct CodeExecutionExchange
          getter call_id : String?
          getter calls : Array(CodeExecutionCallContent)
          getter results : Array(CodeExecutionResultContent)

          def initialize(@call_id : String? = nil, @calls : Array(CodeExecutionCallContent) = [] of CodeExecutionCallContent, @results : Array(CodeExecutionResultContent) = [] of CodeExecutionResultContent)
          end

          def code_snippets : Array(String)
            @calls.compact_map { |call| call.arguments.try(&.code) }
          end

          def outputs : Array(String)
            @results.compact_map(&.result)
          end
        end

        struct CreateInteractionRequest
          getter model : String?
          getter agent : String?
          getter input : InteractionInput
          getter system_instruction : String?
          getter tools : Array(Tool)?
          getter response_format : JSON::Any?
          getter response_mime_type : String?
          getter stream : Bool?
          getter store : Bool?
          getter background : Bool?
          getter generation_config : GenerationConfig?
          getter agent_config : AgentConfig?
          getter response_modalities : Array(ResponseModality)?
          getter previous_interaction_id : String?
          getter additional_params : JSON::Any?

          def initialize(
            @input : InteractionInput,
            @model : String? = nil,
            @agent : String? = nil,
            @system_instruction : String? = nil,
            @tools : Array(Tool)? = nil,
            @response_format : JSON::Any? = nil,
            @response_mime_type : String? = nil,
            @stream : Bool? = nil,
            @store : Bool? = nil,
            @background : Bool? = nil,
            @generation_config : GenerationConfig? = nil,
            @agent_config : AgentConfig? = nil,
            @response_modalities : Array(ResponseModality)? = nil,
            @previous_interaction_id : String? = nil,
            @additional_params : JSON::Any? = nil,
          )
          end

          # ameba:disable Metrics/CyclomaticComplexity
          def to_json(json : JSON::Builder) : Nil
            json.object do
              json.field "model", @model if @model
              json.field "agent", @agent if @agent
              json.field "input", @input
              json.field "system_instruction", @system_instruction if @system_instruction
              json.field "tools", @tools if @tools
              json.field "response_format" do
                @response_format.try(&.to_json(json))
              end if @response_format
              json.field "response_mime_type", @response_mime_type if @response_mime_type
              json.field "stream", @stream unless @stream.nil?
              json.field "store", @store unless @store.nil?
              json.field "background", @background unless @background.nil?
              json.field "generation_config", @generation_config if @generation_config
              json.field "agent_config" do
                @agent_config.try(&.to_json(json))
              end if @agent_config
              json.field "response_modalities", @response_modalities if @response_modalities
              json.field "previous_interaction_id", @previous_interaction_id if @previous_interaction_id
              @additional_params.try &.as_h.each do |key, value|
                json.field key do
                  value.to_json(json)
                end
              end
            end
          end
          # ameba:enable Metrics/CyclomaticComplexity
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def self.create_request_body(
          model : String,
          completion_request : Crig::Completion::Request::CompletionRequest,
          stream_override : Bool? = nil,
        ) : CreateInteractionRequest
          history = [] of Crig::Completion::Message
          if docs = completion_request.normalized_documents
            history << docs
          end
          history.concat(completion_request.chat_history)

          turns = history.map { |message| Turn.from_completion_message(message) }
          input = InteractionInput.turns(turns)

          params = completion_request.additional_params ? AdditionalParameters.from_json_value(completion_request.additional_params.as(JSON::Any)) : AdditionalParameters.new
          generation_config = params.generation_config || GenerationConfig.new
          generation_config.temperature = completion_request.temperature if completion_request.temperature
          generation_config.max_output_tokens = completion_request.max_tokens if completion_request.max_tokens
          generation_config.tool_choice = ToolChoice.from_core(completion_request.tool_choice.as(Crig::Completion::ToolChoice)) if completion_request.tool_choice
          generation_config = generation_config.empty? ? nil : generation_config

          system_instruction = completion_request.preamble || params.system_instruction
          tools = [] of Tool
          completion_request.tools.each { |tool| tools << Tool.from_tool_definition(tool) }
          params.tools.try(&.each { |tool| tools << tool })
          tools = nil if tools.empty?

          response_format = params.response_format
          response_mime_type = params.response_mime_type
          if response_format && response_mime_type.nil?
            raise Crig::Completion::CompletionError.new("response_mime_type is required when response_format is set")
          end

          CreateInteractionRequest.new(
            model: params.agent ? nil : model,
            agent: params.agent,
            input: input,
            system_instruction: system_instruction,
            tools: tools,
            response_format: response_format,
            response_mime_type: response_mime_type,
            stream: stream_override.nil? ? params.stream : stream_override,
            store: params.store,
            background: params.background,
            generation_config: generation_config,
            agent_config: params.agent_config,
            response_modalities: params.response_modalities,
            previous_interaction_id: params.previous_interaction_id,
            additional_params: params.additional_params,
          )
        end

        # ameba:enable Metrics/CyclomaticComplexity

        def self.build_interaction_stream_path(interaction_id : String, last_event_id : String? = nil) : String
          path = "/v1beta/interactions/#{interaction_id}?stream=true"
          path += "&last_event_id=#{URI.encode_path_segment(last_event_id)}" if last_event_id
          path
        end

        class InteractionsCompletionModel
          include Crig::Completion::CompletionModel

          getter client : Crig::Providers::Gemini::InteractionsClient
          getter model : String

          def initialize(@client : Crig::Providers::Gemini::InteractionsClient, @model : String)
          end

          def self.with_model(client : Crig::Providers::Gemini::InteractionsClient, model : String) : self
            new(client, model)
          end

          def generate_content_api : Crig::Providers::Gemini::CompletionModel
            @client.generate_content_api.completion_model(@model)
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.new(prompt)
          end

          def create_completion_request(request : Crig::Completion::Request::CompletionRequest, stream_override : Bool? = nil) : CreateInteractionRequest
            Interactions.create_request_body(@model, request, stream_override)
          end

          def create_interaction(request : Crig::Completion::Request::CompletionRequest) : Interaction
            @client.create_interaction(create_completion_request(request, false))
          end

          def get_interaction(interaction_id : String) : Interaction
            @client.get_interaction(interaction_id)
          end

          def stream_interaction_events(request : Crig::Completion::Request::CompletionRequest) : Streaming::InteractionEventStream
            @client.stream_interaction_events(create_completion_request(request, true))
          end

          def stream_interaction_events_by_id(interaction_id : String, last_event_id : String? = nil) : Streaming::InteractionEventStream
            @client.stream_interaction_events_by_id(interaction_id, last_event_id)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            span = Crig::Span.chat_span("gemini", @model, request.preamble, nil)

            payload = create_completion_request(request, false)
            response = @client.post_json("/v1beta/interactions", payload.to_json)
            raise Crig::Completion::CompletionError.new(response.body) if response.status_code >= 400
            interaction = Interaction.from_json(response.body)
            result = interaction_to_completion_response(interaction)
            if response = result.raw_response
              span.record_response_metadata(response) if response.responds_to?(:get_response_id)
              span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
            end
            span.end_span
          result
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            Streaming.stream(self, request)
          end

          def interaction_to_completion_response(interaction : Interaction) : Crig::Completion::CompletionResponse(Interaction)
            raise Crig::Completion::CompletionError.new(interaction.status ? "Interaction contained no outputs (status: #{interaction.status.as(InteractionStatus).kind})" : "Interaction contained no outputs") if interaction.outputs.empty?
            choices = interaction.outputs.compact_map { |output| assistant_content_from_output(output) }
            choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(choices)
            Crig::Completion::CompletionResponse(Interaction).new(
              choice: choice,
              usage: interaction.token_usage || Crig::Completion::Usage.new,
              raw_response: interaction,
            )
          end

          # ameba:disable Metrics/CyclomaticComplexity
          private def assistant_content_from_output(output : Content) : Crig::Completion::AssistantContent?
            case output.kind
            in .text?
              Crig::Completion::AssistantContent.text(output.text.as(TextContent).text)
            in .function_call?
              function_call = output.function_call.as(FunctionCallContent)
              name = function_call.name
              return if name.nil?
              call_id = function_call.id || name
              Crig::Completion::AssistantContent.tool_call_with_call_id(
                name,
                call_id,
                name,
                function_call.arguments || JSON.parse("{}")
              )
            in .thought?
              thought = output.thought.as(ThoughtContent)
              summary = thought.summary || [] of ThoughtSummaryContent
              reasoning_content = summary.compact_map do |item|
                next unless item.kind.text?
                Crig::Completion::ReasoningContent.text(item.text.as(TextContent).text)
              end
              return if reasoning_content.empty?
              if signature = thought.signature
                first = reasoning_content.first?
                if first && first.kind.text?
                  reasoning_content[0] = Crig::Completion::ReasoningContent.text(first.text || "", signature)
                end
              end
              Crig::Completion::AssistantContent.new(
                Crig::Completion::AssistantContent::Kind::Reasoning,
                reasoning: Crig::Completion::Reasoning.new(reasoning_content),
              )
            in .image?
              image = output.image.as(ImageContent)
              mime_type = image.mime_type || raise Crig::Completion::CompletionError.new("Image output missing mime_type")
              media_type = Crig::Completion::MimeType.image_from_mime_type(mime_type) || raise Crig::Completion::CompletionError.new("Unsupported image output mime type #{mime_type}")
              if data = image.data
                Crig::Completion::AssistantContent.image_base64(data, media_type, Crig::Completion::ImageDetail::Auto)
              elsif uri = image.uri
                Crig::Completion::AssistantContent.new(
                  Crig::Completion::AssistantContent::Kind::Image,
                  image: Crig::Completion::Image.new(Crig::Completion::DocumentSourceKind.url(uri), media_type, Crig::Completion::ImageDetail::Auto),
                )
              else
                raise Crig::Completion::CompletionError.new("Image output missing data or uri")
              end
            in .audio?, .document?, .video?, .function_result?, .code_execution_call?, .code_execution_result?, .url_context_call?, .url_context_result?,
               .google_search_call?, .google_search_result?, .mcp_server_tool_call?, .mcp_server_tool_result?, .file_search_result?
              nil
            end
          end
          # ameba:enable Metrics/CyclomaticComplexity
        end

        module Streaming
        end
      end
    end
  end
end

require "./interactions_api/streaming"
