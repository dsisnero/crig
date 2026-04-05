require "../src/crig"

module Crig::Examples::CalculatorChatbot
  PREAMBLE = <<-TEXT
  You are a calculator here to help the user perform arithmetic operations.
  Use the tools provided to answer the user's question and do not do any math on your own.
  TEXT

  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  module ArithmeticTool
    def self.parameters(x_description : String, y_description : String) : JSON::Any
      JSON.parse(%({
        "type":"object",
        "properties":{
          "x":{"type":"number","description":"#{x_description}"},
          "y":{"type":"number","description":"#{y_description}"}
        },
        "required":["x","y"]
      }))
    end
  end

  struct Add
    include Crig::ToolEmbedding(OperationArgs, Int32, Nil)

    def self.init(state, context : Nil) : self
      _ = state
      _ = context
      new
    end

    def name : String
      "add"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "add",
        "Add x and y together",
        ArithmeticTool.parameters("The first number to add", "The second number to add"),
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x + args.y
    end

    def embedding_docs : Array(String)
      ["Add x and y together"]
    end

    def typed_context : Nil
      nil
    end
  end

  struct Subtract
    include Crig::ToolEmbedding(OperationArgs, Int32, Nil)

    def self.init(state, context : Nil) : self
      _ = state
      _ = context
      new
    end

    def name : String
      "subtract"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "subtract",
        "Subtract y from x (i.e.: x - y)",
        ArithmeticTool.parameters("The number to subtract from", "The number to subtract"),
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x - args.y
    end

    def embedding_docs : Array(String)
      ["Subtract y from x (i.e.: x - y)"]
    end

    def typed_context : Nil
      nil
    end
  end

  struct Multiply
    include Crig::ToolEmbedding(OperationArgs, Int32, Nil)

    def self.init(state, context : Nil) : self
      _ = state
      _ = context
      new
    end

    def name : String
      "multiply"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "multiply",
        "Compute the product of x and y (i.e.: x * y)",
        ArithmeticTool.parameters("The first factor in the product", "The second factor in the product"),
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x * args.y
    end

    def embedding_docs : Array(String)
      ["Compute the product of x and y (i.e.: x * y)"]
    end

    def typed_context : Nil
      nil
    end
  end

  struct Divide
    include Crig::ToolEmbedding(OperationArgs, Int32, Nil)

    def self.init(state, context : Nil) : self
      _ = state
      _ = context
      new
    end

    def name : String
      "divide"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "divide",
        "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios.",
        ArithmeticTool.parameters(
          "The Dividend of the division. The number being divided",
          "The Divisor of the division. The number by which the dividend is being divided",
        ),
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x // args.y
    end

    def embedding_docs : Array(String)
      ["Compute the Quotient of x and y (i.e.: x / y). Useful for ratios."]
    end

    def typed_context : Nil
      nil
    end
  end

  def self.toolset : Crig::ToolSet
    Crig::ToolSet.builder
      .dynamic_tool(Add.new)
      .dynamic_tool(Subtract.new)
      .dynamic_tool(Multiply.new)
      .dynamic_tool(Divide.new)
      .build
  end

  def self.build_index(embedding_model : M) : Crig::InMemoryVectorIndex(M, Crig::Embeddings::ToolSchema) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(embedding_model), Crig::Embeddings::ToolSchema).new(embedding_model)
      .documents(toolset.schemas)
      .build
    Crig::InMemoryVectorStore(Crig::Embeddings::ToolSchema)
      .from_documents_with_id_f(embeddings, &.name)
      .index(embedding_model)
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::Client,
    completion_model : String = Crig::Providers::OpenAI::GPT_4,
    embedding_model_name : String = Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002,
  ) : Crig::Agent(Crig::Providers::OpenAI::ResponsesCompletionModel)
    embedding_model = client.embedding_model(embedding_model_name)
    client.agent(completion_model)
      .preamble(PREAMBLE)
      .dynamic_tools(2, build_index(embedding_model), toolset)
      .build
  end

  def self.build_chatbot(
    agent : Crig::Agent(M),
  ) : Crig::Integrations::ChatBot(Crig::Integrations::AgentImpl(M)) forall M
    Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
      .agent(agent)
      .max_turns(10)
      .build
  end
end
