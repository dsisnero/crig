require "../src/crig"

module Crig::Examples::MultiAgent
  struct TranslatorArgs
    include JSON::Serializable

    getter prompt : String

    def initialize(@prompt : String)
    end
  end

  class TranslatorTool(M)
    include Crig::Tool(TranslatorArgs, String)

    getter agent : Crig::Agent(M)

    def initialize(@agent : Crig::Agent(M))
    end

    def name : String
      "translator"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "translator",
        "Translate any text to English. If already in English, fix grammar and syntax issues.",
        JSON.parse(%({
          "type":"object",
          "properties":{"prompt":{"type":"string","description":"The text to translate to English"}},
          "required":["prompt"]
        }))
      )
    end

    def call_typed(args : TranslatorArgs) : String
      @agent.chat(args.prompt, [] of Crig::Completion::Message)
    end
  end

  TRANSLATOR_PREAMBLE = "You are a translator assistant that will translate any input text into english. If the text is already in english, simply respond with the original text but fix any mistakes (grammar, syntax, etc.)."
  SYSTEM_PREAMBLE     = "You are a helpful assistant that can work with text in any language. When you receive input that is not in English, or contains grammatical errors use the translator tool first to ensure proper English, then provide your response. Always show both the translated text and your final response."

  def self.build_translator_agent(
    model : M,
  ) : Crig::Agent(M) forall M
    Crig::AgentBuilder(typeof(model)).new(model)
      .preamble(TRANSLATOR_PREAMBLE)
      .build
  end

  def self.build_multi_agent_system(
    model : M,
  ) : Crig::Agent(M) forall M
    translator_tool = TranslatorTool(typeof(model)).new(build_translator_agent(model))

    Crig::AgentBuilder(typeof(model)).new(model)
      .preamble(SYSTEM_PREAMBLE)
      .tool(translator_tool)
      .build
  end

  def self.build_chatbot(
    agent : Crig::Agent(M),
  ) : Crig::Integrations::ChatBot(Crig::Integrations::AgentImpl(M)) forall M
    Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
      .agent(agent)
      .max_turns(1)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
