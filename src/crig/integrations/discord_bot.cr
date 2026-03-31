require "discordcr"

module Crig
  module Integrations
    module DiscordExt
      DISCORD_BOT_TOKEN_ENV = "DISCORD_BOT_TOKEN"

      abstract def into_discord_bot(token : String) : Crig::Integrations::DiscordBot::Client

      def into_discord_bot_from_env : Crig::Integrations::DiscordBot::Client
        token = ENV[DISCORD_BOT_TOKEN_ENV]? ||
                raise KeyError.new("#{DISCORD_BOT_TOKEN_ENV} should exist as an env var")
        into_discord_bot(token)
      end
    end

    module DiscordBot
      DEFAULT_ERROR_MESSAGE = "Sorry, I encountered an error processing your message."

      struct MessageContext
        getter channel_id : UInt64
        getter content : String
        getter? author_bot : Bool

        def initialize(@channel_id : UInt64, @content : String, @author_bot : Bool = false)
        end

        def self.from_discord(message : Discord::Message) : self
          new(
            message.channel_id.to_u64,
            message.content,
            message.author.bot || false,
          )
        end
      end

      struct Event
        enum Kind
          Message
          Interaction
        end

        getter kind : Kind
        getter message : MessageContext?
        getter interaction : InteractionContext?

        def initialize(@kind : Kind, @message : MessageContext? = nil, @interaction : InteractionContext? = nil)
        end

        def self.message(message : MessageContext) : self
          new(Kind::Message, message)
        end

        def self.interaction(interaction : InteractionContext) : self
          new(Kind::Interaction, interaction: interaction)
        end
      end

      struct InteractionContext
        getter channel_id : UInt64
        getter interaction_id : UInt64
        getter token : String
        getter command_name : String
        getter user_name : String

        def initialize(
          @channel_id : UInt64,
          @interaction_id : UInt64,
          @token : String,
          @command_name : String,
          @user_name : String,
        )
        end
      end

      struct Command
        enum Kind
          SendMessage
          TriggerTyping
          DeferInteraction
          CreateThread
          EditInteractionResponse
        end

        getter kind : Kind
        getter channel_id : UInt64?
        getter content : String?
        getter interaction_id : UInt64?
        getter interaction_token : String?
        getter thread_name : String?

        def initialize(
          @kind : Kind,
          @channel_id : UInt64? = nil,
          @content : String? = nil,
          @interaction_id : UInt64? = nil,
          @interaction_token : String? = nil,
          @thread_name : String? = nil,
        )
        end

        def self.send_message(channel_id : UInt64, content : String) : self
          new(Kind::SendMessage, channel_id, content)
        end

        def self.trigger_typing(channel_id : UInt64) : self
          new(Kind::TriggerTyping, channel_id)
        end

        def self.defer_interaction(interaction_id : UInt64, interaction_token : String) : self
          new(Kind::DeferInteraction, interaction_id: interaction_id, interaction_token: interaction_token)
        end

        def self.create_thread(channel_id : UInt64, thread_name : String) : self
          new(Kind::CreateThread, channel_id: channel_id, thread_name: thread_name)
        end

        def self.edit_interaction_response(interaction_token : String, content : String) : self
          new(Kind::EditInteractionResponse, content: content, interaction_token: interaction_token)
        end
      end

      struct CommandResult
        getter thread_id : UInt64?

        def initialize(@thread_id : UInt64? = nil)
        end

        def self.empty : self
          new
        end
      end

      struct EventRequest
        getter event : Event
        getter reply_channel : Channel(Crig::Concurrency::Result(Nil))

        def initialize(@event : Event, @reply_channel : Channel(Crig::Concurrency::Result(Nil)))
        end
      end

      struct CommandRequest
        getter command : Command
        getter reply_channel : Channel(Crig::Concurrency::Result(CommandResult))

        def initialize(@command : Command, @reply_channel : Channel(Crig::Concurrency::Result(CommandResult)))
        end
      end

      class Session(M)
        getter inbox : Channel(EventRequest)
        getter outbox : Channel(CommandRequest)

        def initialize(@agent : Crig::Agent(M), @executor : Command -> CommandResult)
          @inbox = Channel(EventRequest).new
          @outbox = Channel(CommandRequest).new
          @conversations = {} of UInt64 => Array(Crig::Completion::Message)

          spawn { process_events }
          spawn { process_commands }
        end

        def submit(event : Event) : Nil
          submit_async(event).receive.unwrap
        end

        def submit_async(event : Event) : Channel(Crig::Concurrency::Result(Nil))
          reply_channel = Channel(Crig::Concurrency::Result(Nil)).new(1)
          @inbox.send(EventRequest.new(event, reply_channel))
          reply_channel
        end

        def history_for(channel_id : UInt64) : Array(Crig::Completion::Message)
          @conversations[channel_id]?.try(&.dup) || [] of Crig::Completion::Message
        end

        private def process_events : Nil
          loop do
            request = @inbox.receive
            begin
              handle_event(request.event)
              request.reply_channel.send(Crig::Concurrency::Result(Nil).success(nil))
            rescue ex : Exception
              request.reply_channel.send(Crig::Concurrency::Result(Nil).failure(ex))
            ensure
              request.reply_channel.close
            end
          end
        end

        private def process_commands : Nil
          loop do
            request = @outbox.receive
            begin
              result = @executor.call(request.command)
              request.reply_channel.send(Crig::Concurrency::Result(CommandResult).success(result))
            rescue ex : Exception
              request.reply_channel.send(Crig::Concurrency::Result(CommandResult).failure(ex))
            ensure
              request.reply_channel.close
            end
          end
        end

        private def handle_event(event : Event) : Nil
          case event.kind
          when .message?
            message = event.message || raise "missing message context"
            handle_message(message)
          when .interaction?
            interaction = event.interaction || raise "missing interaction context"
            handle_interaction(interaction)
          end
        end

        private def handle_interaction(interaction : InteractionContext) : Nil
          return unless interaction.command_name == "new"

          send_command(Command.defer_interaction(interaction.interaction_id, interaction.token))

          thread_name = "AI Conversation - #{interaction.user_name}"
          thread_result = send_command(Command.create_thread(interaction.channel_id, thread_name))
          thread_id = thread_result.thread_id || raise "missing created thread id"

          @conversations[thread_id] = [] of Crig::Completion::Message

          send_command(
            Command.edit_interaction_response(
              interaction.token,
              "Started a new conversation in <##{thread_id}>! Send messages there to chat with the AI."
            )
          )
          send_command(
            Command.send_message(
              thread_id,
              "Hello! I'm ready to help. What would you like to talk about?"
            )
          )
        end

        private def handle_message(message : MessageContext) : Nil
          channel_id = message.channel_id
          return if message.author_bot?

          prompt = message.content.strip
          return if prompt.empty?

          send_command(Command.trigger_typing(channel_id))

          history = history_for(channel_id)
          response = @agent.chat(prompt, history)

          history << Crig::Completion::Message.user(prompt)
          history << Crig::Completion::Message.assistant(response)
          @conversations[channel_id] = history

          chunk_message(response).each do |chunk|
            send_command(Command.send_message(channel_id, chunk))
          end
        rescue ex : Exception
          send_command(Command.send_message(message.channel_id, DEFAULT_ERROR_MESSAGE))
        end

        private def send_command(command : Command) : CommandResult
          reply_channel = Channel(Crig::Concurrency::Result(CommandResult)).new(1)
          @outbox.send(CommandRequest.new(command, reply_channel))
          reply_channel.receive.unwrap
        end

        private def chunk_message(content : String, limit : Int32 = 1900) : Array(String)
          return [content] of String if content.size <= limit

          content.chars.each_slice(limit).map(&.join).to_a
        end
      end

      class Client(M)
        DEFAULT_INTENTS = Discord::Gateway::Intents::Guilds |
                          Discord::Gateway::Intents::GuildMessages |
                          Discord::Gateway::Intents::DirectMessages

        getter token : String
        getter intents : Discord::Gateway::Intents
        getter discord_client : Discord::Client
        getter session : Session(M)

        def initialize(
          @token : String,
          agent : Crig::Agent(M),
          client_id : UInt64? = nil,
          @intents : Discord::Gateway::Intents = DEFAULT_INTENTS,
        )
          @discord_client = Discord::Client.new(
            token: normalized_token(@token),
            client_id: client_id,
            intents: @intents,
          )
          @session = Session(M).new(agent, ->(command : Command) { execute(command) })
          register_handlers
        end

        def run : Nil
          @discord_client.run
        end

        def stop : Nil
          @discord_client.stop
        end

        private def register_handlers : Nil
          @discord_client.on_ready do |_payload|
            register_new_command
          end

          @discord_client.on_message_create do |message|
            @session.submit_async(Event.message(MessageContext.from_discord(message)))
          end

          @discord_client.on_dispatch do |dispatch|
            type, data = dispatch
            next unless type == "INTERACTION_CREATE"

            if interaction = parse_interaction(data.to_s)
              @session.submit_async(Event.interaction(interaction))
            end
          end
        end

        private def execute(command : Command) : CommandResult
          case command.kind
          when .send_message?
            execute_send_message(command)
          when .trigger_typing?
            execute_trigger_typing(command)
          when .defer_interaction?
            execute_defer_interaction(command)
          when .create_thread?
            execute_create_thread(command)
          when .edit_interaction_response?
            execute_edit_interaction_response(command)
          else
            raise "unsupported discord command kind: #{command.kind}"
          end
        end

        private def normalized_token(token : String) : String
          token.starts_with?("Bot ") ? token : "Bot #{token}"
        end

        private def register_new_command : Nil
          body = JSON.build do |json|
            json.object do
              json.field "name", "new"
              json.field "description", "Start a new chat session with the bot"
            end
          end

          @discord_client.request(
            :application_commands,
            @discord_client.client_id,
            "POST",
            "/applications/#{@discord_client.client_id}/commands",
            HTTP::Headers{"Content-Type" => "application/json"},
            body,
          )
        end

        private def execute_send_message(command : Command) : CommandResult
          @discord_client.create_message(command.channel_id || 0_u64, command.content || "")
          CommandResult.empty
        end

        private def execute_trigger_typing(command : Command) : CommandResult
          @discord_client.trigger_typing_indicator(command.channel_id || 0_u64)
          CommandResult.empty
        end

        private def execute_defer_interaction(command : Command) : CommandResult
          defer_interaction(command.interaction_id || 0_u64, command.interaction_token || "")
          CommandResult.empty
        end

        private def execute_create_thread(command : Command) : CommandResult
          thread_id = create_thread(command.channel_id || 0_u64, command.thread_name || "AI Conversation")
          CommandResult.new(thread_id)
        end

        private def execute_edit_interaction_response(command : Command) : CommandResult
          edit_interaction_response(command.interaction_token || "", command.content || "")
          CommandResult.empty
        end

        private def defer_interaction(interaction_id : UInt64, interaction_token : String) : Nil
          body = JSON.build do |json|
            json.object do
              json.field "type", 5
            end
          end

          @discord_client.request(
            :interaction_callback,
            interaction_id,
            "POST",
            "/interactions/#{interaction_id}/#{interaction_token}/callback",
            HTTP::Headers{"Content-Type" => "application/json"},
            body,
          )
        end

        private def edit_interaction_response(interaction_token : String, content : String) : Nil
          body = JSON.build do |json|
            json.object do
              json.field "content", content
            end
          end

          @discord_client.request(
            :interaction_response_edit,
            @discord_client.client_id,
            "PATCH",
            "/webhooks/#{@discord_client.client_id}/#{interaction_token}/messages/@original",
            HTTP::Headers{"Content-Type" => "application/json"},
            body,
          )
        end

        private def create_thread(channel_id : UInt64, thread_name : String) : UInt64
          body = JSON.build do |json|
            json.object do
              json.field "name", thread_name
              json.field "type", 11
              json.field "auto_archive_duration", 1440
            end
          end

          response = @discord_client.request(
            :channel_threads,
            channel_id,
            "POST",
            "/channels/#{channel_id}/threads",
            HTTP::Headers{"Content-Type" => "application/json"},
            body,
          )

          JSON.parse(response.body)["id"].as_s.to_u64
        end

        private def parse_interaction(payload : String) : InteractionContext?
          data = JSON.parse(payload)
          command_name = data["data"]?.try(&.["name"]?).try(&.as_s?)
          return unless command_name

          channel_id = data["channel_id"].as_s.to_u64
          interaction_id = data["id"].as_s.to_u64
          token = data["token"].as_s
          user_name = data["member"]?.try(&.["user"]?).try(&.["username"]?).try(&.as_s?) ||
                      data["user"]?.try(&.["username"]?).try(&.as_s?) ||
                      "Discord User"

          InteractionContext.new(channel_id, interaction_id, token, command_name, user_name)
        end
      end
    end
  end

  struct Agent(M)
    include Crig::Integrations::DiscordExt

    def into_discord_bot(token : String) : Crig::Integrations::DiscordBot::Client(M)
      Crig::Integrations::DiscordBot::Client(M).new(token, self)
    end
  end
end
