require "../src/crig"
require "./vector_search"

module Crig::Examples::RagDynamicTools
  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  struct Add
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

  def self.tools : Array(Crig::ToolDyn)
    [Add.new.as(Crig::ToolDyn), Subtract.new.as(Crig::ToolDyn)]
  end

  def self.tool_definitions : Array(Crig::Completion::ToolDefinition)
    tools.map(&.definition(""))
  end

  def self.tool_schemas : Array(Crig::Embeddings::ToolSchema)
    [
      Crig::Embeddings::ToolSchema.new("add", JSON.parse("null"), ["Add x and y together"]),
      Crig::Embeddings::ToolSchema.new("subtract", JSON.parse("null"), ["Subtract y from x (i.e.: x - y)"]),
    ]
  end

  def self.toolset : Crig::ToolSet
    Crig::ToolSet.builder
      .static_tool(Add.new)
      .static_tool(Subtract.new)
      .build
  end

  def self.build_index(embedding_model : M) : Crig::InMemoryVectorIndex(M, Crig::Embeddings::ToolSchema) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(embedding_model), Crig::Embeddings::ToolSchema).new(embedding_model)
      .documents(tool_schemas)
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
    handle = tools.reduce(Crig::ToolServer.new) { |server, tool| server.tool(tool) }.run
    client.agent(completion_model)
      .preamble("You are a calculator here to help the user perform arithmetic operations.")
      .tool_server_handle(handle)
      .dynamic_tools(1, build_index(embedding_model), tool_definitions)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Calculate 3 - 7") : String forall M
    agent.prompt(prompt).send
  end
end
