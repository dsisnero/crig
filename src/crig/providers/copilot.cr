require "http/client"

module Crig
  module Providers
    module Copilot
      GITHUB_COPILOT_API_BASE_URL = "https://api.githubcopilot.com"

      GPT_4                  = "gpt-4"
      GPT_4O                 = "gpt-4o"
      GPT_4O_MINI            = "gpt-4o-mini"
      GPT_4_1                = "gpt-4.1"
      GPT_4_1_MINI           = "gpt-4.1-mini"
      GPT_4_1_NANO           = "gpt-4.1-nano"
      GPT_5_3_CODEX          = "gpt-5.3-codex"
      GPT_5_1_CODEX          = "gpt-5.1-codex"
      GPT_5_5                = "gpt-5.5"
      GPT_5_4                = "gpt-5.4"
      CLAUDE_SONNET_4        = "claude-sonnet-4"
      CLAUDE_SONNET_4_6      = "claude-sonnet-4.6"
      CLAUDE_OPUS_4_6        = "claude-opus-4.6"
      CLAUDE_OPUS_4_7        = "claude-opus-4.7"
      CLAUDE_3_5_SONNET      = "claude-3.5-sonnet"
      GEMINI_3_FLASH         = "gemini-3-flash-preview"
      GEMINI_3_1_PRO_FLASH   = "gemini-3.1-pro-preview"
      GEMINI_2_0_FLASH       = "gemini-2.0-flash-001"
      O3_MINI                = "o3-mini"
      TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small"
      TEXT_EMBEDDING_3_LARGE = "text-embedding-3-large"
      TEXT_EMBEDDING_ADA_002 = "text-embedding-ada-002"

      CODEX_MODELS = [GPT_5_3_CODEX, GPT_5_1_CODEX]

      struct CopilotBuilder
        getter access_token : String?
        getter base_url : String

        def initialize(
          @access_token : String? = nil,
          @base_url : String = GITHUB_COPILOT_API_BASE_URL,
        )
        end

        def access_token(token : String) : self
          self.class.new(token, @base_url)
        end

        def base_url(url : String) : self
          self.class.new(@access_token, url)
        end

        def build : Client
          token = @access_token || raise "GITHUB_COPILOT_ACCESS_TOKEN not set"
          Client.new(token, @base_url)
        end
      end

      struct Client
        getter access_token : String
        getter base_url : String

        def initialize(
          @access_token : String,
          @base_url : String = GITHUB_COPILOT_API_BASE_URL,
        )
        end

        def self.builder : CopilotBuilder
          CopilotBuilder.new
        end

        def self.from_env : self
          token = ENV["GITHUB_TOKEN"]? || ENV["GITHUB_COPILOT_ACCESS_TOKEN"]? ||
                  ENV["GITHUB_COPILOT_TOKEN"]? || raise "GITHUB_TOKEN not set"
          base_url = ENV["GITHUB_COPILOT_API_BASE"]? || GITHUB_COPILOT_API_BASE_URL
          new(token, base_url)
        end

        def self.from_val(token : String) : self
          new(token)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def embedding_model(model : String) : EmbeddingModel
          EmbeddingModel.new(self, model)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization"          => "Bearer #{@access_token}",
            "Content-Type"           => "application/json",
            "Accept"                 => "application/json",
            "Copilot-Integration-Id" => "vscode-chat",
            "Editor-Plugin-Version"  => "copilot-chat/0.26.7",
            "User-Agent"             => "GitHubCopilotChat/0.26.7",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
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
          if codex_model?
            completion_responses(request)
          else
            completion_chat(request)
          end
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          if codex_model?
            stream_responses(request)
          else
            stream_chat(request)
          end
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        private def codex_model? : Bool
          CODEX_MODELS.includes?(@model)
        end

        private def completion_chat(request : Crig::Completion::Request::CompletionRequest)
          payload = Crig::Providers::OpenAI::CompletionRequest.new(
            model: @model,
            messages: build_chat_messages(request),
            temperature: request.temperature,
            tools: request.tools.map { |t| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(t) },
            max_tokens: request.max_tokens,
          )
          response = @client.post_json("/chat/completions", payload.to_json_value.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("Copilot (#{response.status_code}): #{text}") unless response.success?

          parsed = JSON.parse(text)
          chat_response = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(parsed)
          chat_response.to_completion_response(parsed)
        end

        private def completion_responses(request : Crig::Completion::Request::CompletionRequest)
          payload = Crig::Providers::OpenAI::CompletionRequest.new(
            model: @model,
            input: build_responses_input(request),
            tools: request.tools.map { |t| Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool(t) },
          )
          response = @client.post_json("/responses", payload.to_json_value.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("Copilot (#{response.status_code}): #{text}") unless response.success?

          parsed = JSON.parse(text)
          body = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(text)
          Crig::Completion::CompletionResponse(JSON::Any).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.text(text),
            ),
            Crig::Completion::Usage.new,
            parsed,
          )
        end

        private def stream_chat(request : Crig::Completion::Request::CompletionRequest)
          payload = Crig::Providers::OpenAI::CompletionRequest.new(
            model: @model,
            messages: build_chat_messages(request),
            temperature: request.temperature,
            tools: request.tools.map { |t| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(t) },
            max_tokens: request.max_tokens,
            stream: true,
          )
          response = @client.post_json(
            "/chat/completions",
            payload.to_json_value.to_json,
            {"Accept" => "text/event-stream"},
          )
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("Copilot (#{response.status_code}): #{text}") unless response.success?

          raw_choices = parse_chat_stream(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        private def stream_responses(request : Crig::Completion::Request::CompletionRequest)
          payload = Crig::Providers::OpenAI::CompletionRequest.new(
            model: @model,
            input: build_responses_input(request),
            tools: request.tools.map { |t| Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool(t) },
            stream: true,
          )
          response = @client.post_json(
            "/responses",
            payload.to_json_value.to_json,
            {"Accept" => "text/event-stream"},
          )
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("Copilot (#{response.status_code}): #{text}") unless response.success?

          raw_choices = parse_responses_stream(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        private def build_chat_messages(request : Crig::Completion::Request::CompletionRequest) : Array(Crig::Providers::OpenAI::Chat::Message)
          messages = [] of Crig::Providers::OpenAI::Chat::Message
          if preamble = request.preamble
            messages << Crig::Providers::OpenAI::Chat::Message.system(preamble)
          end
          request.chat_history.each do |msg|
            Crig::Providers::OpenAI::Chat::Message.from_core_message(msg).each do |item|
              messages << item
            end
          end
          messages
        end

        private def build_responses_input(request : Crig::Completion::Request::CompletionRequest) : Array(Crig::Providers::OpenAI::InputItem)
          items = [] of Crig::Providers::OpenAI::InputItem
          if preamble = request.preamble
            items << Crig::Providers::OpenAI::InputItem.system_message(preamble)
          end
          request.chat_history.each do |msg|
            items.concat(Crig::Providers::OpenAI::InputItem.from_completion_message(msg))
          end
          items
        end

        private def parse_chat_stream(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          final_usage = Crig::Completion::Usage.new

          text.each_line do |line|
            next unless line.starts_with?("data: ")
            data = line.lchop("data: ").strip
            next if data.empty? || data == "[DONE]"

            chunk = JSON.parse(data)
            choices = chunk["choices"]?.try(&.as_a) || [] of JSON::Any
            choices.each do |choice|
              delta = choice["delta"]?
              if text_delta = delta.try(&.["content"]?).try(&.as_s?)
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(text_delta)
              end
            end
            if usage = chunk["usage"]?
              final_usage = Crig::Completion::Usage.new(
                input_tokens: usage["prompt_tokens"]?.try(&.as_i64) || 0_i64,
                output_tokens: usage["completion_tokens"]?.try(&.as_i64) || 0_i64,
                total_tokens: usage["total_tokens"]?.try(&.as_i64) || 0_i64,
              )
            end
          end

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(final_usage),
          )
          raw_choices
        end

        private def parse_responses_stream(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          usage = Crig::Completion::Usage.new

          text.each_line do |line|
            next unless line.starts_with?("data: ")
            data = line.lchop("data: ").strip
            next if data.empty? || data == "[DONE]"

            chunk = JSON.parse(data)
            if chunk["type"]?.try(&.as_s) == "response.output_text.delta"
              delta = chunk["delta"]?.try(&.as_s) || ""
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(delta)
            elsif response = chunk["response"]?
              if u = response["usage"]?
                usage = Crig::Completion::Usage.new(
                  input_tokens: u["input_tokens"]?.try(&.as_i64) || 0_i64,
                  output_tokens: u["output_tokens"]?.try(&.as_i64) || 0_i64,
                  total_tokens: u["total_tokens"]?.try(&.as_i64) || 0_i64,
                )
              end
            end
          end

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(usage),
          )
          raw_choices
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def max_documents : Int32
          2048
        end

        def ndims : Int32
          0
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          payload = {"model" => @model, "input" => texts.to_a}
          response = @client.post_json("/embeddings", payload.to_json)
          text = response.body
          raise Crig::Embeddings::EmbeddingError.new("Copilot (#{response.status_code}): #{text}") unless response.success?

          parsed = JSON.parse(text)
          data = parsed["data"].as_a
          data.map do |item|
            embedding = item["embedding"].as_a.map(&.as_f)
            Crig::Embeddings::Embedding.new(item["index"].as_i.to_s, embedding)
          end
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Copilot::CompletionModel)
        include Crig::EmbeddingsClient(Crig::Providers::Copilot::EmbeddingModel)

        def completion_model(model : String) : Crig::Providers::Copilot::CompletionModel
          Crig::Providers::Copilot::CompletionModel.make(self, model)
        end

        def embedding_model(model : String) : Crig::Providers::Copilot::EmbeddingModel
          Crig::Providers::Copilot::EmbeddingModel.new(self, model)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::Providers::Copilot::EmbeddingModel
          Crig::Providers::Copilot::EmbeddingModel.new(self, model)
        end
      end
    end
  end
end
