require "crig"

module Crig::Examples::RagDynamicTools
  struct OperationArgs
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    property x : Int32
    property y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  class MathError < Exception
    def initialize(message = "Math error")
      super(message)
    end
  end

  class InitError < Exception
    def initialize(message = "Init error")
      super(message)
    end
  end

  struct Add
    include Crig::Tool

    def name : String
      "add"
    end

    def description : String
      "Add x and y together"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "add",
        description: "Add x and y together",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The first number to add"
            },
            "y" => {
              "type" => "number",
              "description" => "The second number to add"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      args.x + args.y
    end
  end

  struct Subtract
    include Crig::Tool

    def name : String
      "subtract"
    end

    def description : String
      "Subtract y from x (i.e.: x - y)"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "subtract",
        description: "Subtract y from x (i.e.: x - y)",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The number to subtract from"
            },
            "y" => {
              "type" => "number",
              "description" => "The number to subtract"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      args.x - args.y
    end
  end
# Main execution
if PROGRAM_NAME == __FILE__
  begin
    # Create DeepSeek client for completions
    deepseek_client = Crig::Providers::DeepSeek::Client.from_env

  # Create Ollama client for embeddings (free/local)
  ollama_client = Crig::Providers::Ollama::Client.new("http://localhost:11434")

  # Create tools
  add_tool = Crig::Examples::RagDynamicTools::Add.new
  subtract_tool = Crig::Examples::RagDynamicTools::Subtract.new

  # Create tool schemas for embedding
  tool_schemas = [
    add_tool.definition(""),
    subtract_tool.definition("")
  ]

  # Create embeddings for tool schemas using Ollama (free)
  embedding_model = ollama_client.embedding_model("nomic-embed-text")

  # Create embeddings using the new ergonomic API
  embeddings = Crig::EmbeddingsBuilder
    .new(embedding_model)
    .documents(tool_schemas.map(&.to_json))
    .build

  # Create vector store with the embeddings
  vector_store = Crig::VectorStore::InMemoryVectorStore.from_documents_with_id(
    embeddings,
    ->(tool : Crig::Completion::ToolDefinition) { tool.name }
  )

  # Create vector store index
  index = vector_store.index(embedding_model)

  # Create RAG agent with DeepSeek completions and dynamic tools
  calculator_rag = deepseek_client
    .agent("deepseek-chat")
    .preamble("You are a calculator here to help the user perform arithmetic operations.")
    # Add dynamic tools with the vector index
    .dynamic_tools(1, index, [add_tool, subtract_tool])
    .build

  puts "RAG Dynamic Tools Example"
  puts "Using DeepSeek for completions and Ollama (nomic-embed-text) for embeddings"
  puts

  # Test prompts
  test_prompts = [
    "Calculate 3 + 7",
    "What is 15 - 8?",
    "Add 10 and 20",
    "Subtract 5 from 12"
  ]

  test_prompts.each do |prompt|
    puts "Prompt: #{prompt}"
    begin
      response = calculator_rag.prompt(prompt)
      puts "Response: #{response.response}"
      puts
    rescue ex
      puts "Error: #{ex.message}"
      puts
    end
  end

      puts "Example completed successfully!"
    end
  rescue ex : KeyError
    puts "Error: DEEPSEEK_API_KEY environment variable not set"
    puts "Please set DEEPSEEK_API_KEY to your DeepSeek API key"
    exit 1
  rescue ex : Socket::ConnectError
    puts "Error: Cannot connect to Ollama at http://localhost:11434"
    puts "Please ensure Ollama is running: ollama serve"
    puts "Or install and pull the nomic-embed-text model: ollama pull nomic-embed-text"
    exit 1
  end
end
end
