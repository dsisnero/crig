module Crig
  module Providers
    module Gemini
      module Interactions
        module Streaming
          alias InteractionEventStream = Array(InteractionSseEvent)

          struct StreamingCompletionResponse
            include JSON::Serializable

            getter usage : InteractionUsage?
            getter interaction : Interaction?

            def initialize(@usage : InteractionUsage? = nil, @interaction : Interaction? = nil)
            end

            def token_usage : Crig::Completion::Usage?
              (@usage || @interaction.try(&.usage)).try(&.token_usage)
            end
          end

          struct ErrorEvent
            include JSON::Serializable
            getter code : String
            getter message : String
          end

          struct TextDelta
            include JSON::Serializable
            getter text : String?
            getter annotations : Array(Annotation)?
          end

          struct ImageDelta
            include JSON::Serializable
            getter data : String?
            getter uri : String?
            @[JSON::Field(key: "mime_type")]
            getter mime_type : String?
            getter resolution : MediaResolution?
          end

          struct AudioDelta
            include JSON::Serializable
            getter data : String?
            getter uri : String?
            @[JSON::Field(key: "mime_type")]
            getter mime_type : String?
          end

          struct DocumentDelta
            include JSON::Serializable
            getter data : String?
            getter uri : String?
            @[JSON::Field(key: "mime_type")]
            getter mime_type : String?
          end

          struct VideoDelta
            include JSON::Serializable
            getter data : String?
            getter uri : String?
            @[JSON::Field(key: "mime_type")]
            getter mime_type : String?
            getter resolution : MediaResolution?
          end

          struct FunctionCallDelta
            include JSON::Serializable
            getter name : String?
            getter arguments : JSON::Any?
            getter id : String?
          end

          struct ThoughtSignatureDelta
            include JSON::Serializable
            getter signature : String
          end

          struct FunctionResultDelta
            include JSON::Serializable
            getter name : String?
            getter result : JSON::Any?
            @[JSON::Field(key: "call_id")]
            getter call_id : String?
            @[JSON::Field(key: "is_error")]
            getter is_error : Bool?
          end

          struct CodeExecutionCallDelta
            include JSON::Serializable
            getter arguments : CodeExecutionCallArguments?
            getter id : String?
          end

          struct CodeExecutionResultDelta
            include JSON::Serializable
            getter result : String?
            @[JSON::Field(key: "is_error")]
            getter is_error : Bool?
            getter signature : String?
            @[JSON::Field(key: "call_id")]
            getter call_id : String?
          end

          struct UrlContextCallDelta
            include JSON::Serializable
            getter arguments : UrlContextCallArguments?
            getter id : String?
          end

          struct UrlContextResultDelta
            include JSON::Serializable
            getter result : Array(UrlContextResult)?
            getter signature : String?
            @[JSON::Field(key: "is_error")]
            getter is_error : Bool?
            @[JSON::Field(key: "call_id")]
            getter call_id : String?
          end

          struct GoogleSearchCallDelta
            include JSON::Serializable
            getter arguments : GoogleSearchCallArguments?
            getter id : String?
          end

          struct GoogleSearchResultDelta
            include JSON::Serializable
            getter result : Array(GoogleSearchResult)?
            getter signature : String?
            @[JSON::Field(key: "is_error")]
            getter is_error : Bool?
            @[JSON::Field(key: "call_id")]
            getter call_id : String?
          end

          struct McpServerToolCallDelta
            include JSON::Serializable
            getter name : String?
            @[JSON::Field(key: "server_name")]
            getter server_name : String?
            getter arguments : JSON::Any?
            getter id : String?
          end

          struct McpServerToolResultDelta
            include JSON::Serializable
            getter name : String?
            @[JSON::Field(key: "server_name")]
            getter server_name : String?
            getter result : JSON::Any?
            @[JSON::Field(key: "call_id")]
            getter call_id : String?
          end

          struct FileSearchResultDelta
            include JSON::Serializable
            getter result : Array(FileSearchResult)?
          end

          struct ThoughtSummaryDelta
            include JSON::Serializable
            getter content : ThoughtSummaryContent
          end

          struct ContentDelta
            enum Kind
              Text
              Image
              Audio
              Document
              Video
              FunctionCall
              ThoughtSummary
              ThoughtSignature
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
            getter text : TextDelta?
            getter image : ImageDelta?
            getter audio : AudioDelta?
            getter document : DocumentDelta?
            getter video : VideoDelta?
            getter function_call : FunctionCallDelta?
            getter thought_summary : ThoughtSummaryDelta?
            getter thought_signature : ThoughtSignatureDelta?
            getter function_result : FunctionResultDelta?
            getter code_execution_call : CodeExecutionCallDelta?
            getter code_execution_result : CodeExecutionResultDelta?
            getter url_context_call : UrlContextCallDelta?
            getter url_context_result : UrlContextResultDelta?
            getter google_search_call : GoogleSearchCallDelta?
            getter google_search_result : GoogleSearchResultDelta?
            getter mcp_server_tool_call : McpServerToolCallDelta?
            getter mcp_server_tool_result : McpServerToolResultDelta?
            getter file_search_result : FileSearchResultDelta?

            def initialize(@kind : Kind, @text : TextDelta? = nil, @image : ImageDelta? = nil, @audio : AudioDelta? = nil, @document : DocumentDelta? = nil, @video : VideoDelta? = nil, @function_call : FunctionCallDelta? = nil, @thought_summary : ThoughtSummaryDelta? = nil, @thought_signature : ThoughtSignatureDelta? = nil, @function_result : FunctionResultDelta? = nil, @code_execution_call : CodeExecutionCallDelta? = nil, @code_execution_result : CodeExecutionResultDelta? = nil, @url_context_call : UrlContextCallDelta? = nil, @url_context_result : UrlContextResultDelta? = nil, @google_search_call : GoogleSearchCallDelta? = nil, @google_search_result : GoogleSearchResultDelta? = nil, @mcp_server_tool_call : McpServerToolCallDelta? = nil, @mcp_server_tool_result : McpServerToolResultDelta? = nil, @file_search_result : FileSearchResultDelta? = nil)
            end

            # ameba:disable Metrics/CyclomaticComplexity
            def self.new(pull : JSON::PullParser)
              value = JSON::Any.new(pull)
              type = value["type"].as_s
              case type
              when "text"
                new(Kind::Text, text: TextDelta.from_json(value.to_json))
              when "image"
                new(Kind::Image, image: ImageDelta.from_json(value.to_json))
              when "audio"
                new(Kind::Audio, audio: AudioDelta.from_json(value.to_json))
              when "document"
                new(Kind::Document, document: DocumentDelta.from_json(value.to_json))
              when "video"
                new(Kind::Video, video: VideoDelta.from_json(value.to_json))
              when "function_call"
                new(Kind::FunctionCall, function_call: FunctionCallDelta.from_json(value.to_json))
              when "thought_summary"
                new(Kind::ThoughtSummary, thought_summary: ThoughtSummaryDelta.from_json(value.to_json))
              when "thought_signature"
                new(Kind::ThoughtSignature, thought_signature: ThoughtSignatureDelta.from_json(value.to_json))
              when "function_result"
                new(Kind::FunctionResult, function_result: FunctionResultDelta.from_json(value.to_json))
              when "code_execution_call"
                new(Kind::CodeExecutionCall, code_execution_call: CodeExecutionCallDelta.from_json(value.to_json))
              when "code_execution_result"
                new(Kind::CodeExecutionResult, code_execution_result: CodeExecutionResultDelta.from_json(value.to_json))
              when "url_context_call"
                new(Kind::UrlContextCall, url_context_call: UrlContextCallDelta.from_json(value.to_json))
              when "url_context_result"
                new(Kind::UrlContextResult, url_context_result: UrlContextResultDelta.from_json(value.to_json))
              when "google_search_call"
                new(Kind::GoogleSearchCall, google_search_call: GoogleSearchCallDelta.from_json(value.to_json))
              when "google_search_result"
                new(Kind::GoogleSearchResult, google_search_result: GoogleSearchResultDelta.from_json(value.to_json))
              when "mcp_server_tool_call"
                new(Kind::McpServerToolCall, mcp_server_tool_call: McpServerToolCallDelta.from_json(value.to_json))
              when "mcp_server_tool_result"
                new(Kind::McpServerToolResult, mcp_server_tool_result: McpServerToolResultDelta.from_json(value.to_json))
              when "file_search_result"
                new(Kind::FileSearchResult, file_search_result: FileSearchResultDelta.from_json(value.to_json))
              else
                raise Crig::Completion::CompletionError.new("Unknown Gemini interactions content delta type: #{type}")
              end
            end
            # ameba:enable Metrics/CyclomaticComplexity
          end

          struct InteractionSseEvent
            enum Kind
              InteractionStart
              InteractionComplete
              InteractionStatusUpdate
              ContentStart
              ContentDelta
              ContentStop
              Error
            end

            getter kind : Kind
            getter interaction : Interaction?
            getter interaction_id : String?
            getter status : InteractionStatus?
            getter index : Int32?
            getter content : Content?
            getter delta : ContentDelta?
            getter error : ErrorEvent?
            getter event_id : String?

            def initialize(
              @kind : Kind,
              @interaction : Interaction? = nil,
              @interaction_id : String? = nil,
              @status : InteractionStatus? = nil,
              @index : Int32? = nil,
              @content : Content? = nil,
              @delta : ContentDelta? = nil,
              @error : ErrorEvent? = nil,
              @event_id : String? = nil,
            )
            end

            def self.from_json_value(value : JSON::Any) : self
              case value["event_type"].as_s
              when "interaction.start"
                new(Kind::InteractionStart, interaction: Interaction.from_json(value["interaction"].to_json), event_id: value["event_id"]?.try(&.as_s?))
              when "interaction.complete"
                new(Kind::InteractionComplete, interaction: Interaction.from_json(value["interaction"].to_json), event_id: value["event_id"]?.try(&.as_s?))
              when "interaction.status_update"
                new(
                  Kind::InteractionStatusUpdate,
                  interaction_id: value["interaction_id"].as_s,
                  status: InteractionStatus.from_json(value["status"].to_json),
                  event_id: value["event_id"]?.try(&.as_s?)
                )
              when "content.start"
                new(Kind::ContentStart, index: value["index"].as_i, content: Content.from_json(value["content"].to_json), event_id: value["event_id"]?.try(&.as_s?))
              when "content.delta"
                new(Kind::ContentDelta, index: value["index"].as_i, delta: ContentDelta.from_json(value["delta"].to_json), event_id: value["event_id"]?.try(&.as_s?))
              when "content.stop"
                new(Kind::ContentStop, index: value["index"].as_i, event_id: value["event_id"]?.try(&.as_s?))
              when "error"
                new(Kind::Error, error: ErrorEvent.from_json(value["error"].to_json), event_id: value["event_id"]?.try(&.as_s?))
              else
                raise Crig::Completion::CompletionError.new("Unknown Gemini interactions SSE event type")
              end
            end

            def self.new(pull : JSON::PullParser)
              from_json_value(JSON::Any.new(pull))
            end
          end

          def self.stream(model : InteractionsCompletionModel, request : Crig::Completion::Request::CompletionRequest)
            payload = model.create_completion_request(request, true)
            response = model.client.post_json("/v1beta/interactions", payload.to_json, sse: true)
            body = response.body
            raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400
            Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(parse_streaming_choices(body))
          end

          def self.parse_event_stream(text : String) : InteractionEventStream
            events = [] of InteractionSseEvent
            text.each_line do |line|
              next unless line.starts_with?("data:")
              data_str = line[5..].to_s.strip
              next if data_str.empty? || data_str == "[DONE]"
              begin
                events << InteractionSseEvent.from_json(data_str)
              rescue
              end
            end
            events
          end

          def self.content_start_to_choice(content : Content) : Crig::RawStreamingChoice(StreamingCompletionResponse)?
            case content.kind
            in .text?
              text = content.text.as(TextContent).text
              text.empty? ? nil : Crig::RawStreamingChoice(StreamingCompletionResponse).message(text)
            in .function_call?
              function_call = content.function_call.as(FunctionCallContent)
              name = function_call.name
              return if name.nil?
              call_id = function_call.id || name
              Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
                Crig::RawStreamingToolCall.new(name, name, function_call.arguments || JSON.parse("{}")).with_call_id(call_id)
              )
            in .image?, .audio?, .document?, .video?, .thought?, .function_result?, .code_execution_call?,
               .code_execution_result?, .url_context_call?, .url_context_result?, .google_search_call?,
               .google_search_result?, .mcp_server_tool_call?, .mcp_server_tool_result?, .file_search_result?
            end
          end

          def self.content_delta_to_choice(delta : ContentDelta) : Crig::RawStreamingChoice(StreamingCompletionResponse)?
            case delta.kind
            in .text?
              text = delta.text.as(TextDelta).text
              text ? Crig::RawStreamingChoice(StreamingCompletionResponse).message(text) : nil
            in .function_call?
              function_call = delta.function_call.as(FunctionCallDelta)
              name = function_call.name
              return if name.nil?
              call_id = function_call.id || name
              Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
                Crig::RawStreamingToolCall.new(name, name, function_call.arguments || JSON.parse("{}")).with_call_id(call_id)
              )
            in .thought_summary?
              content = delta.thought_summary.as(ThoughtSummaryDelta).content
              return unless content.kind.text?
              Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, content.text.as(TextContent).text)
            in .image?, .audio?, .document?, .video?, .thought_signature?, .function_result?,
               .code_execution_call?, .code_execution_result?, .url_context_call?, .url_context_result?,
               .google_search_call?, .google_search_result?, .mcp_server_tool_call?, .mcp_server_tool_result?,
               .file_search_result?
            end
          end

          def self.parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
            raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
            final_interaction = nil.as(Interaction?)
            final_usage = nil.as(InteractionUsage?)

            parse_event_stream(text).each do |event|
              case event.kind
              in .content_start?
                if choice = content_start_to_choice(event.content.as(Content))
                  raw_choices << choice
                end
              in .content_delta?
                if choice = content_delta_to_choice(event.delta.as(ContentDelta))
                  raw_choices << choice
                end
              in .interaction_complete?
                interaction = event.interaction.as(Interaction)
                final_interaction = interaction
                final_usage = interaction.usage
              in .error?
                raise Crig::Completion::CompletionError.new(event.error.as(ErrorEvent).message)
              in .interaction_start?, .interaction_status_update?, .content_stop?
              end
            end

            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
              StreamingCompletionResponse.new(final_usage, final_interaction)
            )
            raw_choices
          end
        end
      end
    end
  end
end
