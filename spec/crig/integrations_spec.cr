require "../spec_helper"
describe Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided) do
  it "builds chat and agent chatbot variants" do
    chat_builder = Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
    chat = FakeChatIntegration.new
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new)

    chat_builder.chat(chat).build.should be_a(Crig::Integrations::ChatBot(Crig::Integrations::ChatImpl(FakeChatIntegration)))
    chat_builder.agent(agent).max_turns(2).show_usage.build.should be_a(
      Crig::Integrations::ChatBot(Crig::Integrations::AgentImpl(FakeCliChatbotCompletionModel))
    )
  end
end

describe Crig::Integrations::ChatBot(Crig::Integrations::ChatImpl(FakeChatIntegration)) do
  it "runs the chat loop against a chat implementation" do
    chat = FakeChatIntegration.new
    bot = Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new.chat(chat).build
    input = IO::Memory.new("hello\nexit\n")
    output = IO::Memory.new

    bot.run(input, output)

    rendered = output.to_s
    rendered.should contain("> ")
    rendered.should contain("chat: hello")
    rendered.should contain("========================== Response ============================")
    chat.seen.size.should eq(1)
    chat.seen.first[0].should eq("hello")
  end
end

describe Crig::Integrations::ChatBot(Crig::Integrations::AgentImpl(FakeCliChatbotCompletionModel)) do
  it "runs the chat loop against an agent implementation and prints usage" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new)
    bot = Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
      .agent(agent)
      .max_turns(2)
      .show_usage
      .build
    input = IO::Memory.new("hello\nexit\n")
    output = IO::Memory.new

    bot.run(input, output)

    rendered = output.to_s
    rendered.should contain("agent reply")
    rendered.should contain("Input 3 tokens")
    rendered.should contain("Output 2 tokens")
  end
end

describe Crig::Integrations::DiscordExt do
  it "builds a discordcr-backed discord client from an agent" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new)
    client = agent.into_discord_bot("discord-token")

    client.token.should eq("discord-token")
    client.intents.should eq(
      Discord::Gateway::Intents::Guilds |
      Discord::Gateway::Intents::GuildMessages |
      Discord::Gateway::Intents::DirectMessages
    )
    client.discord_client.should be_a(Discord::Client)
  end

  it "builds a discord client from DISCORD_BOT_TOKEN" do
    original = ENV["DISCORD_BOT_TOKEN"]?
    ENV["DISCORD_BOT_TOKEN"] = "env-token"

    begin
      agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new)
      agent.into_discord_bot_from_env.token.should eq("env-token")
    ensure
      if original
        ENV["DISCORD_BOT_TOKEN"] = original
      else
        ENV.delete("DISCORD_BOT_TOKEN")
      end
    end
  end

  it "raises when DISCORD_BOT_TOKEN is missing" do
    original = ENV["DISCORD_BOT_TOKEN"]?
    ENV.delete("DISCORD_BOT_TOKEN")

    begin
      agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new)

      expect_raises(KeyError, /DISCORD_BOT_TOKEN should exist as an env var/) do
        agent.into_discord_bot_from_env
      end
    ensure
      ENV["DISCORD_BOT_TOKEN"] = original if original
    end
  end
end

describe Crig::Integrations::DiscordBot::Session(FakeCliChatbotCompletionModel) do
  it "processes inbound messages through channel-based command execution" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new("agent reply"))
    commands = [] of Crig::Integrations::DiscordBot::Command
    session = Crig::Integrations::DiscordBot::Session(FakeCliChatbotCompletionModel).new(
      agent,
      ->(command : Crig::Integrations::DiscordBot::Command) { commands << command; Crig::Integrations::DiscordBot::CommandResult.empty }
    )

    session.submit(
      Crig::Integrations::DiscordBot::Event.message(
        Crig::Integrations::DiscordBot::MessageContext.new(42_u64, "hello")
      )
    )

    commands.map(&.kind).should eq([
      Crig::Integrations::DiscordBot::Command::Kind::TriggerTyping,
      Crig::Integrations::DiscordBot::Command::Kind::SendMessage,
    ])
    commands.last.content.should eq("agent reply")
    session.history_for(42_u64).should eq([
      Crig::Completion::Message.user("hello"),
      Crig::Completion::Message.assistant("agent reply"),
    ])
  end

  it "ignores bot-authored and blank messages" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new("agent reply"))
    commands = [] of Crig::Integrations::DiscordBot::Command
    session = Crig::Integrations::DiscordBot::Session(FakeCliChatbotCompletionModel).new(
      agent,
      ->(command : Crig::Integrations::DiscordBot::Command) { commands << command; Crig::Integrations::DiscordBot::CommandResult.empty }
    )

    session.submit(
      Crig::Integrations::DiscordBot::Event.message(
        Crig::Integrations::DiscordBot::MessageContext.new(7_u64, "from bot", true)
      )
    )
    session.submit(
      Crig::Integrations::DiscordBot::Event.message(
        Crig::Integrations::DiscordBot::MessageContext.new(7_u64, "   ")
      )
    )

    commands.should eq([] of Crig::Integrations::DiscordBot::Command)
    session.history_for(7_u64).should eq([] of Crig::Completion::Message)
  end

  it "splits long responses into discord-sized message chunks" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new("x" * 2005))
    commands = [] of Crig::Integrations::DiscordBot::Command
    session = Crig::Integrations::DiscordBot::Session(FakeCliChatbotCompletionModel).new(
      agent,
      ->(command : Crig::Integrations::DiscordBot::Command) { commands << command; Crig::Integrations::DiscordBot::CommandResult.empty }
    )

    session.submit(
      Crig::Integrations::DiscordBot::Event.message(
        Crig::Integrations::DiscordBot::MessageContext.new(9_u64, "hello")
      )
    )

    send_commands = commands.select(&.kind.send_message?)
    send_commands.size.should eq(2)
    send_commands.first.content.not_nil!.size.should eq(1900)
    send_commands.last.content.not_nil!.size.should eq(105)
  end

  it "creates a new thread session from the slash command through channel-based command execution" do
    agent = Crig::Agent(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new("agent reply"))
    commands = [] of Crig::Integrations::DiscordBot::Command
    session = Crig::Integrations::DiscordBot::Session(FakeCliChatbotCompletionModel).new(
      agent,
      ->(command : Crig::Integrations::DiscordBot::Command) do
        commands << command
        if command.kind.create_thread?
          Crig::Integrations::DiscordBot::CommandResult.new(99_u64)
        else
          Crig::Integrations::DiscordBot::CommandResult.empty
        end
      end
    )

    session.submit(
      Crig::Integrations::DiscordBot::Event.interaction(
        Crig::Integrations::DiscordBot::InteractionContext.new(
          42_u64,
          7_u64,
          "interaction-token",
          "new",
          "dominiclabs",
        )
      )
    )

    commands.map(&.kind).should eq([
      Crig::Integrations::DiscordBot::Command::Kind::DeferInteraction,
      Crig::Integrations::DiscordBot::Command::Kind::CreateThread,
      Crig::Integrations::DiscordBot::Command::Kind::EditInteractionResponse,
      Crig::Integrations::DiscordBot::Command::Kind::SendMessage,
    ])
    commands[1].thread_name.should eq("AI Conversation - dominiclabs")
    commands[3].channel_id.should eq(99_u64)
    session.history_for(99_u64).should eq([] of Crig::Completion::Message)
  end
end
