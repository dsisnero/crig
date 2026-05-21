require "http/client"
require "random/secure"
require "./chatgpt/oauth"

module Crig
  module Providers
    module ChatGPT
      CHATGPT_API_BASE_URL = "https://chatgpt.com/backend-api/codex"
      DEFAULT_ORIGINATOR   = "rig"
      DEFAULT_INSTRUCTIONS = "You are ChatGPT, a helpful AI assistant."

      GPT_5_4             = "gpt-5.4"
      GPT_5_4_PRO         = "gpt-5.4-pro"
      GPT_5_3_CODEX       = "gpt-5.3-codex"
      GPT_5_3_CODEX_SPARK = "gpt-5.3-codex-spark"
      GPT_5_3_INSTANT     = "gpt-5.3-instant"
      GPT_5_3_CHAT_LATEST = "gpt-5.3-chat-latest"

      DEFAULT_USER_AGENT = "rig-crystal"

      enum AuthSource
        AccessToken
        OAuth
      end

      struct ChatGPTExt
        getter access_token : String?
        getter account_id : String?
        getter auth_source : AuthSource
        getter default_instructions : String?
        getter originator : String
        getter user_agent : String

        def initialize(
          @auth_source : AuthSource = AuthSource::AccessToken,
          @access_token : String? = nil,
          @account_id : String? = nil,
          @default_instructions : String? = DEFAULT_INSTRUCTIONS,
          @originator : String = DEFAULT_ORIGINATOR,
          @user_agent : String = DEFAULT_USER_AGENT,
        )
        end
      end

      struct ChatGPTBuilder
        getter access_token : String?
        getter account_id : String?
        getter base_url : String
        getter default_instructions : String?
        getter originator : String
        getter user_agent : String?
        property device_code_handler : Proc(OAuth::DeviceCodePrompt, Nil)?
        property auth_file : String?

        def initialize(
          @access_token : String? = nil,
          @account_id : String? = nil,
          @base_url : String = CHATGPT_API_BASE_URL,
          @default_instructions : String? = DEFAULT_INSTRUCTIONS,
          @originator : String = DEFAULT_ORIGINATOR,
          @user_agent : String? = nil,
        )
        end

        def access_token(token : String) : self
          self.class.new(token, @account_id, @base_url, @default_instructions, @originator, @user_agent)
        end

        def account_id(id : String) : self
          self.class.new(@access_token, id, @base_url, @default_instructions, @originator, @user_agent)
        end

        def base_url(url : String) : self
          self.class.new(@access_token, @account_id, url, @default_instructions, @originator, @user_agent)
        end

        def default_instructions(instructions : String) : self
          self.class.new(@access_token, @account_id, @base_url, instructions, @originator, @user_agent)
        end

        def originator(originator : String) : self
          self.class.new(@access_token, @account_id, @base_url, @default_instructions, originator, @user_agent)
        end

        def user_agent(agent : String) : self
          self.class.new(@access_token, @account_id, @base_url, @default_instructions, @originator, agent)
        end

        # Enable OAuth device-code authentication instead of access-token auth.
        def oauth : self
          self.class.new(@access_token, @account_id, @base_url, @default_instructions, @originator, @user_agent)
        end

        # Set a callback for displaying the device code prompt to the user.
        def on_device_code(&handler : OAuth::DeviceCodePrompt -> Nil) : self
          @device_code_handler = handler
          self
        end

        def token_dir(path : String) : self
          @auth_file = File.join(path, "auth.json")
          self
        end

        def build : Client
          token = @access_token || raise "CHATGPT_ACCESS_TOKEN not set"
          client = Client.new(
            token,
            @account_id,
            @base_url,
            @default_instructions,
            @originator,
            @user_agent || DEFAULT_USER_AGENT,
          )
          client
        end
      end

      struct Client
        getter access_token : String
        getter account_id : String?
        getter base_url : String
        getter ext : ChatGPTExt

        def initialize(
          @access_token : String,
          @account_id : String? = nil,
          @base_url : String = CHATGPT_API_BASE_URL,
          @default_instructions : String? = DEFAULT_INSTRUCTIONS,
          @originator : String = DEFAULT_ORIGINATOR,
          @user_agent : String = DEFAULT_USER_AGENT,
        )
          @ext = ChatGPTExt.new(
            auth_source: AuthSource::AccessToken,
            access_token: @access_token,
            account_id: @account_id,
            default_instructions: @default_instructions,
            originator: @originator,
            user_agent: @user_agent,
          )
        end

        def self.builder : ChatGPTBuilder
          ChatGPTBuilder.new
        end

        def self.from_env : self
          token = ENV["CHATGPT_ACCESS_TOKEN"]? || raise "CHATGPT_ACCESS_TOKEN not set"
          account_id = ENV["CHATGPT_ACCOUNT_ID"]?
          base_url = ENV["CHATGPT_API_BASE"]? || ENV["OPENAI_CHATGPT_API_BASE"]? || CHATGPT_API_BASE_URL
          new(token, account_id, base_url)
        end

        def self.from_val(token : String) : self
          new(token)
        end

        # Trigger the OAuth device-code flow. Resolves when user authorizes.
        def oauth_authenticate(authenticator : OAuth::Authenticator) : Nil
          context = authenticator.auth_context
          @access_token = context.access_token
          @account_id = context.account_id
        end

        def completion_model(model : String) : ResponsesCompletionModel
          ResponsesCompletionModel.new(self, model)
        end

        def post(path : String, body : String) : HTTP::Client::Response
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@access_token}",
            "Content-Type"  => "application/json",
            "Accept"        => "text/event-stream",
            "originator"    => @ext.originator,
            "user-agent"    => @ext.user_agent,
            "session_id"    => Random::Secure.hex(10),
          }
          headers["ChatGPT-Account-Id"] = @account_id if @account_id
          HTTP::Client.exec("POST", build_uri(path), headers: headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end

      struct ResponsesCompletionModel
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
          span = Crig::Span.chat_span("chatgpt", @model, request.preamble, nil)

          chatgpt_request = create_chatgpt_request(request)
          response = @client.post("/responses", chatgpt_request.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("ChatGPT (#{response.status_code}): #{text}") unless response.success?

          body = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(text)
          if error = body.error
            raise Crig::Completion::CompletionError.provider_error("ChatGPT: #{error.message}")
          end
          result = parse_completion_response(body)
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          chatgpt_request = create_chatgpt_request(request)
          response = @client.post("/responses", chatgpt_request.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.provider_error("ChatGPT (#{response.status_code}): #{text}") unless response.success?

          raw_choices = parse_streaming_choices(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        private def create_chatgpt_request(request : Crig::Completion::Request::CompletionRequest) : Crig::Providers::OpenAI::CompletionRequest
          # Build the base Responses API request using OpenAI's request builder
          openai_model = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
            Crig::Providers::OpenAI::Client.new("dummy-key", "https://api.openai.com/v1"),
            @model,
          )
          chatgpt_request = openai_model.create_completion_request(request)

          # Extract system messages into instructions (ChatGPT uses instructions field)
          system_texts = extract_system_instructions(chatgpt_request)
          unless system_texts.empty?
            merged = system_texts.join("\n\n")
            chatgpt_request.instructions = if existing = chatgpt_request.instructions
                                             "#{merged}\n\n#{existing}"
                                           else
                                             merged
                                           end
          end

          # Merge default instructions (avoiding duplicates)
          if default = @client.ext.default_instructions
            chatgpt_request.instructions = merge_instructions(default, chatgpt_request.instructions)
          end

          # ChatGPT-specific modifications: drop temperature, force stream, add reasoning include
          chatgpt_request.temperature = nil
          chatgpt_request.max_output_tokens = nil
          chatgpt_request.stream = true

          existing_include = chatgpt_request.include || [] of String
          unless existing_include.includes?("reasoning.encrypted_content")
            chatgpt_request.include = existing_include + ["reasoning.encrypted_content"]
          end

          chatgpt_request
        end

        private def extract_system_instructions(request : Crig::Providers::OpenAI::CompletionRequest) : Array(String)
          instructions = [] of String
          filtered = [] of Crig::Providers::OpenAI::InputItem
          request.input.each do |item|
            if item.role == "system" && (text = item.content)
              instructions << text.strip unless text.strip.empty?
            else
              filtered << item
            end
          end
          request.input = filtered
          instructions
        end

        private def merge_instructions(default : String, existing : String?) : String
          case existing.try(&.strip)
          when nil, ""
            default
          when .includes?(default)
            existing.not_nil!
          else
            "#{default}\n\n#{existing}"
          end
        end

        private def parse_completion_response(body : Crig::Providers::OpenAI::CompletionResponsePayload) : Crig::Completion::CompletionResponse(JSON::Any)
          choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many(
            body.output.compact_map do |output|
              case output.type
              when "message"
                content_parts = output.content || [] of Crig::Providers::OpenAI::ContentPart
                text = content_parts.map { |cp| cp.text.try(&.as_s) || "" }.join
                Crig::Completion::AssistantContent.text(text)
              end
            end
          )

          usage = body.usage || Crig::Providers::OpenAI::ResponsesUsage.new(0_i64, 0_i64, 0_i64)
          rig_usage = Crig::Completion::Usage.new(
            input_tokens: usage.input_tokens,
            output_tokens: usage.output_tokens,
            total_tokens: usage.total_tokens,
          )

          Crig::Completion::CompletionResponse(JSON::Any).new(choice, rig_usage, body.to_json)
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          accumulated_text = ""
          usage = Crig::Completion::Usage.new

          text.each_line do |line|
            next unless line.starts_with?("data: ")
            data = line.lchop("data: ").strip
            next if data.empty? || data == "[DONE]"

            chunk = JSON.parse(data)
            case chunk["type"]?.try(&.as_s)
            when "response.output_text.delta"
              delta = chunk["delta"]?.try(&.as_s) || ""
              accumulated_text += delta
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(delta)
            when "response.completed"
              if response = chunk["response"]?
                if u = response["usage"]?
                  usage = Crig::Completion::Usage.new(
                    input_tokens: u["input_tokens"]?.try(&.as_i64) || 0_i64,
                    output_tokens: u["output_tokens"]?.try(&.as_i64) || 0_i64,
                    total_tokens: u["total_tokens"]?.try(&.as_i64) || 0_i64,
                  )
                end
              end
            end
          end

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(usage)
          )
          raw_choices
        end
      end
    end
  end
end
