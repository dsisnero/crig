require "../src/crig"

module Crig::Examples::AgentWithHuggingFace
  MODEL          = "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B"
  BASIC_PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."
  TOOLS_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."
  CONTEXT_PROMPT = "What does \"glarb-glarb\" mean?"

  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  struct Adder
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "add"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "add",
        "Add x and y together",
        JSON.parse(%({"type":"object","properties":{"x":{"type":"number","description":"The first number to add"},"y":{"type":"number","description":"The second number to add"}}}))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x + args.y
    end
  end

  struct Subtract
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "subtract"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "subtract",
        "Subtract y from x (i.e.: x - y)",
        JSON.parse(%({"type":"object","properties":{"x":{"type":"number","description":"The number to subtract from"},"y":{"type":"number","description":"The number to subtract"}}}))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x - args.y
    end
  end

  TOOLS = [Adder.new.as(Crig::ToolDyn), Subtract.new.as(Crig::ToolDyn)]

  def self.build_partial_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = MODEL,
  ) : Crig::AgentBuilder(Crig::Providers::HuggingFace::CompletionModel)
    client.agent(model)
  end

  def self.build_basic_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::HuggingFace::CompletionModel)
    build_partial_agent(client, model)
      .preamble(BASIC_PREAMBLE)
      .build
  end

  def self.build_tools_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::HuggingFace::CompletionModel)
    build_partial_agent(client, model)
      .preamble(TOOLS_PREAMBLE)
      .max_tokens(1024)
      .tools(TOOLS)
      .build
  end

  def self.load_examples(glob : String) : Array(Tuple(String, String))
    Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError)
      .with_glob(glob)
      .read_with_path
      .ignore_errors
      .to_a
  end

  def self.build_loader_agent(
    client : Crig::Providers::HuggingFace::Client,
    glob : String,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::HuggingFace::CompletionModel)
    load_examples(glob)
      .reduce(build_partial_agent(client, model)) do |builder, (path, content)|
        builder.context("Rust Example #{path.inspect}:\n#{content}")
      end
      .build
  end

  def self.build_context_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::HuggingFace::CompletionModel)
    build_partial_agent(client, model)
      .context("Definition of a *flurbo*: A flurbo is a green alien that lives on cold planets")
      .context("Definition of a *glarb-glarb*: A glarb-glarb is an ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.")
      .context("Definition of a *linglingdong*: A term used by inhabitants of the far side of the moon to describe humans.")
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
