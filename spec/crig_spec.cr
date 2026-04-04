require "./spec_helper"
require "../examples/agent"
require "../examples/agent_stream_chat"
require "../examples/agent_with_agent_tool"
require "../examples/agent_prompt_chaining"
require "../examples/agent_with_cohere"
require "../examples/agent_with_galadriel"
require "../examples/agent_with_grok"
require "../examples/agent_with_groq"
require "../examples/agent_with_hyperbolic"
require "../examples/agent_with_moonshot"
require "../examples/agent_with_ollama"
require "../examples/agent_with_openrouter"
require "../examples/agent_with_tools"
require "../examples/agent_with_default_max_turns"
require "../examples/agent_with_context"
require "../examples/agent_with_deepseek"
require "../examples/agent_with_together"
require "../examples/agent_with_loaders"
require "../examples/agent_with_mira"
require "../examples/chain"
require "../examples/enum_dispatch"
require "../examples/extractor"
require "../examples/extractor_with_deepseek"
require "../examples/gemini_agent"
require "../examples/gemini_embeddings"
require "../examples/gemini_extractor"
require "../examples/gemini_streaming_with_tools"
require "../examples/gemini_structured_output"
require "../examples/groq_streaming_reasoning"
require "../examples/hyperbolic_image_generation"
require "../examples/huggingface_image_generation"
require "../examples/huggingface_streaming"
require "../examples/image"
require "../examples/loaders"
require "../examples/multi_extract"
require "../examples/multi_turn_agent"
require "../examples/multi_turn_agent_extended"
require "../examples/anthropic_plaintext_document"
require "../examples/openai_image_generation"
require "../examples/rag"
require "../examples/rmcp"
require "../examples/simple_model"
require "../examples/anthropic_agent"
require "../examples/anthropic_structured_output"
require "../examples/anthropic_streaming"
require "../examples/anthropic_streaming_with_tools"
require "../examples/anthropic_think_tool"
require "../examples/anthropic_think_tool_with_other_tools"
require "../examples/cohere_streaming"
require "../examples/cohere_streaming_with_tools"
require "../examples/deepseek_streaming"
require "../examples/gemini_streaming"
require "../examples/vector_search"
require "../examples/ollama_streaming"
require "../examples/ollama_structured_output"
require "../examples/openai_audio_generation"
require "../examples/openai_structured_output"
require "../examples/openai_streaming"

def run_crig_probe(source : String) : JSON::Any
  probe_id = "#{Process.pid}_#{Time.utc.to_unix_ms}_#{Random.rand(1_000_000)}"
  source_path = nil.as(String?)
  binary_path = nil.as(String?)
  cache_dir = "#{Dir.current}/.crystal-cache"
  Dir.mkdir_p(cache_dir)
  env = {"CRYSTAL_CACHE_DIR" => cache_dir}

  source_path = "#{Dir.current}/.crig_probe_#{probe_id}.cr"
  binary_path = "#{cache_dir}/crig_probe_#{probe_id}"
  File.write(source_path, source)

  build_output = IO::Memory.new
  build_error = IO::Memory.new
  build_status = Process.run(
    "crystal",
    ["build", source_path, "-o", binary_path],
    chdir: Dir.current,
    env: env,
    output: build_output,
    error: build_error,
  )
  unless build_status.success?
    stderr = build_error.to_s
    stdout = build_output.to_s
    raise "crig probe build failed: #{stderr.empty? ? stdout : stderr}"
  end

  run_output = IO::Memory.new
  run_error = IO::Memory.new
  run_status = Process.run(
    binary_path,
    chdir: Dir.current,
    env: env,
    output: run_output,
    error: run_error,
  )

  return JSON.parse(run_output.to_s) if run_status.success?

  stderr = run_error.to_s
  stdout = run_output.to_s
  raise "crig probe failed: #{stderr.empty? ? stdout : stderr}"
ensure
  if path = source_path
    File.delete(path) if File.exists?(path)
  end
  if path = binary_path
    File.delete(path) if File.exists?(path)
  end
end

struct ExampleEmbedding
  include Crig::Embeddings::Embed

  def initialize(@parts : Array(String))
  end

  def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
    @parts.each { |part| embedder.embed(part) }
  end
end

struct ExampleMultiEmbedding
  include Crig::Embeddings::Embed

  getter id : String

  def initialize(@id : String, @parts : Array(String))
  end

  def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
    @parts.each { |part| embedder.embed(part) }
  end
end

struct FailingExampleEmbedding
  include Crig::Embeddings::Embed

  def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
    _ = embedder
    raise "embed exploded"
  end
end

struct DerivedDefinition
  include JSON::Serializable

  getter word : String
  getter link : String
  getter speech : String

  def initialize(@word : String, @link : String, @speech : String)
  end
end

def custom_embedding_function(embedder : Crig::Embeddings::TextEmbedder, definition : DerivedDefinition) : Nil
  embedder.embed(definition.to_json)
end

struct DerivedWordDefinitionCustom
  @id : String
  @word : String
  @definition : DerivedDefinition

  def initialize(@id : String, @word : String, @definition : DerivedDefinition)
  end

  @[Crig::Embeddings::EmbedField(embed_with: custom_embedding_function)]
  def definition : DerivedDefinition
    @definition
  end

  Crig::Embeddings.derive_embed({{@type}})
end

struct DerivedWordDefinitionCustomAndBasic
  @id : String
  @word : String
  @definition : DerivedDefinition

  def initialize(@id : String, @word : String, @definition : DerivedDefinition)
  end

  @[Crig::Embeddings::EmbedField]
  def word : String
    @word
  end

  @[Crig::Embeddings::EmbedField(embed_with: custom_embedding_function)]
  def definition : DerivedDefinition
    @definition
  end

  Crig::Embeddings.derive_embed({{@type}})
end

struct DerivedWordDefinitionSingle
  @id : String
  @word : String
  @definition : String

  def initialize(@id : String, @word : String, @definition : String)
  end

  @[Crig::Embeddings::EmbedField]
  def definition : String
    @definition
  end

  Crig::Embeddings.derive_embed({{@type}})
end

struct DerivedCompanyAges
  @id : String
  @company : String
  @employee_ages : Array(Int32)

  def initialize(@id : String, @company : String, @employee_ages : Array(Int32))
  end

  @[Crig::Embeddings::EmbedField]
  def employee_ages : Array(Int32)
    @employee_ages
  end

  Crig::Embeddings.derive_embed({{@type}})
end

struct DerivedCompanyNames
  @id : String
  @company : String
  @employee_names : Array(String)

  def initialize(@id : String, @company : String, @employee_names : Array(String))
  end

  @[Crig::Embeddings::EmbedField]
  def employee_names : Array(String)
    @employee_names
  end

  Crig::Embeddings.derive_embed({{@type}})
end

struct DummyOneOrManyString
  getter string : String

  def initialize(@string : String)
  end

  def ==(other : self) : Bool
    @string == other.string
  end

  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .string?
      new(pull.read_string)
    when .begin_object?
      string = nil
      pull.read_begin_object
      until pull.kind.end_object?
        key = pull.read_object_key
        if key == "string"
          string = pull.read_string
        else
          pull.skip
        end
      end
      pull.read_end_object
      new(string || "")
    else
      raise "unexpected DummyOneOrManyString payload"
    end
  end

  def to_json(json : JSON::Builder) : Nil
    json.object do
      json.field "string", @string
    end
  end
end

struct DummyOneOrManyStruct
  include JSON::Serializable

  @[JSON::Field(converter: Crig::StringOrOneOrManyConverter(DummyOneOrManyString))]
  getter field : Crig::OneOrMany(DummyOneOrManyString)

  def initialize(@field : Crig::OneOrMany(DummyOneOrManyString))
  end
end

struct DummyOneOrManyStructOption
  include JSON::Serializable

  @[JSON::Field(converter: Crig::StringOrOptionOneOrManyConverter(DummyOneOrManyString))]
  getter field : Crig::OneOrMany(DummyOneOrManyString)?

  def initialize(@field : Crig::OneOrMany(DummyOneOrManyString)?)
  end
end

struct DummyOneOrManyMessage
  include JSON::Serializable

  getter role : String
  @[JSON::Field(converter: Crig::StringOrOptionOneOrManyConverter(DummyOneOrManyString))]
  getter content : Crig::OneOrMany(DummyOneOrManyString)?

  def initialize(@role : String, @content : Crig::OneOrMany(DummyOneOrManyString)?)
  end
end

class MutableOneOrManyValue
  property value : String

  def initialize(@value : String)
  end
end

class FakeTelemetryRequest
  include Crig::ProviderRequestExt(String)

  def input_messages : Array(String)
    ["user:hello"]
  end

  def system_prompt : String?
    "You are concise."
  end

  def model_name : String
    "fake-model"
  end

  def prompt : String?
    "hello"
  end
end

class FakeTelemetryResponse
  include Crig::ProviderResponseExt(String, Crig::Completion::Usage)
  include Crig::Completion::GetTokenUsage

  def response_id : String?
    "resp_123"
  end

  def response_model_name : String?
    "fake-model"
  end

  def output_messages : Array(String)
    ["assistant:hi"]
  end

  def text_response : String?
    "hi"
  end

  def usage : Crig::Completion::Usage?
    Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2)
  end

  def token_usage : Crig::Completion::Usage?
    usage
  end
end

class FakeSpanCombinator
  include Crig::SpanCombinator

  getter events : Array(String)

  def initialize
    @events = [] of String
  end

  def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
    token_usage = usage.token_usage
    @events << "usage:#{token_usage.try(&.input_tokens)}:#{token_usage.try(&.output_tokens)}"
  end

  def record_response_metadata(response) : Nil
    @events << "response:#{response.get_response_id}:#{response.get_response_model_name}"
  end

  def record_model_input(messages) : Nil
    @events << "input:#{messages.to_json}"
  end

  def record_model_output(messages) : Nil
    @events << "output:#{messages.to_json}"
  end
end

struct DerivedCompanyMultiple
  @id : String
  @company : String
  @employee_ages : Array(Int32)

  def initialize(@id : String, @company : String, @employee_ages : Array(Int32))
  end

  @[Crig::Embeddings::EmbedField]
  def company : String
    @company
  end

  @[Crig::Embeddings::EmbedField]
  def employee_ages : Array(Int32)
    @employee_ages
  end

  Crig::Embeddings.derive_embed({{@type}})
end

class FakeEmbeddingModel
  include Crig::Embeddings::EmbeddingModel

  def max_documents : Int32
    2
  end

  def ndims : Int32
    3
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    texts.map do |text|
      Crig::Embeddings::Embedding.new(text, [text.bytesize.to_f64, 0.0, 1.0])
    end.to_a
  end
end

class FailingEmbeddingModel
  include Crig::Embeddings::EmbeddingModel

  def max_documents : Int32
    2
  end

  def ndims : Int32
    3
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    raise Crig::Embeddings::EmbeddingError.new("embedding provider unavailable for #{texts.first}")
  end
end

class FakeImageEmbeddingModel
  include Crig::Embeddings::ImageEmbeddingModel

  def max_documents : Int32
    2
  end

  def ndims : Int32
    2
  end

  def embed_images(images : Enumerable(Bytes)) : Array(Crig::Embeddings::Embedding)
    images.map do |image|
      Crig::Embeddings::Embedding.new("image:#{image.size}", [image.size.to_f64, 1.0])
    end.to_a
  end
end

class FakeToolEmbedding
  include Crig::ToolEmbeddingDyn

  def name : String
    "nothing"
  end

  def context : JSON::Any
    JSON.parse(%({"category":"utility"}))
  end

  def embedding_docs : Array(String)
    ["Do nothing."]
  end
end

struct EchoArgs
  include JSON::Serializable

  getter value : String

  def initialize(@value : String)
  end
end

struct EchoTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "echo",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    args.value
  end
end

Crig.rig_tool(
  description: "Perform basic arithmetic operations",
  params: {
    x:         "First number in the calculation",
    y:         "Second number in the calculation",
    operation: "The operation to perform (add, subtract, multiply, divide)",
  },
  required: [:x, :y, :operation]
) do
  def calculator(x : Int32, y : Int32, operation : String) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    case operation
    when "add"
      Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x + y)
    when "subtract"
      Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x - y)
    when "multiply"
      Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x * y)
    when "divide"
      if y == 0
        Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Division by zero"))
      else
        Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x // y)
      end
    else
      Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Unknown operation: #{operation}"))
    end
  end
end

Crig.rig_tool(
  description: "Perform basic arithmetic operations",
  params: {
    x:         "First number in the calculation",
    y:         "Second number in the calculation",
    operation: "The operation to perform (add, subtract, multiply, divide)",
  }
) do
  def sync_calculator(x : Int32, y : Int32, operation : String) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    calculator(x, y, operation)
  end
end

Crig.rig_tool do
  def count_rs(s : String) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(s.chars.count { |ch| ch == 'r' || ch == 'R' }.to_i)
  end
end

struct DefaultNamedTool
  include Crig::Tool(EchoArgs, String)

  NAME = "default-named"

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "default-named",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    args.value
  end
end

struct FailingEchoTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "echo",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    raise "boom"
  end
end

struct RecursiveFailingTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "echo",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    raise "ToolCallError: already wrapped"
  end
end

struct EmbeddedEchoContext
  include JSON::Serializable

  getter category : String

  def initialize(@category : String)
  end
end

struct EmbeddedEchoTool
  include Crig::ToolEmbedding(EchoArgs, String, EmbeddedEchoContext)

  def name : String
    "embedded-echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "embedded-echo",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    args.value
  end

  def embedding_docs : Array(String)
    ["Echo values back to the caller."]
  end

  def typed_context : EmbeddedEchoContext
    EmbeddedEchoContext.new("utility")
  end
end

struct StatefulEmbeddedEchoTool
  include Crig::ToolEmbedding(EchoArgs, String, EmbeddedEchoContext)

  getter state_value : String
  getter stored_context : EmbeddedEchoContext

  def initialize(@state_value : String, @stored_context : EmbeddedEchoContext)
  end

  def self.init(state : String, context : EmbeddedEchoContext) : self
    new(state, context)
  end

  def name : String
    "stateful-embedded-echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    _ = prompt
    Crig::Completion::ToolDefinition.new(
      "stateful-embedded-echo",
      "Echo the given value with runtime state",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : EchoArgs) : String
    "#{@state_value}:#{@stored_context.category}:#{args.value}"
  end

  def embedding_docs : Array(String)
    ["#{@state_value}:#{@stored_context.category}"]
  end

  def typed_context : EmbeddedEchoContext
    @stored_context
  end
end

struct EmptyToolArgs
  include JSON::Serializable
end

struct SleeperTool
  include Crig::Tool(EmptyToolArgs, Int32)

  NAME = "sleeper"

  def initialize(@sleep_duration_ms : Int32)
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "sleeper",
      "Sleeps for the configured duration",
      JSON.parse(%({"type":"object","properties":{}}))
    )
  end

  def call_typed(args : EmptyToolArgs) : Int32
    sleep(@sleep_duration_ms.milliseconds)
    @sleep_duration_ms
  end
end

class MockToolIndex
  def initialize(@tool_ids : Array(String))
  end

  def top_n_ids(request : Crig::VectorSearchRequest) : Array(Tuple(Float64, String))
    @tool_ids.each_with_index.map do |id, index|
      {1.0 - (index.to_f64 * 0.1), id}
    end.to_a
  end
end

class ReconnectingSseClient
  include Crig::HttpClient::HttpClientExt

  getter sent_requests = [] of HTTP::Request

  def initialize
    @stream_calls = 0
  end

  def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new(1)
    channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(Bytes.empty))
    channel.close
    Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error).ok(
      Crig::HttpClient::Response.new(Crig::HttpClient::LazyBody(Bytes).new(channel))
    )
  end

  def send_multipart(
    req : HTTP::Request,
    form : Crig::HttpClient::MultipartForm,
  ) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    send(req)
  end

  def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error)
    @sent_requests << req
    @stream_calls += 1
    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new

    spawn do
      if @stream_calls == 1
        channel.send(
          Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(
            "id: evt-1\nevent: update\ndata: first\n\n".to_slice
          )
        )
        channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).err(Crig::HttpClient::Error.stream_ended))
      else
        channel.send(
          Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(
            "data: recovered\n\n".to_slice
          )
        )
      end
      channel.close
    end

    Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error).ok(
      Crig::HttpClient::StreamingResponse.new(channel: channel)
    )
  end
end

class InvalidUtf8SseClient
  include Crig::HttpClient::HttpClientExt

  def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new(1)
    channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(Bytes.empty))
    channel.close
    Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error).ok(
      Crig::HttpClient::Response.new(Crig::HttpClient::LazyBody(Bytes).new(channel))
    )
  end

  def send_multipart(
    req : HTTP::Request,
    form : Crig::HttpClient::MultipartForm,
  ) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    send(req)
  end

  def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error)
    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new

    spawn do
      channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(Bytes[0xFF]))
      channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok("data: recovered\n\n".to_slice))
      channel.close
    end

    Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error).ok(
      Crig::HttpClient::StreamingResponse.new(channel: channel)
    )
  end
end

class FailingConnectSseClient
  include Crig::HttpClient::HttpClientExt

  getter sent_requests = [] of HTTP::Request

  def initialize
    @stream_calls = 0
  end

  def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new(1)
    channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok(Bytes.empty))
    channel.close
    Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error).ok(
      Crig::HttpClient::Response.new(Crig::HttpClient::LazyBody(Bytes).new(channel))
    )
  end

  def send_multipart(
    req : HTTP::Request,
    form : Crig::HttpClient::MultipartForm,
  ) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
    send(req)
  end

  def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error)
    @sent_requests << req
    @stream_calls += 1
    if @stream_calls == 1
      return Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error).err(
        Crig::HttpClient::Error.stream_ended
      )
    end

    channel = Channel(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error)).new
    spawn do
      channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok("data: connected\n\n".to_slice))
      channel.close
    end

    Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error).ok(
      Crig::HttpClient::StreamingResponse.new(channel: channel)
    )
  end
end

def build_mcp_test_client_and_server : {MCP::Client::Client, MCP::Server::Server}
  server_options = MCP::Server::ServerOptions.new(MCP::Server::ServerCapabilities.new.with_tools)
  server = MCP::Server::Server.new(
    MCP::Protocol::Implementation.new(name: "test-server", version: "1.0"),
    server_options
  )

  client = MCP::Client::Client.new(
    client_info: MCP::Protocol::Implementation.new("test-client", "1.0"),
    client_options: MCP::Client::ClientOptions.new(
      capabilities: MCP::Protocol::ClientCapabilities.new
    )
  )

  client_transport, server_transport = MCP::Shared::InMemoryTransport.create_linked_pair
  client_ready = Channel(Nil).new(1)
  server_ready = Channel(Nil).new(1)

  spawn do
    client.connect(client_transport)
    client_ready.send(nil)
  end

  spawn do
    server.connect(server_transport)
    server_ready.send(nil)
  end

  client_ready.receive
  server_ready.receive

  {client, server}
end

class FakeCompletionModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("ok")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    ["streamed"]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeStructuredCompletionModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    submit_tool = request.tools.find { |tool| tool.name == "submit" }
    choice = if submit_tool
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "tool_call_submit",
                   "submit",
                   JSON.parse(%({"city":"Denver","temperature":72})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text(%({"city":"Denver","temperature":72}))
               )
             end

    Crig::Completion::CompletionResponse(String).new(
      choice,
      Crig::Completion::Usage.new(output_tokens: 4),
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    ["streamed"]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeChatIntegration
  include Crig::Completion::Chat

  getter seen : Array({String, Array(Crig::Completion::Message)})

  def initialize(&@response_builder : String, Array(Crig::Completion::Message) -> String)
    @seen = [] of {String, Array(Crig::Completion::Message)}
  end

  def initialize
    @seen = [] of {String, Array(Crig::Completion::Message)}
    @response_builder = ->(text : String, _history : Array(Crig::Completion::Message)) { "chat: #{text}" }
  end

  def chat(prompt : Crig::Completion::Message | String, chat_history : Array(Crig::Completion::Message)) : String
    text = prompt.is_a?(String) ? prompt : prompt.rag_text || ""
    @seen << {text, chat_history.dup}
    @response_builder.call(text, chat_history)
  end
end

class FakeCliChatbotCompletionModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def initialize(
    @completion_text : String = "unused",
    @stream_chunks : Array(String) = ["agent", " reply"],
    @usage : Crig::Completion::Usage = Crig::Completion::Usage.new(
      input_tokens: 3,
      output_tokens: 2,
      total_tokens: 5
    ),
  )
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text(@completion_text)
      ),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    raw_choices = @stream_chunks.map do |chunk|
      Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(chunk)
    end
    raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
      Crig::Client::FinalCompletionResponse.new(@usage)
    )

    Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FixedJSONCompletionModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def initialize(@json : String, @usage : Crig::Completion::Usage = Crig::Completion::Usage.new)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    submit_tool = request.tools.find { |tool| tool.name == "submit" }
    choice = if submit_tool
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "tool_call_submit",
                   "submit",
                   JSON.parse(@json),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text(@json)
               )
             end

    Crig::Completion::CompletionResponse(String).new(
      choice,
      @usage,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    ["streamed"]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class MetricFixedJSONCompletionModel
  include Crig::Completion::CompletionModel

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def initialize(@json : String, @usage : Crig::Completion::Usage = Crig::Completion::Usage.new)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    submit_tool = request.tools.find { |tool| tool.name == "submit" }
    choice = if submit_tool
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "tool_call_submit",
                   "submit",
                   JSON.parse(@json),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text(@json)
               )
             end

    Crig::Completion::CompletionResponse(String).new(
      choice,
      @usage,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    ["streamed"]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class PipelineMockModel
  include Crig::Completion::Prompt

  def prompt(prompt : Crig::Completion::Message | String) : String
    text = prompt.is_a?(String) ? prompt : (prompt.rag_text || prompt.role)
    "Mock response: #{text}"
  end
end

class PipelineMockIndex
  def top_n(request : Crig::VectorSearchRequest, type : T.class) : Array(Tuple(Float64, String, T)) forall T
    _ = request
    [{1.0, "doc1", T.from_json(%({"foo":"bar"}))}]
  end
end

struct PipelineFoo
  include JSON::Serializable

  getter foo : String

  def initialize(@foo : String)
  end
end

struct DummyJudgment
  include JSON::Serializable
  include Crig::Judgment

  getter verdict : Bool
  getter explanation : String

  def initialize(@verdict : Bool, @explanation : String)
  end

  def passes : Bool
    @verdict
  end
end

struct MetricDummyJudgment
  include JSON::Serializable
  include Crig::Judgment

  getter verdict : Bool
  getter explanation : String

  def initialize(@verdict : Bool, @explanation : String)
  end

  def passes : Bool
    @verdict
  end
end

class RecordingPromptHook < Crig::PromptHook
  getter events : Array(String)

  def initialize(@terminate_on_call : Bool = false, @terminate_on_response : Bool = false)
    @events = [] of String
  end

  def on_completion_call(
    prompt : Crig::Completion::Message,
    history : Array(Crig::Completion::Message),
  ) : Crig::HookAction
    @events << "call:#{prompt.rag_text || prompt.role}"
    return Crig::HookAction.terminate("stop-before-send") if @terminate_on_call
    Crig::HookAction.cont
  end

  def on_completion_response(
    prompt : Crig::Completion::Message,
    response,
  ) : Crig::HookAction
    @events << "response:#{response.raw_response}"
    return Crig::HookAction.terminate("stop-after-send") if @terminate_on_response
    Crig::HookAction.cont
  end
end

class RecordingStreamingPromptHook < Crig::PromptHook
  getter events : Array(String)

  def initialize
    @events = [] of String
  end

  def on_tool_call_delta(
    tool_call_id : String,
    internal_call_id : String,
    tool_name : String?,
    tool_call_delta : String,
  ) : Crig::HookAction
    @events << "tool-call-delta:#{tool_call_id}:#{internal_call_id}:#{tool_name}:#{tool_call_delta}"
    Crig::HookAction.cont
  end
end

class TerminatingTextDeltaHook < Crig::PromptHook
  def on_text_delta(text_delta : String, aggregated_text : String) : Crig::HookAction
    Crig::HookAction.terminate("stop-now")
  end
end

class TerminatingToolCallHook < Crig::PromptHook
  def on_tool_call(
    tool_name : String,
    tool_call_id : String?,
    internal_call_id : String,
    args : String,
  ) : Crig::ToolCallHookAction
    Crig::ToolCallHookAction.terminate("stop-tool-call")
  end
end

class SkippingToolCallHook < Crig::PromptHook
  def on_tool_call(
    tool_name : String,
    tool_call_id : String?,
    internal_call_id : String,
    args : String,
  ) : Crig::ToolCallHookAction
    Crig::ToolCallHookAction.skip("tool skipped")
  end
end

class TerminatingToolResultHook < Crig::PromptHook
  def on_tool_result(
    tool_name : String,
    tool_call_id : String?,
    internal_call_id : String,
    args : String,
    result : String,
  ) : Crig::HookAction
    Crig::HookAction.terminate("stop-tool-result")
  end
end

class FakeMultiToolPromptModel
  include Crig::Completion::CompletionModel

  getter turn_counter = 0

  def completion(request : Crig::Completion::Request::CompletionRequest)
    turn = @turn_counter
    @turn_counter += 1

    choice = if turn == 0
               Crig::OneOrMany(Crig::Completion::AssistantContent).many([
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_1",
                   "call_1",
                   "missing_tool",
                   JSON.parse(%({"input":"one"})),
                 ),
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_2",
                   "call_2",
                   "missing_tool",
                   JSON.parse(%({"input":"two"})),
                 ),
               ])
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("done")
               )
             end

    usage = turn == 0 ? Crig::Completion::Usage.new(total_tokens: 4) : Crig::Completion::Usage.new(total_tokens: 6)
    Crig::Completion::CompletionResponse(String).new(
      choice,
      usage,
      "raw-prompt",
      turn == 0 ? "msg-tool" : "msg-final",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["unused"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 1)),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class TerminatingToolCallDeltaHook < Crig::PromptHook
  def on_tool_call_delta(
    tool_call_id : String,
    internal_call_id : String,
    tool_name : String?,
    tool_call_delta : String,
  ) : Crig::HookAction
    Crig::HookAction.terminate("stop-tool-call-delta")
  end
end

class TerminatingStreamFinishHook < Crig::PromptHook
  def on_stream_completion_response_finish(
    prompt : Crig::Completion::Message,
    response,
  ) : Crig::HookAction
    Crig::HookAction.terminate("stop-stream-finish")
  end
end

class FakeCompletionClientModel
  include Crig::Completion::CompletionModel
  include Crig::Completion::CompletionModelDyn

  getter name : String
  getter last_request : Crig::Completion::Request::CompletionRequest?

  def initialize(@name : String)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("completion:#{@name}")),
      Crig::Completion::Usage.new(output_tokens: 1),
      "raw:#{@name}",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["chunk:#{@name}"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3)),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class EnumDispatchOpenAIModel
  include Crig::Completion::CompletionModel

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("Helpful")
      ),
      Crig::Completion::Usage.new,
      "raw:openai",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      [] of String,
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class EnumDispatchAnthropicModel
  include Crig::Completion::CompletionModel

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("Unhelpful")
      ),
      Crig::Completion::Usage.new,
      "raw:anthropic",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      [] of String,
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeStreamingAgentModel
  include Crig::Completion::CompletionModel

  enum Mode
    Reasoning
    ToolCall
  end

  getter last_request : Crig::Completion::Request::CompletionRequest?

  def initialize(@mode : Mode)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("unused")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    choice = case @mode
             in .reasoning?
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.new(
                   Crig::Completion::AssistantContent::Kind::Reasoning,
                   reasoning: Crig::Completion::Reasoning.new(
                     [Crig::Completion::ReasoningContent.summary("step one")],
                     "r1",
                   ),
                 )
               )
             in .tool_call?
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool-1",
                   "call_1",
                   "weather",
                   JSON.parse(%({"city":"Denver"})),
                 )
               )
             end

    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).new(
      [] of String,
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 1)),
      choice: choice,
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeMultiTurnStreamingModel
  include Crig::Completion::CompletionModel

  getter turn_counter = 0

  def initialize(@tool_call_turns : Int32)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("unused")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    turn = @turn_counter
    @turn_counter += 1

    choice = if turn < @tool_call_turns
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_1",
                   "call_1",
                   "missing_tool",
                   JSON.parse(%({"input":"value"})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("done")
               )
             end

    usage = turn < @tool_call_turns ? Crig::Completion::Usage.new(total_tokens: 4) : Crig::Completion::Usage.new(total_tokens: 6)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).new(
      turn < @tool_call_turns ? [] of String : ["done"],
      Crig::FinalCompletionResponse.new(usage),
      choice: choice,
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeMultiTurnPromptModel
  include Crig::Completion::CompletionModel

  getter turn_counter = 0

  def initialize(@tool_call_turns : Int32)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    turn = @turn_counter
    @turn_counter += 1

    choice = if turn < @tool_call_turns
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_1",
                   "call_1",
                   "missing_tool",
                   JSON.parse(%({"input":"value"})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("done")
               )
             end

    usage = turn < @tool_call_turns ? Crig::Completion::Usage.new(total_tokens: 4) : Crig::Completion::Usage.new(total_tokens: 6)
    Crig::Completion::CompletionResponse(String).new(
      choice,
      usage,
      "raw-prompt",
      turn < @tool_call_turns ? "msg-tool-#{turn}" : "msg-final-#{turn}",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["unused"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 1)),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeDeltaStreamingModel
  include Crig::Completion::CompletionModel

  enum Mode
    ReasoningDelta
    ReasoningDeltaAndToolCall
    ToolCallDeltaAndToolCall
  end

  getter turn_counter = 0

  def initialize(@mode : Mode)
  end

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("unused")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    turn = @turn_counter
    @turn_counter += 1
    raw_choices = case @mode
                  in .reasoning_delta?
                    [
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 2))
                      ),
                    ]
                  in .reasoning_delta_and_tool_call?
                    if turn == 0
                      [
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call(
                          Crig::RawStreamingToolCall.new(
                            "tool_call_1",
                            "missing_tool",
                            JSON.parse(%({"input":"value"})),
                          ).with_internal_call_id("internal_1").with_call_id("call_1")
                        ),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                          Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3))
                        ),
                      ]
                    else
                      [
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("done"),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                          Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))
                        ),
                      ]
                    end
                  in .tool_call_delta_and_tool_call?
                    if turn == 0
                      [
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call_delta(
                          "tool_call_1",
                          "internal_1",
                          Crig::ToolCallDeltaContent.name("missing_tool")
                        ),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call_delta(
                          "tool_call_1",
                          "internal_1",
                          Crig::ToolCallDeltaContent.delta("{\"input\":\"value\"}")
                        ),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call(
                          Crig::RawStreamingToolCall.new(
                            "tool_call_1",
                            "missing_tool",
                            JSON.parse(%({"input":"value"})),
                          ).with_internal_call_id("internal_1").with_call_id("call_1")
                        ),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                          Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3))
                        ),
                      ]
                    else
                      [
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("done"),
                        Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                          Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))
                        ),
                      ]
                    end
                  end

    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices(raw_choices)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeImageGenerationModel
  include Crig::ImageGenerationModel

  getter last_request : Crig::ImageGenerationRequest?

  def image_generation(request : Crig::ImageGenerationRequest)
    @last_request = request
    Crig::ImageGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-image")
  end

  def image_generation_request : Crig::ImageGenerationRequestBuilder
    Crig::ImageGenerationRequestBuilder.new(self)
  end
end

class FakeAudioGenerationModel
  include Crig::AudioGenerationModel

  getter last_request : Crig::AudioGenerationRequest?

  def audio_generation(request : Crig::AudioGenerationRequest)
    @last_request = request
    Crig::AudioGenerationResponse(String).new(Bytes[4_u8, 5_u8], "raw-audio")
  end

  def audio_generation_request : Crig::AudioGenerationRequestBuilder
    Crig::AudioGenerationRequestBuilder.new(self)
  end
end

class FakeTranscriptionModel
  include Crig::TranscriptionModel

  getter last_request : Crig::TranscriptionRequest?

  def transcription(request : Crig::TranscriptionRequest)
    @last_request = request
    Crig::TranscriptionResponse(String).new("hello world", "raw-transcription")
  end

  def transcription_request : Crig::TranscriptionRequestBuilder
    Crig::TranscriptionRequestBuilder.new(self)
  end
end

class FailingTranscriptionModel
  include Crig::TranscriptionModel

  def transcription(request : Crig::TranscriptionRequest)
    raise Crig::TranscriptionError.new("provider unavailable for #{request.filename}")
  end

  def transcription_request : Crig::TranscriptionRequestBuilder
    Crig::TranscriptionRequestBuilder.new(self)
  end
end

class FakeWasmCompat
  include Crig::WasmCompatSend
  include Crig::WasmCompatSync
  include Crig::WasmCompatSendStream
end

class SuccessfulVerifyClient
  include Crig::VerifyClient
  include Crig::VerifyClientDyn

  getter? verified = false

  def verify : Nil
    @verified = true
  end
end

class FailingVerifyClient
  include Crig::VerifyClient

  def verify : Nil
    raise Crig::VerifyError.provider_error("boom")
  end
end

class FakeEmbeddingsClientModel
  include Crig::EmbeddingModel
  include Crig::EmbeddingModelDyn

  getter name : String
  getter dims : Int32

  def initialize(@name : String, @dims : Int32)
  end

  def max_documents : Int32
    2
  end

  def ndims : Int32
    @dims
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    texts.map { |text| Crig::Embeddings::Embedding.new("#{name}:#{text}", [dims.to_f64]) }.to_a
  end

  def embed_text(text : String) : Crig::Embeddings::Embedding
    Crig::Embeddings::Embedding.new("#{name}:#{text}", [dims.to_f64])
  end

  def embed_texts(texts : Array(String)) : Array(Crig::Embeddings::Embedding)
    texts.map { |text| Crig::Embeddings::Embedding.new("#{name}:#{text}", [dims.to_f64]) }
  end
end

class FakeEmbeddingsClient
  include Crig::EmbeddingsClient(FakeEmbeddingsClientModel)
  include Crig::EmbeddingsClientDyn

  def embedding_model(model : String) : FakeEmbeddingsClientModel
    FakeEmbeddingsClientModel.new(model, 0)
  end

  def embedding_model_with_ndims(model : String, ndims : Int32) : FakeEmbeddingsClientModel
    FakeEmbeddingsClientModel.new(model, ndims)
  end
end

class FakeCompletionClient
  include Crig::CompletionClient(FakeCompletionClientModel)
  include Crig::CompletionClientDyn

  def completion_model(model : String) : FakeCompletionClientModel
    FakeCompletionClientModel.new(model)
  end
end

class FakeRmcpExampleCompletionModel
  include Crig::Completion::CompletionModel

  getter turns = 0

  def completion(request : Crig::Completion::Request::CompletionRequest)
    turn = @turns
    @turns += 1

    choice = if turn == 0
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_1",
                   "call_1",
                   "sum",
                   JSON.parse(%({"a":2,"b":5})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("7")
               )
             end

    Crig::Completion::CompletionResponse(String).new(
      choice,
      Crig::Completion::Usage.new(total_tokens: turn == 0 ? 4 : 6),
      "raw-rmcp-example",
      turn == 0 ? "msg-tool" : "msg-final",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["unused"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 1)),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end

  def completion_request(prompt : Crig::Completion::Message) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeRmcpExampleCompletionClient
  include Crig::CompletionClient(FakeRmcpExampleCompletionModel)

  def completion_model(model : String) : FakeRmcpExampleCompletionModel
    FakeRmcpExampleCompletionModel.new
  end
end

class FakeOpenAIChatServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      valid_path = {"/v1/chat/completions", "/chat/completions", "/v1/responses"}.includes?(context.request.path)
      unless context.request.method == "POST" && valid_path
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenAIEmbeddingServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/v1/embeddings"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeGeminiGenerateContentServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      valid_path = context.request.method == "POST" &&
                   context.request.path.ends_with?(":generateContent")
      unless valid_path
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenRouterChatServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/api/v1/chat/completions"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenRouterEmbeddingServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/api/v1/embeddings"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenAIImageGenerationServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/v1/images/generations"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenAITranscriptionServer
  getter parts : Array(NamedTuple(name: String, body: String, filename: String?))

  def initialize(&@handler : Array(NamedTuple(name: String, body: String, filename: String?)) -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @parts = [] of NamedTuple(name: String, body: String, filename: String?)
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/v1/audio/transcriptions"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      request_parts = [] of NamedTuple(name: String, body: String, filename: String?)
      HTTP::FormData.parse(context.request) do |part|
        request_parts << {
          name:     part.name || "",
          body:     part.body.gets_to_end,
          filename: part.filename,
        }
      end
      @parts.concat(request_parts)

      response = @handler.call(request_parts)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeOpenAIAudioGenerationServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/v1/audio/speech"
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload

      response = @handler.call(payload)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeAzureJsonServer
  getter requests : Array(JSON::Any)
  getter headers : Array(HTTP::Headers)

  def initialize(@path : String, &@handler : JSON::Any -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @requests = [] of JSON::Any
    @headers = [] of HTTP::Headers
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.resource == @path
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      body = context.request.body.try(&.gets_to_end) || ""
      payload = JSON.parse(body)
      @requests << payload
      @headers << context.request.headers.dup

      response = @handler.call(payload)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeAzureMultipartServer
  getter parts : Array(NamedTuple(name: String, body: String, filename: String?))
  getter headers : Array(HTTP::Headers)

  def initialize(@path : String, &@handler : Array(NamedTuple(name: String, body: String, filename: String?)) -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @parts = [] of NamedTuple(name: String, body: String, filename: String?)
    @headers = [] of HTTP::Headers
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.resource == @path
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
        next
      end

      request_parts = [] of NamedTuple(name: String, body: String, filename: String?)
      HTTP::FormData.parse(context.request) do |part|
        request_parts << {
          name:     part.name || "",
          body:     part.body.gets_to_end,
          filename: part.filename,
        }
      end
      @parts.concat(request_parts)
      @headers << context.request.headers.dup

      response = @handler.call(request_parts)
      context.response.status_code = response[:status_code] || HTTP::Status::OK.code
      context.response.content_type = response[:content_type]
      context.response.print(response[:body])
    end
  end
end

class FakeProviderClient
  include Crig::ProviderClient(String)

  getter source : String

  def initialize(@source : String)
  end

  def self.from_env : self
    new("env")
  end

  def self.from_val(input : String) : self
    new(input)
  end
end

class DefaultDebugExtExample
  include Crig::DebugExt
end

class FakeProviderExtension
  include Crig::Provider(Symbol)

  def verify_path : String
    "/verify"
  end

  def builder_type : Symbol.class
    Symbol
  end

  def build_uri(base_url : String, path : String, transport : Crig::Client::Transport) : String
    trimmed = path.lstrip('/')
    return trimmed if base_url.empty?
    "#{base_url.rstrip('/')}/#{trimmed}"
  end

  def with_custom(request : Crig::Client::RequestBuilder) : Crig::Client::RequestBuilder
    request.body("customized")
  end
end

class FakeCapabilities
  include Crig::Capabilities

  def completion_capability : Bool
    true
  end

  def embeddings_capability : Bool
    false
  end

  def transcription_capability : Bool
    true
  end

  def model_listing_capability : Bool
    false
  end

  def image_generation_capability : Bool
    false
  end

  def audio_generation_capability : Bool
    false
  end
end

class FakeProviderBuilder
  include Crig::ProviderBuilder(FakeProviderExtension, Crig::BearerAuth)

  getter base_url : String

  def initialize(@base_url : String = "https://api.example.com")
  end

  def build(builder : Crig::Client::ClientBuilder(FakeProviderBuilder, Crig::BearerAuth, H)) : FakeProviderExtension forall H
    _ = builder
    FakeProviderExtension.new
  end
end

class FakeModelListingClient
  include Crig::ModelListingClient

  def initialize(@models : Array(Crig::ModelInfo))
  end

  def list_models : Crig::ModelList
    Crig::ModelList.new(@models)
  end
end

class FakeModelLister
  include Crig::ModelLister(Array(Crig::ModelInfo))

  def self.new(client : Array(Crig::ModelInfo))
    allocate.tap(&.initialize(client))
  end

  def initialize(@client : Array(Crig::ModelInfo))
  end

  def list_all : Crig::ModelList
    Crig::ModelList.new(@client)
  end
end

class FakeAudioGenerationClientModel
  include Crig::AudioGenerationModel
  include Crig::AudioGenerationModelDyn

  getter name : String
  getter last_request : Crig::AudioGenerationRequest?

  def initialize(@name : String)
  end

  def audio_generation(request : Crig::AudioGenerationRequest)
    @last_request = request
    Crig::AudioGenerationResponse(String).new(Bytes[7_u8, 8_u8], "audio:#{@name}")
  end

  def audio_generation_request : Crig::AudioGenerationRequestBuilder
    Crig::AudioGenerationRequestBuilder.new(self)
  end
end

class FakeAudioGenerationClient
  include Crig::AudioGenerationClient(FakeAudioGenerationClientModel)
  include Crig::AudioGenerationClientDyn

  def audio_generation_model(model : String) : FakeAudioGenerationClientModel
    FakeAudioGenerationClientModel.new(model)
  end
end

class FakeImageGenerationClientModel
  include Crig::ImageGenerationModel
  include Crig::ImageGenerationModelDyn

  getter name : String
  getter last_request : Crig::ImageGenerationRequest?

  def initialize(@name : String)
  end

  def image_generation(request : Crig::ImageGenerationRequest)
    @last_request = request
    Crig::ImageGenerationResponse(String).new(Bytes[9_u8, 10_u8], "image:#{@name}")
  end

  def image_generation_request : Crig::ImageGenerationRequestBuilder
    Crig::ImageGenerationRequestBuilder.new(self)
  end
end

class FakeImageGenerationClient
  include Crig::ImageGenerationClient(FakeImageGenerationClientModel)
  include Crig::ImageGenerationClientDyn

  def image_generation_model(model : String) : FakeImageGenerationClientModel
    FakeImageGenerationClientModel.new(model)
  end
end

class FakeTranscriptionClientModel
  include Crig::TranscriptionModel
  include Crig::TranscriptionModelDyn

  getter name : String
  getter last_request : Crig::TranscriptionRequest?

  def initialize(@name : String)
  end

  def transcription(request : Crig::TranscriptionRequest)
    @last_request = request
    Crig::TranscriptionResponse(String).new("text:#{@name}", "transcription:#{@name}")
  end

  def transcription_request : Crig::TranscriptionRequestBuilder
    Crig::TranscriptionRequestBuilder.new(self)
  end
end

class FakeTranscriptionClient
  include Crig::TranscriptionClient(FakeTranscriptionClientModel)
  include Crig::TranscriptionClientDyn

  def transcription_model(model : String) : FakeTranscriptionClientModel
    FakeTranscriptionClientModel.new(model)
  end
end

struct DummyStringifiedJSON
  include JSON::Serializable

  @[JSON::Field(converter: Crig::JSONUtils::StringifiedJSON)]
  getter data : JSON::Any

  def initialize(@data : JSON::Any)
  end
end

struct DummyStringOrVec
  include JSON::Serializable

  @[JSON::Field(converter: Crig::JSONUtils::StringOrVecConverter(String))]
  getter items : Array(String)

  def initialize(@items : Array(String))
  end
end

struct DummyNullOrVec
  include JSON::Serializable

  @[JSON::Field(converter: Crig::JSONUtils::NullOrVecConverter(String))]
  getter items : Array(String)

  def initialize(@items : Array(String))
  end
end

struct StoredDoc
  include JSON::Serializable

  getter id : String
  getter name : String

  def initialize(@id : String, @name : String)
  end
end

struct WeatherPayload
  include JSON::Serializable

  getter city : String
  getter temperature : Int32

  def initialize(@city : String, @temperature : Int32)
  end
end

class RecordedFilter
  getter description : String

  def initialize(@description : String)
  end

  def self.from_filter(filter : Crig::Filter) : self
    case filter.kind.to_s
    when "Eq"
      eq(required_key(filter), required_value(filter))
    when "Gt"
      gt(required_key(filter), required_value(filter))
    when "Lt"
      lt(required_key(filter), required_value(filter))
    when "And"
      and_(from_filter(required_lhs(filter)), from_filter(required_rhs(filter)))
    when "Or"
      or_(from_filter(required_lhs(filter)), from_filter(required_rhs(filter)))
    else
      raise "Unsupported filter kind: #{filter.kind}"
    end
  end

  def self.eq(key : String, value : JSON::Any) : self
    new("eq(#{key},#{value.to_json})")
  end

  def self.gt(key : String, value : JSON::Any) : self
    new("gt(#{key},#{value.to_json})")
  end

  def self.lt(key : String, value : JSON::Any) : self
    new("lt(#{key},#{value.to_json})")
  end

  def self.and_(lhs : self, rhs : self) : self
    new("and(#{lhs.description},#{rhs.description})")
  end

  def self.or_(lhs : self, rhs : self) : self
    new("or(#{lhs.description},#{rhs.description})")
  end

  private def self.required_key(filter : Crig::Filter) : String
    filter.key || raise("missing key")
  end

  private def self.required_value(filter : Crig::Filter) : JSON::Any
    filter.value || raise("missing value")
  end

  private def self.required_lhs(filter : Crig::Filter) : Crig::Filter
    filter.lhs || raise("missing lhs")
  end

  private def self.required_rhs(filter : Crig::Filter) : Crig::Filter
    filter.rhs || raise("missing rhs")
  end
end

private def vector_embedding(document : String, values : Array(Float64)) : Crig::OneOrMany(Crig::Embeddings::Embedding)
  Crig::OneOrMany(Crig::Embeddings::Embedding).one(Crig::Embeddings::Embedding.new(document, values))
end

describe Crig do
  it "tracks the pinned upstream commit" do
    Crig::UPSTREAM_COMMIT.should eq("f5c4812de02e776d9a68b481a8cf71ed6b572a2d")
  end

  it "exposes the upstream source path" do
    Crig::UPSTREAM_SOURCE_PATH.should eq("vendor/rig/rig/rig-core")
  end
end

describe Crig::VerifyError, tags: %w[verify error] do
  it "builds parity-style verification errors" do
    Crig::VerifyError.invalid_authentication.message.should eq("invalid authentication")
    Crig::VerifyError.provider_error("boom").message.should eq("provider error: boom")
    Crig::VerifyError.http_error("timeout").message.should eq("http error: timeout")
  end
end

describe Crig::VerifyClient, tags: %w[verify client] do
  it "verifies through the concrete client interface" do
    client = SuccessfulVerifyClient.new

    client.verify

    client.verified?.should be_true
  end

  it "surfaces provider verification failures" do
    client = FailingVerifyClient.new

    expect_raises(Crig::VerifyError, "provider error: boom") do
      client.verify
    end
  end

  it "verifies asynchronously through the concrete client interface" do
    client = SuccessfulVerifyClient.new

    client.verify_async.receive.unwrap

    client.verified?.should be_true
  end
end

describe Crig::VerifyClientDyn, tags: %w[verify client_dyn] do
  it "supports the dynamic verification interface" do
    client = SuccessfulVerifyClient.new.as(Crig::VerifyClientDyn)

    client.verify
  end

  it "supports asynchronous dynamic verification" do
    client = SuccessfulVerifyClient.new.as(Crig::VerifyClientDyn)

    client.verify_async.receive.unwrap
  end
end

describe Crig::EmbeddingsClient(FakeEmbeddingsClientModel), tags: %w[embeddings client] do
  it "builds embedding models and builders through the client interface" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model("test-model")
    builder = client.embeddings(ExampleEmbedding, "test-model").document(ExampleEmbedding.new(["hello"]))

    model.name.should eq("test-model")
    builder.model.name.should eq("test-model")
    builder.build[0][1].first.document.should eq("test-model:hello")
  end

  it "supports the rust-style embeddings builder entry point without a type argument" do
    client = FakeEmbeddingsClient.new
    builder = client.embeddings("test-model")
      .simple_document("doc0", "Hello, world!")
      .simple_document("doc1", "Goodbye, world!")

    builder.model.name.should eq("test-model")
    builder.documents.map(&.[0].id).should eq(["doc0", "doc1"])
    builder.build.map { |entry| entry[1].first.document }.should eq(
      ["test-model:Hello, world!", "test-model:Goodbye, world!"]
    )
  end

  it "supports explicit embedding dimensions" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model_with_ndims("test-model", 42)
    builder = client.embeddings_with_ndims(ExampleEmbedding, "test-model", 42).document(ExampleEmbedding.new(["hello"]))

    model.ndims.should eq(42)
    builder.model.ndims.should eq(42)
  end

  it "supports the rust-style embeddings_with_ndims builder entry point without a type argument" do
    client = FakeEmbeddingsClient.new
    builder = client.embeddings_with_ndims("test-model", 42)
      .simple_document("doc0", "Hello, world!")

    builder.model.ndims.should eq(42)
    builder.build[0][1].first.document.should eq("test-model:Hello, world!")
  end
end

describe Crig::EmbeddingsClientDyn, tags: %w[embeddings client_dyn] do
  it "returns dynamic embedding models" do
    client = FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn)
    model = client.embedding_model("test-model")

    model.embed_text("hello").document.should eq("test-model:hello")
    client.embedding_model_with_ndims("test-model", 42).ndims.should eq(42)
  end
end

describe Crig::CompletionClient(FakeCompletionClientModel), tags: %w[completion client] do
  it "builds completion models and agent builders through the client interface" do
    client = FakeCompletionClient.new
    model = client.completion_model("gpt-4o")
    agent = client.agent("gpt-4o")
      .description("assistant")
      .preamble("You are concise.")
      .append_preamble("Be brief.")
      .context("Fact A")
      .default_max_turns(3)
      .temperature(0.2)
      .build
    response = agent.model.completion_request("hello").send(agent.model)

    model.name.should eq("gpt-4o")
    response.raw_response.should eq("raw:gpt-4o")
    agent.description.should eq("assistant")
    agent.preamble.should eq("You are concise.\nBe brief.")
    agent.static_context.map(&.text).should eq(["Fact A"])
    agent.default_max_turns.should eq(3)
    agent.temperature.should eq(0.2)
  end

  it "builds extractor builders through the client interface" do
    client = FakeCompletionClient.new
    extractor = client.extractor(String, "gpt-4o")
      .preamble("Only extract weather.")
      .context("Denver forecast")
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.auto)
      .retries(2)
      .build
    response = extractor.model.completion_request("hello").send(extractor.model)

    response.raw_response.should eq("raw:gpt-4o")
    extractor.retries.should eq(2)
    extractor.agent.preamble.try(&.includes?("ADDITIONAL INSTRUCTIONS")).should be_true
    extractor.agent.static_context.map(&.text).should eq(["Denver forecast"])
    extractor.agent.additional_params.try(&.["mode"].as_s).should eq("strict")
    extractor.agent.max_tokens.should eq(128)
    extractor.agent.tool_choice.should eq(Crig::Completion::ToolChoice.auto)
  end
end

describe Crig::CompletionClientDyn, tags: %w[completion client_dyn] do
  it "builds dynamic completion models" do
    client = FakeCompletionClient.new.as(Crig::CompletionClientDyn)
    model = client.completion_model("gpt-4o")
    response = model.completion_request(Crig::Completion::Message.user("hello")).send(model)

    response.raw_response.should eq("raw:gpt-4o")
  end

  it "builds dynamic agent builders backed by completion handles" do
    client = FakeCompletionClient.new.as(Crig::CompletionClientDyn)
    agent = client.agent("gpt-4o").name("assistant").build

    agent.model.should be_a(Crig::CompletionModelHandle)
    agent.name.should eq("assistant")
  end
end

describe Crig::CompletionModelHandle, tags: %w[completion model_handle] do
  it "wraps a dynamic completion model for request and stream builders" do
    inner = FakeCompletionClientModel.new("gpt-4o").as(Crig::Completion::CompletionModelDyn)
    handle = Crig::CompletionModelHandle.new(inner)
    completion = handle.completion_request("hello").send(handle)
    stream = handle.completion_request("hello").stream(handle)

    completion.raw_response.should eq("raw:gpt-4o")
    stream.chunks.should eq(["chunk:gpt-4o"])
    stream.response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "rejects direct construction from a client" do
    expect_raises(Exception, "Cannot create a completion model handle from a client") do
      Crig::CompletionModelHandle.make(nil, "gpt-4o")
    end
  end
end

describe Crig::FinalCompletionResponse, tags: %w[completion response] do
  it "exposes token usage for dynamic streaming parity" do
    response = Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))

    response.token_usage.try(&.total_tokens).should eq(4)
  end

  it "round-trips optional usage through json" do
    response = Crig::FinalCompletionResponse.from_json(%({"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3,"cached_input_tokens":0}}))

    response.usage.try(&.total_tokens).should eq(3)
    response.to_json.should contain(%("total_tokens":3))
  end
end

describe Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse), tags: %w[streaming completion] do
  it "stores streaming chunks and an optional final response" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["a", "b"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 2)),
    )

    response.chunks.should eq(["a", "b"])
    response.response.try(&.usage).try(&.total_tokens).should eq(2)
  end

  it "supports pause and resume state" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(["a"])

    response.is_paused.should be_false
    response.pause
    response.is_paused.should be_true
    response.resume
    response.is_paused.should be_false
  end

  it "consumes channel-backed streaming choices and aggregates the final response" do
    source = Channel(Crig::Concurrency::Result(Crig::RawStreamingChoice(Crig::FinalCompletionResponse))).new(4)
    source.send(Crig::Concurrency::Result(Crig::RawStreamingChoice(Crig::FinalCompletionResponse)).success(
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello ")
    ))
    source.send(Crig::Concurrency::Result(Crig::RawStreamingChoice(Crig::FinalCompletionResponse)).success(
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("world")
    ))
    source.send(Crig::Concurrency::Result(Crig::RawStreamingChoice(Crig::FinalCompletionResponse)).success(
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 2))
      )
    ))
    source.close

    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(source)
    items = response.consume

    items.map(&.kind.to_s).should eq(["Text", "Text", "Final"])
    response.choice.to_a.first.text.try(&.text).should eq("hello world")
    response.response.try(&.usage).try(&.total_tokens).should eq(2)
  end

  it "aggregates reasoning content from raw streaming choices" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning(
        "rs_1",
        Crig::Completion::ReasoningContent.text("step one", "sig_1")
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("final answer"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 5))
      ),
    ])

    choice_items = response.choice.to_a
    choice_items.size.should eq(2)
    choice_items[0].kind.reasoning?.should be_true
    choice_items[0].reasoning.try(&.id).should eq("rs_1")
    choice_items[0].reasoning.try(&.content.first.text).should eq("step one")
    choice_items[0].reasoning.try(&.content.first.signature).should eq("sig_1")
    choice_items[1].kind.text?.should be_true
    choice_items[1].text.try(&.text).should eq("final answer")
  end

  it "does not inject empty text into reasoning-only streams" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning(
        "rs_only",
        Crig::Completion::ReasoningContent.summary("hidden summary")
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 2))
      ),
    ])

    choice_items = response.choice.to_a
    choice_items.size.should eq(1)
    choice_items[0].kind.reasoning?.should be_true
    choice_items[0].reasoning.try(&.id).should eq("rs_only")
  end

  it "keeps assistant items in arrival order across reasoning text and tool calls" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning(
        "rs_interleaved",
        Crig::Completion::ReasoningContent.text("chain-of-thought")
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("final-text"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call(
        Crig::RawStreamingToolCall.new(
          "tool_1",
          "mock_tool",
          JSON.parse(%({"arg":1}))
        )
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3))
      ),
    ])

    choice_items = response.choice.to_a
    choice_items.size.should eq(3)
    choice_items[0].kind.reasoning?.should be_true
    choice_items[0].reasoning.try(&.id).should eq("rs_interleaved")
    choice_items[1].kind.text?.should be_true
    choice_items[1].text.try(&.text).should eq("final-text")
    choice_items[2].kind.tool_call?.should be_true
    choice_items[2].tool_call.try(&.id).should eq("tool_1")
  end

  it "keeps non contiguous text chunks split by tool calls" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("first"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call(
        Crig::RawStreamingToolCall.new(
          "tool_split",
          "mock_tool",
          JSON.parse(%({"arg":"x"}))
        )
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("second"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3))
      ),
    ])

    choice_items = response.choice.to_a
    choice_items.size.should eq(3)
    choice_items[0].kind.text?.should be_true
    choice_items[0].text.try(&.text).should eq("first")
    choice_items[1].kind.tool_call?.should be_true
    choice_items[1].tool_call.try(&.id).should eq("tool_split")
    choice_items[2].kind.text?.should be_true
    choice_items[2].text.try(&.text).should eq("second")
  end

  it "aggregates reasoning deltas into a single reasoning item" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))
      ),
    ])

    choice_items = response.choice.to_a
    choice_items.size.should eq(1)
    choice_items[0].kind.reasoning?.should be_true
    choice_items[0].reasoning.try(&.id).should eq("rs_delta")
    choice_items[0].reasoning.try(&.content.first.text).should eq("step one")
    choice_items[0].reasoning.try(&.content.first.signature).should be_nil
  end

  it "captures message ids and final responses from raw choices" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message_id("msg-raw-1"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 7))
      ),
    ])

    response.message_id.should eq("msg-raw-1")
    response.response.try(&.usage).try(&.total_tokens).should eq(7)
  end

  it "yields tool call delta and reasoning delta items while aggregating state" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).tool_call_delta(
        "tool-1",
        "internal-1",
        Crig::ToolCallDeltaContent.delta("{")
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", "step"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_delta", " one"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 9))
      ),
    ])

    item1 = response.next_item
    item2 = response.next_item
    item3 = response.next_item
    item4 = response.next_item
    item5 = response.next_item

    item1.should_not be_nil
    item1.try(&.kind.tool_call_delta?).should be_true
    item1.try(&.id).should eq("tool-1")
    item1.try(&.internal_call_id).should eq("internal-1")
    item2.should_not be_nil
    item2.try(&.kind.reasoning_delta?).should be_true
    item2.try(&.reasoning_delta).should eq("step")
    item3.should_not be_nil
    item3.try(&.kind.reasoning_delta?).should be_true
    item3.try(&.reasoning_delta).should eq(" one")
    item4.should_not be_nil
    item4.try(&.kind.final?).should be_true
    item5.should be_nil

    response.choice.to_a.size.should eq(1)
    response.choice.first.kind.reasoning?.should be_true
    response.choice.first.reasoning.try(&.content.first.text).should eq("step one")
    response.response.try(&.usage).try(&.total_tokens).should eq(9)
  end

  it "captures message ids silently during stateful iteration" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message_id("msg-live-1"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello"),
    ])

    first = response.next_item
    done = response.next_item

    first.should_not be_nil
    first.try(&.kind.text?).should be_true
    first.try(&.text).try(&.text).should eq("hello")
    done.should be_nil
    response.message_id.should eq("msg-live-1")
  end

  it "stops yielding after cancellation" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello 1"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello 2"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello 3"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 15))
      ),
    ])

    response.next_item.should_not be_nil
    response.next_item.should_not be_nil
    response.cancel

    response.next_item.should be_nil
    response.choice.to_a.size.should eq(1)
    response.choice.first.kind.text?.should be_true
    response.choice.first.text.try(&.text).should eq("hello 1hello 2")
  end

  it "does not advance while paused and resumes iteration afterward" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello 1"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello 2"),
    ])

    response.pause
    response.next_item.should be_nil
    response.chunks.should eq([] of String)

    response.resume
    first = response.next_item
    second = response.next_item
    done = response.next_item

    first.should_not be_nil
    first.try(&.kind.text?).should be_true
    first.try(&.text).try(&.text).should eq("hello 1")
    second.should_not be_nil
    second.try(&.kind.text?).should be_true
    second.try(&.text).try(&.text).should eq("hello 2")
    done.should be_nil
    response.choice.first.text.try(&.text).should eq("hello 1hello 2")
  end

  it "yields the final response only once during stateful iteration" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 3))
      ),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))
      ),
    ])

    first = response.next_item
    second = response.next_item

    first.should_not be_nil
    first.try(&.kind.final?).should be_true
    second.should be_nil
    response.final_response_yielded?.should be_true
    response.response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "converts into a completion response preserving raw response and message id" do
    response = Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).from_raw_choices([
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message_id("msg-convert-1"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("hello"),
      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 5))
      ),
    ])
    converted = response.to_completion_response

    converted.choice.first.kind.text?.should be_true
    converted.choice.first.text.try(&.text).should eq("hello")
    converted.usage.should eq(Crig::Completion::Usage.new)
    converted.raw_response.try(&.usage).try(&.total_tokens).should eq(5)
    converted.message_id.should eq("msg-convert-1")
  end
end

describe Crig::PauseControl, tags: %w[streaming control] do
  it "tracks paused state" do
    control = Crig::PauseControl.new

    control.is_paused.should be_false
    control.pause
    control.is_paused.should be_true
    control.resume
    control.is_paused.should be_false
  end
end

describe Crig::RawStreamingToolCall, tags: %w[streaming tool_call] do
  it "supports builder-style metadata setters and conversion to tool calls" do
    tool_call = Crig::RawStreamingToolCall.new(
      "tool-1",
      "weather",
      JSON.parse(%({"city":"Denver"}))
    ).with_internal_call_id("internal-1")
      .with_call_id("call-1")
      .with_signature("sig")
      .with_additional_params(JSON.parse(%({"source":"test"})))

    converted = tool_call.to_tool_call

    converted.should be_a(Crig::Completion::ToolCall)
    converted.call_id.should_not be_nil
    converted.signature.should_not be_nil
    converted.additional_params.should_not be_nil
  end
end

describe Crig::ToolCallDeltaContent, tags: %w[streaming tool_delta] do
  it "supports name and delta variants" do
    name = Crig::ToolCallDeltaContent.name("weather")
    delta = Crig::ToolCallDeltaContent.delta("{\"city\":\"Denver\"}")

    name.kind.name?.should be_true
    name.value.should eq("weather")
    delta.kind.delta?.should be_true
    delta.value.should eq("{\"city\":\"Denver\"}")
  end
end

describe Crig::RawStreamingChoice(String), tags: %w[streaming choice] do
  it "supports message, tool-call, reasoning, final-response, and message-id variants" do
    tool_call = Crig::RawStreamingToolCall.new("tool-1", "weather", JSON.parse(%({"city":"Denver"})))
    message = Crig::RawStreamingChoice(String).message("hello")
    tool = Crig::RawStreamingChoice(String).tool_call(tool_call)
    delta = Crig::RawStreamingChoice(String).tool_call_delta("tool-1", "internal-1", Crig::ToolCallDeltaContent.delta("{}"))
    reasoning = Crig::RawStreamingChoice(String).reasoning("r1", Crig::Completion::ReasoningContent.summary("step"))
    reasoning_delta = Crig::RawStreamingChoice(String).reasoning_delta("r1", "step")
    final_response = Crig::RawStreamingChoice(String).final_response("done")
    message_id = Crig::RawStreamingChoice(String).message_id("msg-1")

    message.kind.message?.should be_true
    tool.tool_call.try(&.name).should eq("weather")
    delta.content.try(&.value).should eq("{}")
    reasoning.reasoning_content.try(&.summary).should eq("step")
    reasoning_delta.reasoning_delta.should eq("step")
    final_response.final_response.should eq("done")
    message_id.message_id.should eq("msg-1")
  end
end

describe Crig::StreamedAssistantContent(Crig::FinalCompletionResponse), tags: %w[streaming assistant] do
  it "supports text, tool-call, reasoning, delta, and final variants" do
    tool_call = Crig::Completion::ToolCall.new(
      "tool-1",
      Crig::Completion::ToolFunction.new("weather", JSON.parse(%({"city":"Denver"})))
    )
    reasoning = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.summary("step")], "r1")

    text = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).text("hello")
    tool = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).tool_call(tool_call, "internal-1")
    delta = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).tool_call_delta("tool-1", "internal-1", Crig::ToolCallDeltaContent.delta("{}"))
    reasoning_item = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).reasoning(reasoning)
    reasoning_delta = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).reasoning_delta("r1", "step")
    final_response = Crig::StreamedAssistantContent(Crig::FinalCompletionResponse).final_response(
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 2))
    )

    text.text.try(&.text).should eq("hello")
    tool.kind.tool_call?.should be_true
    delta.content.try(&.value).should eq("{}")
    reasoning_item.reasoning.try(&.id).should eq("r1")
    reasoning_delta.reasoning_delta.should eq("step")
    final_response.final.try(&.usage).try(&.total_tokens).should eq(2)
  end
end

describe Crig::StreamedUserContent, tags: %w[streaming user] do
  it "supports tool-result streaming items" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool-1",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(Crig::Completion::ToolResultContent.text("done")),
      "call-1",
    )
    content = Crig::StreamedUserContent.tool_result(tool_result, "internal-1")

    content.kind.tool_result?.should be_true
    content.tool_result.try(&.id).should eq("tool-1")
    content.internal_call_id.should eq("internal-1")
  end
end

describe Crig::StreamingResult(String), tags: %w[streaming result] do
  it "stores raw streaming choices" do
    result = Crig::StreamingResult(String).new([
      Crig::RawStreamingChoice(String).message("hello"),
      Crig::RawStreamingChoice(String).final_response("done"),
    ])

    result.items.size.should eq(2)
    result.items.last.final_response.should eq("done")
  end
end

describe Crig::AgentBuilder(FakeCompletionClientModel), tags: %w[agent builder] do
  it "supports removing a preamble after setting it" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .preamble("base")
      .without_preamble
      .build

    agent.preamble.should be_nil
  end

  it "stores dynamic context sources and queries them through vector indexes" do
    model = FakeCompletionClientModel.new("gpt-4o")
    embedding_model = FakeEmbeddingsClientModel.new("embed", 1)
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {
        "doc-1",
        StoredDoc.new("doc-1", "Denver"),
        vector_embedding("Denver weather", [1.0]),
      },
    ])
    index = store.index(embedding_model)
    request = Crig::VectorSearchRequest.new("weather", 1_u64)

    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .dynamic_context(1, index)
      .build

    agent.dynamic_context.size.should eq(1)
    agent.dynamic_context.first.sample.should eq(1)
    agent.dynamic_context.first.search(request).first[1].should eq("doc-1")
  end

  it "stores static tools and explicit tool server handles" do
    model = FakeCompletionClientModel.new("gpt-4o")
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )
    stocks_tool = Crig::Completion::ToolDefinition.new(
      "stocks",
      "Lookup stocks",
      JSON.parse(%({"type":"object"})),
    )
    handle = Crig::ToolServerHandle.new("shared-tools")

    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .tool(weather_tool)
      .tools([stocks_tool])
      .tool_server_handle(handle)
      .build

    agent.static_tools.map(&.name).should eq(["weather", "stocks"])
    agent.tool_server_handle.try(&.id).should eq("shared-tools")
  end

  it "routes builder-managed tools through the tool server run loop" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .tool(EchoTool.new.as(Crig::ToolDyn))
      .build

    handle = agent.tool_server_handle || raise "missing tool server handle"
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    JSON.parse(handle.call_tool("echo", %({"value":"hello"}))).as_s.should eq("hello")
  end

  it "stores dynamic tool sources and their associated tool definitions" do
    model = FakeCompletionClientModel.new("gpt-4o")
    embedding_model = FakeEmbeddingsClientModel.new("embed", 1)
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {
        "doc-1",
        StoredDoc.new("doc-1", "Denver"),
        vector_embedding("Denver weather", [1.0]),
      },
    ])
    index = store.index(embedding_model)
    request = Crig::VectorSearchRequest.new("weather", 1_u64)
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )

    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .dynamic_tools(1, index, [weather_tool])
      .build

    agent.dynamic_tools.size.should eq(1)
    agent.dynamic_tools.first.sample.should eq(1)
    agent.dynamic_tools.first.tools.map(&.name).should eq(["weather"])
    agent.dynamic_tools.first.search(request).first[1].should eq("doc-1")
  end

  it "adds an MCP tool through rmcp_tool using a tool server handle" do
    model = FakeCompletionClientModel.new("gpt-4o")
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .rmcp_tool(definition, client)
      .build

    handle = agent.tool_server_handle.not_nil!
    handle.get_tool_defs(nil).map(&.name).should eq(["sum"])
    handle.call_tool("sum", %({"x":2,"y":3})).should eq("5")
  end

  it "adds multiple MCP tools through rmcp_tools using a tool server handle" do
    model = FakeCompletionClientModel.new("gpt-4o")
    client, server = build_mcp_test_client_and_server
    sum_definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )
    diff_definition = MCP::Protocol::Tool.new(
      name: "diff",
      description: "Subtract numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", sum_definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    server.add_tool("diff", "Subtract numbers", diff_definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x - y).to_s)] of MCP::Protocol::ContentBlock)
    end

    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .rmcp_tools([sum_definition, diff_definition], client)
      .build

    handle = agent.tool_server_handle.not_nil!
    handle.get_tool_defs(nil).map(&.name).sort.should eq(["diff", "sum"])
    handle.call_tool("sum", %({"x":4,"y":1})).should eq("5")
    handle.call_tool("diff", %({"x":4,"y":1})).should eq("3")
  end
end

describe Crig::Agent(FakeCompletionClientModel), tags: %w[agent] do
  it "builds completion requests with static agent configuration" do
    model = FakeCompletionClientModel.new("gpt-4o")
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .name("assistant")
      .preamble("Be concise.")
      .context("Denver is cold.")
      .tool(weather_tool)
      .temperature(0.3)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .output_schema(JSON.parse(%({"title":"answer"})))
      .build

    request = agent.completion("What is the weather?").build

    agent.resolved_name.should eq("assistant")
    request.preamble.should eq("Be concise.")
    request.documents.map(&.text).should eq(["Denver is cold."])
    request.tools.map(&.name).should eq(["weather"])
    request.temperature.should eq(0.3)
    request.max_tokens.should eq(128)
    request.tool_choice.try(&.kind.required?).should be_true
    request.additional_params.try(&.["mode"].as_s).should eq("strict")
    request.output_schema.try(&.["title"].as_s).should eq("answer")
  end

  it "merges dynamic context and tools from rag text in chat history" do
    model = FakeCompletionClientModel.new("gpt-4o")
    embedding_model = FakeEmbeddingsClientModel.new("embed", 1)
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {
        "doc-1",
        StoredDoc.new("doc-1", "Denver"),
        vector_embedding("Denver weather", [1.0]),
      },
    ])
    index = store.index(embedding_model)
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .dynamic_context(1, index)
      .dynamic_tools(1, index, [weather_tool])
      .build

    prompt = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("How can I help?")
      ),
    )
    history = [Crig::Completion::Message.user("Please use weather retrieval for Denver")]

    request = agent.completion(prompt, history).build

    request.documents.map(&.id).should contain("doc-1")
    request.tools.map(&.name).should eq(["weather"])
  end

  it "falls back to the upstream unknown-agent name constant" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    agent.resolved_name.should eq("Unnamed Agent")
  end

  it "builds prompt requests with history and extended details" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    history = [Crig::Completion::Message.user("Earlier")]

    request = agent.prompt("Hello").max_turns(2).with_tool_concurrency(3).with_history(history)
    response = request.extended_details.send

    request.max_turns.should eq(2)
    request.concurrency.should eq(3)
    response.output.should eq("completion:gpt-4o")
    response.usage.output_tokens.should eq(1)
    response.messages.should_not be_nil
    response.messages.try(&.size).should eq(3)
  end

  it "supports agent chat through the prompt-request path" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    history = [Crig::Completion::Message.user("Earlier")]

    response = agent.chat("Hello", history)

    response.should eq("completion:gpt-4o")
  end

  it "builds the upstream agent tool definition" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .name("sub-agent")
      .description("Handles delegated tasks")
      .preamble("Stay concise.")
      .build

    definition = agent.definition("")

    definition.name.should eq("sub-agent")
    definition.description.should contain("Prompt a sub-agent to do a task for you")
    definition.description.should contain("Agent name: sub-agent")
    definition.description.should contain("Agent description: Handles delegated tasks")
    definition.description.should contain("Agent system prompt: Stay concise.")
    definition.parameters["required"][0].as_s.should eq("prompt")
  end

  it "falls back to the upstream default agent tool name" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    agent.definition("").name.should eq("agent_tool")
  end

  it "can be called as a sub-agent tool" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    agent.call(Crig::AgentToolArgs.new("delegate this")).should eq("completion:gpt-4o")
  end
end

describe Crig::WithBuilderTools do
  it "stores static tool definitions" do
    weather_tool = Crig::Completion::ToolDefinition.new(
      "weather",
      "Lookup weather",
      JSON.parse(%({"type":"object"})),
    )

    wrapper = Crig::WithBuilderTools.new([weather_tool])

    wrapper.static_tools.map(&.name).should eq(["weather"])
  end
end

describe Crig::WithToolServerHandle do
  it "stores the provided tool server handle" do
    handle = Crig::ToolServerHandle.new("shared-tools")

    wrapper = Crig::WithToolServerHandle.new(handle)

    wrapper.handle.id.should eq("shared-tools")
  end

  it "implements streaming traits" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    # Verify Agent includes streaming traits
    agent.should be_a(Crig::StreamingPrompt(FakeCompletionClientModel))
    agent.should be_a(Crig::StreamingChat(FakeCompletionClientModel))
    agent.should be_a(Crig::StreamingCompletion(FakeCompletionClientModel))
  end
end

describe Crig::AgentToolArgs do
  it "round-trips the delegated prompt payload" do
    payload = Crig::AgentToolArgs.new("delegate this")
    roundtrip = Crig::AgentToolArgs.from_json(payload.to_json)

    roundtrip.prompt.should eq("delegate this")
  end
end

describe Crig::PromptResponse do
  it "stores output, usage, and optional messages" do
    response = Crig::PromptResponse.new("hello", Crig::Completion::Usage.new(total_tokens: 2))
      .with_messages([Crig::Completion::Message.user("hello")])

    response.to_s.should eq("hello")
    response.usage.total_tokens.should eq(2)
    response.messages.try(&.size).should eq(1)
  end
end

describe Crig::HookAction, tags: %w[agent hooks] do
  it "supports continue and terminate helpers" do
    Crig::HookAction.cont.kind.continue?.should be_true
    terminated = Crig::HookAction.terminate("stop")

    terminated.kind.terminate?.should be_true
    terminated.reason.should eq("stop")
  end
end

describe Crig::ToolCallHookAction, tags: %w[agent tool_hooks] do
  it "supports continue, skip, and terminate helpers" do
    Crig::ToolCallHookAction.cont.kind.continue?.should be_true
    skipped = Crig::ToolCallHookAction.skip("not allowed")
    terminated = Crig::ToolCallHookAction.terminate("stop")

    skipped.kind.skip?.should be_true
    skipped.reason.should eq("not allowed")
    terminated.kind.terminate?.should be_true
    terminated.reason.should eq("stop")
  end
end

describe Crig::PromptHook, tags: %w[agent prompt_hooks] do
  it "runs per-request hooks through the prompt request path" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    hook = RecordingPromptHook.new

    response = agent.prompt("Hello").with_hook(hook).extended_details.send

    response.output.should eq("completion:gpt-4o")
    hook.events.should eq(["call:Hello", "response:raw:gpt-4o"])
  end

  it "can terminate before the completion call" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    hook = RecordingPromptHook.new(terminate_on_call: true)

    expect_raises(Crig::Completion::PromptError, "PromptCancelled: stop-before-send") do
      agent.prompt("Hello").with_hook(hook).send
    end
  end

  it "can terminate after the completion response" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    hook = RecordingPromptHook.new(terminate_on_response: true)

    expect_raises(Crig::Completion::PromptError, "PromptCancelled: stop-after-send") do
      agent.prompt("Hello").with_hook(hook).send
    end
  end
end

describe Crig::PromptRequest(Crig::Extended, FakeMultiTurnPromptModel) do
  it "continues through tool calls until a final text response is returned" do
    model = FakeMultiTurnPromptModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    response = agent.prompt("do tool work").max_turns(3).extended_details.send

    response.output.should eq("done")
    response.usage.total_tokens.should eq(10)
    response.messages.should_not be_nil
    response.messages.try(&.size).should eq(4)
    response.messages.try(&.[0].role.user?).should be_true
    response.messages.try(&.[1].role.assistant?).should be_true
    response.messages.try(&.[1].content.first.as(Crig::Completion::AssistantContent).kind.tool_call?).should be_true
    response.messages.try(&.[2].role.user?).should be_true
    response.messages.try(&.[2].content.first.as(Crig::Completion::UserContent).kind.tool_result?).should be_true
    response.messages.try(&.[3].role.assistant?).should be_true
    response.messages.try(&.[3].content.first.as(Crig::Completion::AssistantContent).text).try(&.text).should eq("done")
    model.turn_counter.should eq(2)
  end

  it "raises after consecutive tool-call turns exceed max turns" do
    model = FakeMultiTurnPromptModel.new(2)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    error = expect_raises(Crig::Completion::PromptError, "MaxTurnsExceeded: 0") do
      agent.prompt("do tool work").extended_details.send
    end

    error.reason.should eq("MaxTurnsExceeded: 0")
    error.chat_history.should_not be_nil
    error.prompt.should eq(Crig::Completion::Message.tool_result_with_call_id("tool_call_1", "call_1", "tool-result"))
  end

  it "wraps tool-call termination with prompt-cancelled history" do
    model = FakeMultiTurnPromptModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    error = expect_raises(Crig::Completion::PromptError, "PromptCancelled: stop-tool-call") do
      agent.prompt("do tool work").with_history([] of Crig::Completion::Message).with_hook(TerminatingToolCallHook.new).extended_details.send
    end

    error.reason.should eq("stop-tool-call")
    error.chat_history.should_not be_nil
    error.chat_history.try(&.size).should eq(2)
    error.chat_history.try(&.[0].role.user?).should be_true
    error.chat_history.try(&.[1].role.assistant?).should be_true
    error.chat_history.try(&.[1].content.first.as(Crig::Completion::AssistantContent).kind.tool_call?).should be_true
  end

  it "wraps tool-result termination with prompt-cancelled history" do
    model = FakeMultiTurnPromptModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    error = expect_raises(Crig::Completion::PromptError, "PromptCancelled: stop-tool-result") do
      agent.prompt("do tool work").with_history([] of Crig::Completion::Message).with_hook(TerminatingToolResultHook.new).extended_details.send
    end

    error.reason.should eq("stop-tool-result")
    error.chat_history.should_not be_nil
    error.chat_history.try(&.size).should eq(2)
    error.chat_history.try(&.[0].role.user?).should be_true
    error.chat_history.try(&.[1].role.assistant?).should be_true
    error.chat_history.try(&.[1].content.first.as(Crig::Completion::AssistantContent).kind.tool_call?).should be_true
  end

  it "turns skipped tool calls into tool-result user messages" do
    model = FakeMultiTurnPromptModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    response = agent.prompt("do tool work").with_hook(SkippingToolCallHook.new).extended_details.send

    response.output.should eq("done")
    response.messages.should_not be_nil
    tool_result_message = response.messages.try(&.[2])
    tool_result_message.should_not be_nil
    tool_result_message.try(&.role.user?).should be_true
    user_content = tool_result_message.try(&.content.first).try(&.as(Crig::Completion::UserContent))
    user_content.should_not be_nil
    user_content.try(&.kind.tool_result?).should be_true
    user_content.try(&.tool_result).try(&.content.first.text).try(&.text).should eq("tool skipped")
  end

  it "stringifies tool execution errors into tool-result user messages" do
    model = FakeMultiTurnPromptModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { raise "resolver boom" })
    agent = Crig::AgentBuilder(FakeMultiTurnPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    response = agent.prompt("do tool work").extended_details.send

    response.output.should eq("done")
    tool_result_message = response.messages.try(&.[2])
    tool_result_message.should_not be_nil
    user_content = tool_result_message.try(&.content.first).try(&.as(Crig::Completion::UserContent))
    user_content.should_not be_nil
    tool_result_text = user_content.try(&.tool_result).try(&.content.first.text).try(&.text)
    tool_result_text.not_nil!.should contain("resolver boom")
  end
end

describe Crig::PromptRequest(Crig::Extended, FakeMultiToolPromptModel) do
  it "keeps tool result messages in tool-call order when concurrency is enabled" do
    model = FakeMultiToolPromptModel.new
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, args : String) {
      parsed = JSON.parse(args)
      value = parsed["input"].as_s
      value == "one" ? "result-one" : "result-two"
    })
    agent = Crig::AgentBuilder(FakeMultiToolPromptModel).new(model)
      .tool_server_handle(handle)
      .build

    response = agent.prompt("do tool work").with_tool_concurrency(2).extended_details.send

    response.output.should eq("done")
    tool_result_message = response.messages.try(&.[2])
    tool_result_message.should_not be_nil
    tool_result_message.try(&.content.size).should eq(2)
    first = tool_result_message.try(&.content.to_a[0]).try(&.as(Crig::Completion::UserContent))
    second = tool_result_message.try(&.content.to_a[1]).try(&.as(Crig::Completion::UserContent))
    first.should_not be_nil
    second.should_not be_nil
    first.try(&.tool_result).try(&.id).should eq("tool_call_1")
    first.try(&.tool_result).try(&.content.first.text).try(&.text).should eq("result-one")
    second.try(&.tool_result).try(&.id).should eq("tool_call_2")
    second.try(&.tool_result).try(&.content.first.text).try(&.text).should eq("result-two")
  end
end

describe Crig::FinalResponse do
  it "supports the upstream empty helper and accessors" do
    response = Crig::FinalResponse.empty

    response.response.should eq("")
    response.usage.total_tokens.should eq(0)
    response.history.should be_nil
  end
end

describe Crig::MultiTurnStreamItem(String) do
  it "builds final-response items without history" do
    item = Crig::MultiTurnStreamItem(String).final_response(
      "done",
      Crig::Completion::Usage.new(total_tokens: 1),
    )

    item.kind.final_response?.should be_true
    item.final_response.try(&.response).should eq("done")
    item.final_response.try(&.history).should be_nil
  end

  it "builds final-response items with history" do
    history = [Crig::Completion::Message.user("hello")]
    item = Crig::MultiTurnStreamItem(String).final_response_with_history(
      "done",
      Crig::Completion::Usage.new(total_tokens: 2),
      history,
    )

    item.kind.final_response?.should be_true
    item.final_response.try(&.response).should eq("done")
    item.final_response.try(&.history).should eq(history)
  end
end

describe Crig::StreamingError do
  it "builds parity-style streaming error wrappers" do
    completion = Crig::StreamingError.completion("boom")
    prompt = Crig::StreamingError.prompt("stop")
    tool = Crig::StreamingError.tool("missing")

    completion.message.should eq("CompletionError: boom")
    completion.kind.should eq(Crig::StreamingError::Kind::Completion)
    prompt.message.should eq("PromptError: stop")
    prompt.kind.should eq(Crig::StreamingError::Kind::Prompt)
    tool.message.should eq("ToolSetError: missing")
    tool.kind.should eq(Crig::StreamingError::Kind::Tool)
  end

  it "retains wrapped prompt error context in streaming errors" do
    prompt_error = Crig::Completion::PromptError.prompt_cancelled(
      [Crig::Completion::Message.user("hello")],
      "stop",
    )
    error = Crig::StreamingError.prompt(prompt_error)

    error.message.should eq("PromptError: PromptCancelled: stop")
    error.kind.should eq(Crig::StreamingError::Kind::Prompt)
    error.prompt_error.should eq(prompt_error)
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("hello")])
  end
end

describe Crig::Completion::CompletionError do
  it "behaves as a concrete exception wrapper" do
    error = Crig::Completion::CompletionError.provider_error("boom")
    request = Crig::Completion::CompletionError.request_error(Exception.new("bad request"))

    error.message.should eq("ProviderError: boom")
    error.kind.should eq(Crig::Completion::CompletionError::Kind::ProviderError)
    request.kind.should eq(Crig::Completion::CompletionError::Kind::RequestError)
    request.source_error.should be_a(Exception)
  end
end

describe Crig::Completion::StructuredOutputError do
  it "behaves as a concrete exception wrapper" do
    prompt = Crig::Completion::PromptError.prompt_cancelled(
      [Crig::Completion::Message.user("hello")],
      "stop",
    )
    prompt_error = Crig::Completion::StructuredOutputError.prompt_error(prompt)
    deserialization = Crig::Completion::StructuredOutputError.deserialization_error(Exception.new("bad schema"))
    empty = Crig::Completion::StructuredOutputError.empty_response

    prompt_error.message.should eq("PromptError: PromptCancelled: stop")
    prompt_error.kind.should eq(Crig::Completion::StructuredOutputError::Kind::PromptError)
    prompt_error.prompt_error.should eq(prompt)
    deserialization.kind.should eq(Crig::Completion::StructuredOutputError::Kind::DeserializationError)
    deserialization.source_error.should be_a(Exception)
    empty.message.should eq("EmptyResponse: model returned no content")
    empty.kind.should eq(Crig::Completion::StructuredOutputError::Kind::EmptyResponse)
  end
end

describe Crig::StreamingPromptRequest(FakeCompletionClientModel) do
  it "builds requests from an agent with default max turns" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o"))
      .default_max_turns(2)
      .build
    request = Crig::StreamingPromptRequest(FakeCompletionClientModel).from_agent(agent, "hello")

    request.prompt.rag_text.should eq("hello")
    request.max_turns.should eq(2)
  end

  it "streams prompts through the agent model and packages a final response" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    response = agent.stream_prompt("hello").send

    response.chunks.should eq(["chunk:gpt-4o"])
    response.response.try(&.response).should eq("chunk:gpt-4o")
    response.response.try(&.history).should be_nil
  end

  it "builds stream items for the one-shot streaming path" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    result = agent.stream_prompt("hello").send_items

    result.items.size.should eq(3)
    result.items[0].kind.stream_assistant_item?.should be_true
    result.items[0].assistant_item.try(&.text).try(&.text).should eq("chunk:gpt-4o")
    result.items[1].kind.stream_assistant_item?.should be_true
    result.items[1].assistant_item.try(&.kind.final?).should be_true
    result.items[1].assistant_item.try(&.final).try(&.response).should eq("chunk:gpt-4o")
    result.items[1].assistant_item.try(&.final).try(&.usage).try(&.total_tokens).should eq(3)
    result.items[2].kind.final_response?.should be_true
    result.items[2].final_response.try(&.response).should eq("chunk:gpt-4o")
    result.items[2].final_response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "supports streaming chat history" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    history = [Crig::Completion::Message.user("earlier")]

    response = agent.stream_chat("hello", history).send

    response.response.try(&.history).try(&.size).should eq(3)
  end

  it "supports multi-turn storage and streaming hook termination" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    hook = RecordingPromptHook.new
    request = agent.stream_prompt("hello").multi_turn(3).with_hook(hook)

    request.max_turns.should eq(3)
    request.send.chunks.should eq(["chunk:gpt-4o"])
  end

  it "wraps text-delta termination with prompt-cancelled history" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    error = expect_raises(Crig::StreamingError) do
      agent.stream_prompt("hello").with_history([] of Crig::Completion::Message).with_hook(TerminatingTextDeltaHook.new).send_items
    end

    error.message.should eq("PromptError: PromptCancelled: stop-now")
    error.prompt_error.should_not be_nil
    error.prompt_error.try(&.reason).should eq("stop-now")
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("hello")])
  end

  it "wraps stream-finish termination with prompt-cancelled history" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build

    error = expect_raises(Crig::StreamingError) do
      agent.stream_prompt("hello").with_history([] of Crig::Completion::Message).with_hook(TerminatingStreamFinishHook.new).send_items
    end

    error.message.should eq("PromptError: PromptCancelled: stop-stream-finish")
    error.prompt_error.should_not be_nil
    error.prompt_error.try(&.reason).should eq("stop-stream-finish")
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("hello")])
  end
end

describe Crig::StreamingPromptRequest(FakeStreamingAgentModel) do
  it "passes through reasoning assistant items" do
    agent = Crig::AgentBuilder(FakeStreamingAgentModel).new(
      FakeStreamingAgentModel.new(FakeStreamingAgentModel::Mode::Reasoning)
    ).build

    result = agent.stream_prompt("hello").send_items

    result.items.size.should eq(2)
    result.items[0].kind.stream_assistant_item?.should be_true
    result.items[0].assistant_item.try(&.kind.reasoning?).should be_true
    result.items[0].assistant_item.try(&.reasoning).try(&.id).should eq("r1")
    result.items[0].assistant_item.try(&.reasoning).try(&.display_text).should eq("step one")
    result.items[1].kind.final_response?.should be_true
    result.items[1].final_response.try(&.usage).try(&.total_tokens).should eq(1)
  end
end

describe Crig::StreamingPromptRequest(FakeMultiTurnStreamingModel) do
  it "continues after a streamed tool call turn" do
    model = FakeMultiTurnStreamingModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    result = agent.stream_prompt("do tool work").multi_turn(3).send_items

    saw_tool_call = false
    saw_tool_result = false
    saw_final_response = false
    final_text = ""

    result.items.each do |item|
      case item.kind
      in .stream_assistant_item?
        assistant_item = item.assistant_item
        next unless assistant_item

        if assistant_item.kind.tool_call?
          saw_tool_call = true
        elsif assistant_item.kind.text?
          final_text += assistant_item.text.try(&.text) || ""
        end
      in .stream_user_item?
        saw_tool_result = true if item.user_item.try(&.kind.tool_result?)
      in .final_response?
        saw_final_response = true
      end
    end

    saw_tool_call.should be_true
    saw_tool_result.should be_true
    saw_final_response.should be_true
    final_text.should eq("done")
    model.turn_counter.should eq(2)
  end

  it "raises after consecutive tool-call turns exceed max turns" do
    model = FakeMultiTurnStreamingModel.new(2)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    expect_raises(Crig::StreamingError, "PromptError: MaxTurnsExceeded: 0") do
      agent.stream_prompt("do tool work").send_items
    end
  end

  it "wraps tool-call termination with prompt-cancelled history" do
    model = FakeMultiTurnStreamingModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    error = expect_raises(Crig::StreamingError) do
      agent.stream_prompt("do tool work").with_history([] of Crig::Completion::Message).with_hook(TerminatingToolCallHook.new).send_items
    end

    error.message.should eq("PromptError: PromptCancelled: stop-tool-call")
    error.prompt_error.should_not be_nil
    error.prompt_error.try(&.reason).should eq("stop-tool-call")
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("do tool work")])
  end

  it "wraps tool-result termination with prompt-cancelled history" do
    model = FakeMultiTurnStreamingModel.new(1)
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeMultiTurnStreamingModel).new(model)
      .tool_server_handle(handle)
      .build

    error = expect_raises(Crig::StreamingError) do
      agent.stream_prompt("do tool work").with_history([] of Crig::Completion::Message).with_hook(TerminatingToolResultHook.new).send_items
    end

    error.message.should eq("PromptError: PromptCancelled: stop-tool-result")
    error.prompt_error.should_not be_nil
    error.prompt_error.try(&.reason).should eq("stop-tool-result")
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("do tool work")])
  end
end

describe Crig::StreamingPromptRequest(FakeDeltaStreamingModel) do
  it "passes through reasoning delta stream items and assembles them into the next-turn assistant history" do
    agent = Crig::AgentBuilder(FakeDeltaStreamingModel).new(
      FakeDeltaStreamingModel.new(FakeDeltaStreamingModel::Mode::ReasoningDeltaAndToolCall)
    ).tool_server_handle(
      Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    ).default_max_turns(1).build

    result = agent.stream_prompt("hello").with_history([] of Crig::Completion::Message).send_items

    result.items.size.should eq(7)
    result.items[0].assistant_item.try(&.kind.reasoning_delta?).should be_true
    result.items[0].assistant_item.try(&.reasoning_delta).should eq("step")
    result.items[1].assistant_item.try(&.kind.reasoning_delta?).should be_true
    result.items[1].assistant_item.try(&.reasoning_delta).should eq(" one")
    result.items[2].assistant_item.try(&.kind.tool_call?).should be_true
    result.items[3].user_item.try(&.kind.tool_result?).should be_true
    result.items[4].assistant_item.try(&.kind.text?).should be_true
    result.items[4].assistant_item.try(&.text).try(&.text).should eq("done")
    result.items[5].assistant_item.try(&.kind.final?).should be_true
    result.items[5].assistant_item.try(&.final).try(&.response).should eq("done")
    result.items[5].assistant_item.try(&.final).try(&.usage).try(&.total_tokens).should eq(4)
    final_history = result.items.last.final_response.try(&.history)
    final_history.should_not be_nil
    assistant_message = final_history.try(&.find do |message|
      message.role.assistant? && message.content.any? do |content|
        content.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          .as(Crig::Completion::AssistantContent).kind.reasoning?
      end
    end)
    assistant_message.should_not be_nil
    assistant_content = assistant_message.try(&.content.first).try(&.as(Crig::Completion::AssistantContent))
    assistant_content.should_not be_nil
    assistant_content.try(&.kind.reasoning?).should be_true
    assistant_content.try(&.reasoning).try(&.content.first.text).should eq("step one")
  end

  it "sends tool call delta events to the hook before the tool call turn completes" do
    hook = RecordingStreamingPromptHook.new
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeDeltaStreamingModel).new(
      FakeDeltaStreamingModel.new(FakeDeltaStreamingModel::Mode::ToolCallDeltaAndToolCall)
    ).tool_server_handle(handle).default_max_turns(1).build

    result = agent.stream_prompt("hello").with_hook(hook).send_items

    hook.events.should eq([
      "tool-call-delta:tool_call_1:internal_1:missing_tool:",
      "tool-call-delta:tool_call_1:internal_1::{\"input\":\"value\"}",
    ])
    result.items.any? { |item| item.user_item.try(&.kind.tool_result?) == true }.should be_true
    result.items.any? do |item|
      item.assistant_item.try(&.kind.final?) == true &&
        item.assistant_item.try(&.final).try(&.response) == "done"
    end.should be_true
    result.items.last.final_response.try(&.response).should eq("done")
  end

  it "wraps tool-call-delta termination with prompt-cancelled history" do
    handle = Crig::ToolServerHandle.with_resolver("shared-tools", ->(_name : String, _args : String) { "tool-result" })
    agent = Crig::AgentBuilder(FakeDeltaStreamingModel).new(
      FakeDeltaStreamingModel.new(FakeDeltaStreamingModel::Mode::ToolCallDeltaAndToolCall)
    ).tool_server_handle(handle).default_max_turns(1).build

    error = expect_raises(Crig::StreamingError) do
      agent.stream_prompt("hello").with_history([] of Crig::Completion::Message).with_hook(TerminatingToolCallDeltaHook.new).send_items
    end

    error.message.should eq("PromptError: PromptCancelled: stop-tool-call-delta")
    error.prompt_error.should_not be_nil
    error.prompt_error.try(&.reason).should eq("stop-tool-call-delta")
    error.prompt_error.try(&.chat_history).should eq([Crig::Completion::Message.user("hello")])
  end
end

describe "Crig streaming helpers" do
  it "merges reasoning blocks preserving order and signatures for matching ids" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new(
      [Crig::Completion::ReasoningContent.text("step-1", "sig-1")],
      "rs_1",
    )
    second = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("step-2", "sig-2"),
        Crig::Completion::ReasoningContent.summary("summary"),
      ],
      "rs_1",
    )

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, second)

    accumulated.size.should eq(1)
    merged = accumulated.first
    merged.id.should eq("rs_1")
    merged.content.size.should eq(3)
    merged.content[0].text.should eq("step-1")
    merged.content[0].signature.should eq("sig-1")
    merged.content[1].text.should eq("step-2")
    merged.content[1].signature.should eq("sig-2")
  end

  it "keeps distinct reasoning ids as separate items" do
    accumulated = [
      Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("step-1")], "rs_a"),
    ]
    incoming = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("step-2")], "rs_b")

    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should eq("rs_a")
    accumulated[1].id.should eq("rs_b")
  end

  it "keeps nil reasoning ids as separate items" do
    accumulated = [
      Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("first")]),
    ]
    incoming = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.text("second")])

    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should be_nil
    accumulated[1].id.should be_nil
    accumulated[0].content[0].text.should eq("first")
    accumulated[1].content[0].text.should eq("second")
  end

  it "converts tool results to user messages with optional call ids" do
    message = Crig.tool_result_to_user_message("tool-1", "call-1", "done")

    message.role.user?.should be_true
    content = message.content.first
    content.should be_a(Crig::Completion::UserContent)
    user_content = content.as(Crig::Completion::UserContent)
    user_content.kind.tool_result?.should be_true
    result = user_content.tool_result
    result.should_not be_nil
    result.try(&.id).should eq("tool-1")
    result.try(&.call_id).should eq("call-1")
    result.try(&.content.first.text).try(&.text).should eq("done")
  end

  it "streams assistant chunks to an io and returns the final response" do
    items = Crig::MultiTurnStreamingResult(Crig::FinalResponse).new([
      Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_item(
        Crig::StreamedAssistantContent(Crig::FinalResponse).text("hello ")
      ),
      Crig::MultiTurnStreamItem(Crig::FinalResponse).stream_item(
        Crig::StreamedAssistantContent(Crig::FinalResponse).text("world")
      ),
      Crig::MultiTurnStreamItem(Crig::FinalResponse).final_response_with_history(
        "hello world",
        Crig::Completion::Usage.new(total_tokens: 2),
        [Crig::Completion::Message.user("hello")],
      ),
    ])
    io = IO::Memory.new

    final_response = Crig.stream_to_stdout(items, io)

    io.to_s.should eq("Response: hello world")
    final_response.response.should eq("hello world")
    final_response.usage.total_tokens.should eq(2)
  end
end

describe Crig::TypedPromptRequest(WeatherPayload, Crig::Standard, FakeStructuredCompletionModel) do
  it "parses typed prompt responses and carries a generated schema title" do
    model = FakeStructuredCompletionModel.new
    prompt_agent = Crig::Agent(FakeStructuredCompletionModel).new(
      model,
      output_schema: JSON.parse(%({"title":"old"})),
    )

    typed_request = prompt_agent.prompt_typed(WeatherPayload, "weather")
    payload = typed_request.send
    detailed = typed_request.extended_details.send

    payload.city.should eq("Denver")
    payload.temperature.should eq(72)
    detailed.output.city.should eq("Denver")
    detailed.usage.output_tokens.should eq(4)
    last_request = model.last_request
    last_request.should_not be_nil
    last_request.try(&.output_schema).should_not be_nil
    last_request.try(&.output_schema).try(&.["title"].as_s).should eq("WeatherPayload")
  end
end

describe Crig::DynClientBuilderError, tags: %w[client_builder error] do
  it "builds parity-style dynamic client errors" do
    Crig::DynClientBuilderError.not_found("openai:gpt-4o").message.should eq("Provider 'openai:gpt-4o' not found")
    Crig::DynClientBuilderError.not_capable("openai:gpt-4o", "Completion").message.should eq("Provider 'openai:gpt-4o' cannot be coerced to a 'Completion'")
    Crig::DynClientBuilderError.completion("boom").message.should eq("Error generating response\nboom")
  end
end

describe Crig::DefaultProviders do
  it "formats provider keys like the upstream enum" do
    Crig::DefaultProviders::OpenAI.to_s.should eq("openai")
    Crig::DefaultProviders::HuggingFace.to_s.should eq("huggingface")
    Crig::DefaultProviders.all.size.should be >= 18
  end

  it "builds environment factories for default providers" do
    Crig::DefaultProviders::OpenAI.env_factory.should be_a(Crig::ProviderFactory)
  end
end

describe Crig::AnyClient do
  it "exposes supported dynamic client capabilities" do
    client = Crig::AnyClient.new(FakeCompletionClient.new)

    client.as_completion.should_not be_nil
    client.as_embedding.should be_nil
    client.as_transcription.should be_nil
    client.as_image_generation.should be_nil
    client.as_audio_generation.should be_nil
  end

  it "supports manually composed capability sets" do
    client = Crig::AnyClient.new(
      completion: FakeCompletionClient.new.as(Crig::CompletionClientDyn),
      embeddings: FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn),
      transcription: FakeTranscriptionClient.new.as(Crig::TranscriptionClientDyn),
      image_generation: FakeImageGenerationClient.new.as(Crig::ImageGenerationClientDyn),
      audio_generation: FakeAudioGenerationClient.new.as(Crig::AudioGenerationClientDyn),
    )

    client.as_completion.should_not be_nil
    client.as_embedding.should_not be_nil
    client.as_transcription.should_not be_nil
    client.as_image_generation.should_not be_nil
    client.as_audio_generation.should_not be_nil
  end
end

describe Crig::DynClientBuilder, tags: %w[client_builder dyn] do
  it "registers default provider env factories on construction" do
    builder = Crig::DynClientBuilder.new

    builder.factories.has_key?("openai").should be_true
    builder.factories.has_key?("anthropic").should be_true
  end

  it "registers and looks up provider factories by provider:model key" do
    builder = Crig::DynClientBuilder.new.register("openai", "gpt-4o") do
      Crig::AnyClient.new(FakeCompletionClient.new)
    end

    builder.factory("openai", "gpt-4o").should_not be_nil
    builder.from_env("openai", "gpt-4o").as_completion.should_not be_nil
  end

  it "falls back to provider-level env factories when no model-specific factory exists" do
    builder = Crig::DynClientBuilder.new(
      {"openai" => Crig::ProviderFactory.new(-> { Crig::AnyClient.new(FakeCompletionClient.new) })}
    )

    builder.factory("openai", "gpt-4o").should_not be_nil
    builder.from_env("openai", "gpt-4o").as_completion.should_not be_nil
  end

  it "builds completion agents and models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }

    agent = builder.agent("openai", "gpt-4o").build
    completion = builder.completion("openai", "gpt-4o")

    agent.model.should be_a(Crig::CompletionModelHandle)
    completion.completion_request(Crig::Completion::Message.user("hello")).send(completion).raw_response.should eq("raw:gpt-4o")
  end

  it "builds embedding and transcription models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "text-embedding-3-large") { Crig::AnyClient.new(FakeEmbeddingsClient.new) }
      .register("openai", "whisper-1") { Crig::AnyClient.new(FakeTranscriptionClient.new) }

    builder.embeddings("openai", "text-embedding-3-large").embed_text("hello").document.should eq("text-embedding-3-large:hello")
    builder.transcription("openai", "whisper-1").transcription_request.data(Bytes[1_u8]).send.response.should eq("transcription:whisper-1")
  end

  it "builds image and audio generation models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "dall-e-3") { Crig::AnyClient.new(FakeImageGenerationClient.new) }
      .register("openai", "tts-1") { Crig::AnyClient.new(FakeAudioGenerationClient.new) }

    builder.image_generation("openai", "dall-e-3").image_generation_request
      .prompt("draw")
      .send
      .response
      .should eq("image:dall-e-3")
    builder.audio_generation("openai", "tts-1").audio_generation_request
      .text("say hello")
      .voice("alloy")
      .send
      .response
      .should eq("audio:tts-1")
  end

  it "raises parity-style not-found errors for missing registrations" do
    builder = Crig::DynClientBuilder.new

    expect_raises(Crig::DynClientBuilderError, "Provider 'nonexistent:gpt-4o' not found") do
      builder.from_env("nonexistent", "gpt-4o")
    end
  end

  it "raises parity-style capability errors for unsupported roles" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeEmbeddingsClient.new) }

    expect_raises(Crig::DynClientBuilderError, "Provider 'openai:gpt-4o' cannot be coerced to a 'Completion'") do
      builder.agent("openai", "gpt-4o")
    end
  end

  it "streams explicit completion requests through the registered completion model" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build

    response = builder.stream_completion("openai", "gpt-4o", request)

    response.chunks.should eq(["chunk:gpt-4o"])
    response.response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "streams one-shot prompts through the registered completion model" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }

    response = builder.stream_prompt("openai", "gpt-4o", "hello")

    response.chunks.should eq(["chunk:gpt-4o"])
  end

  it "streams chat history by appending the prompt to the existing messages" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }
    history = [Crig::Completion::Message.user("earlier")]

    response = builder.stream_chat("openai", "gpt-4o", "hello", history)

    response.chunks.should eq(["chunk:gpt-4o"])
  end
end

describe Crig::ClientBuilderError, tags: %w[client_builder error] do
  it "builds parity-style client builder errors" do
    Crig::ClientBuilderError.http_error("boom").message.should eq("reqwest error: boom")
    Crig::ClientBuilderError.invalid_property("base_url").message.should eq("invalid property: base_url")
  end
end

describe Crig::Transport do
  it "exposes the upstream transport variants" do
    Crig::Transport.values.should eq([
      Crig::Transport::Http,
      Crig::Transport::Sse,
      Crig::Transport::NdJson,
    ])
  end
end

describe Crig::BearerAuth do
  it "builds a bearer authorization header" do
    auth = Crig::BearerAuth.new("secret")

    auth.into_header.should eq({"Authorization", "Bearer secret"})
    Crig::BearerAuth.from("token").token.should eq("token")
  end
end

describe Crig::Nothing do
  it "acts like an empty api key and rejects string conversion" do
    Crig::Nothing.new.into_header.should be_nil

    expect_raises(Exception, "Tried to create a Nothing from a string - this should not happen, please file an issue") do
      Crig::Nothing.try_from("oops")
    end
  end
end

describe Crig::Capable(String) do
  it "reports capability support" do
    Crig::Capable(String).new.capable?.should be_true
  end
end

describe Crig::Capability do
  it "supports true and false marker implementations" do
    Crig::Capable(String).new.capable?.should be_true
    Crig::Nothing.new.capable?.should be_false
  end
end

describe Crig::ProviderClient(String) do
  it "supports env and explicit value construction" do
    FakeProviderClient.from_env.source.should eq("env")
    FakeProviderClient.from_val("value").source.should eq("value")
  end
end

describe Crig::Provider(Symbol) do
  it "builds provider uris with and without trailing slashes" do
    provider = FakeProviderExtension.new

    provider.build_uri("https://api.example.com", "/verify", Crig::Transport::Http).should eq("https://api.example.com/verify")
    provider.build_uri("", "/verify", Crig::Transport::Sse).should eq("verify")
  end

  it "supports customizing request builders" do
    provider = FakeProviderExtension.new
    request = Crig::Client::RequestBuilder.new("POST", "https://api.example.com/verify")

    provider.with_custom(request).body_value.should eq("customized")
  end
end

describe Crig::DebugExt do
  it "returns no debug fields by default" do
    DefaultDebugExtExample.new.fields.should eq([] of {String, String})
  end
end

describe Crig::Capabilities do
  it "exposes capability flags on provider capability sets" do
    capabilities = FakeCapabilities.new

    capabilities.completion_capability.should be_true
    capabilities.embeddings_capability.should be_false
    capabilities.transcription_capability.should be_true
  end
end

describe Crig::ProviderBuilder(FakeProviderExtension, Crig::BearerAuth) do
  it "exposes base_url, build, and default finish hooks" do
    builder = FakeProviderBuilder.new
    client_builder = Crig::Client::ClientBuilder(FakeProviderBuilder, Crig::BearerAuth, String).new(
      builder,
      Crig::BearerAuth.new("secret"),
      "https://api.example.com",
      {"X-Test" => "1"},
      "http",
    )

    builder.base_url.should eq("https://api.example.com")
    builder.finish(client_builder).should eq(client_builder)
    builder.build(client_builder).should be_a(FakeProviderExtension)
  end
end

describe Crig::Client::Client(FakeProviderExtension, String) do
  it "builds lightweight clients directly and exposes base_url/ext state" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      headers: {"X-Test" => "1"},
      http_client: "http",
    )

    client.base_url.should eq("https://api.example.com")
    client.headers.should eq({"X-Test" => "1"})
    client.http_client.should eq("http")
    client.ext.should be_a(FakeProviderExtension)
  end

  it "supports deriving a client with a different extension" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      http_client: "http",
    )
    updated = client.with_ext(:updated)

    updated.base_url.should eq("https://api.example.com")
    updated.http_client.should eq("http")
    updated.ext.should eq(:updated)
  end

  it "builds request metadata for post/get and sse helpers" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      headers: {"Authorization" => "Bearer secret"},
      http_client: "http",
    )

    client.post("/chat").body("{}").method.should eq("POST")
    client.post("/chat").uri.should eq("https://api.example.com/chat")
    client.post("/chat").headers.should eq({"Authorization" => "Bearer secret"})
    client.post("/chat").body_value.should eq("customized")
    client.get("/models").method.should eq("GET")
    client.get_sse("/events").uri.should eq("https://api.example.com/events")
    client.post_sse("/stream").uri.should eq("https://api.example.com/stream")
  end
end

describe Crig::Client::ClientBuilder(FakeProviderExtension, Crig::NeedsApiKey, Nil), tags: %w[client_builder] do
  it "supports base_url, headers, and api_key composition before build" do
    builder = Crig::Client::Client.builder(FakeProviderExtension.new)
      .base_url("https://api.example.com")
      .http_headers({"X-Test" => "1"})
      .api_key(Crig::BearerAuth.new("secret"))

    client = builder.build

    client.base_url.should eq("https://api.example.com")
    client.headers.should eq({
      "X-Test"        => "1",
      "Authorization" => "Bearer secret",
    })
  end

  it "supports swapping the http client and exposing the ext builder" do
    builder = Crig::Client::Client.builder(FakeProviderExtension.new)
      .http_client("http-backend")

    builder.ext.should be_a(FakeProviderExtension)
    builder.build.http_client.should eq("http-backend")
  end
end

describe Crig::ModelListingClient, tags: %w[model_listing client] do
  it "lists all models through the client interface" do
    client = FakeModelListingClient.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = client.list_models

    models.len.should eq(2)
    models.data[0].display_name.should eq("GPT-4")
  end

  it "lists all models asynchronously through the client interface" do
    client = FakeModelListingClient.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
    ])

    models = client.list_models_async.receive.unwrap

    models.len.should eq(1)
    models.data[0].display_name.should eq("GPT-4")
  end
end

describe Crig::ModelLister(Array(Crig::ModelInfo)), tags: %w[model_listing lister] do
  it "lists all models through the lister interface" do
    lister = FakeModelLister.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = lister.list_all

    models.len.should eq(2)
    models.data[1].display_name.should eq("GPT-3.5 Turbo")
  end

  it "lists all models asynchronously through the lister interface" do
    lister = FakeModelLister.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
    ])

    models = lister.list_all_async.receive.unwrap

    models.len.should eq(1)
    models.data[0].display_name.should eq("GPT-4")
  end
end

describe Crig::AudioGenerationClient(FakeAudioGenerationClientModel), tags: %w[audio_generation client] do
  it "builds audio generation models through the client interface" do
    client = FakeAudioGenerationClient.new
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    model.name.should eq("tts-1")
    response.response.should eq("audio:tts-1")
    model.last_request.try(&.voice).should eq("alloy")
  end
end

describe Crig::AudioGenerationClientDyn, tags: %w[audio_generation client_dyn] do
  it "builds dynamic audio generation models" do
    client = FakeAudioGenerationClient.new.as(Crig::AudioGenerationClientDyn)
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end
end

describe Crig::AudioGenerationModelHandle, tags: %w[audio_generation model_handle] do
  it "wraps a dynamic model for the request builder" do
    inner = FakeAudioGenerationClientModel.new("tts-1").as(Crig::AudioGenerationModelDyn)
    handle = Crig::AudioGenerationModelHandle.new(inner)
    response = handle.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make an AudioGenerationModelHandle from a client + model identifier") do
      Crig::AudioGenerationModelHandle.make(nil, "tts-1")
    end
  end
end

describe Crig::ImageGenerationClient(FakeImageGenerationClientModel), tags: %w[image_generation client] do
  it "builds image generation models through the client interface" do
    client = FakeImageGenerationClient.new
    model = client.image_generation_model("dall-e-3")
    response = model.image_generation_request.prompt("draw a cat").width(512).height(768).send

    model.name.should eq("dall-e-3")
    response.response.should eq("image:dall-e-3")
    model.last_request.try(&.width).should eq(512)
  end

  it "supports the custom image-generation helper" do
    client = FakeImageGenerationClient.new

    client.custom_image_generation_model("custom-model").name.should eq("custom-model")
  end
end

describe Crig::ImageGenerationClientDyn, tags: %w[image_generation client_dyn] do
  it "builds dynamic image generation models" do
    client = FakeImageGenerationClient.new.as(Crig::ImageGenerationClientDyn)
    model = client.image_generation_model("dall-e-3")
    response = model.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end
end

describe Crig::ImageGenerationModelHandle, tags: %w[image_generation model_handle] do
  it "wraps a dynamic image model for the request builder" do
    inner = FakeImageGenerationClientModel.new("dall-e-3").as(Crig::ImageGenerationModelDyn)
    handle = Crig::ImageGenerationModelHandle.new(inner)
    response = handle.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make an ImageGenerationModelHandle from a client + model identifier") do
      Crig::ImageGenerationModelHandle.make(nil, "dall-e-3")
    end
  end
end

describe Crig::TranscriptionClient(FakeTranscriptionClientModel), tags: %w[transcription client] do
  it "builds transcription models through the client interface" do
    client = FakeTranscriptionClient.new
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send

    model.name.should eq("whisper-1")
    response.response.should eq("transcription:whisper-1")
    model.last_request.try(&.filename).should eq("clip.wav")
  end
end

describe Crig::TranscriptionClientDyn, tags: %w[transcription client_dyn] do
  it "builds dynamic transcription models" do
    client = FakeTranscriptionClient.new.as(Crig::TranscriptionClientDyn)
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
  end
end

describe Crig::TranscriptionModelHandle, tags: %w[transcription model_handle] do
  it "wraps a dynamic transcription model for the request builder" do
    inner = FakeTranscriptionClientModel.new("whisper-1").as(Crig::TranscriptionModelDyn)
    handle = Crig::TranscriptionModelHandle.new(inner)
    response = handle.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make a TranscriptionModelHandle from a client + model identifier") do
      Crig::TranscriptionModelHandle.make(nil, "whisper-1")
    end
  end
end

describe "media generation error helpers" do
  it "exposes audio-generation error variants with source retention" do
    error = Crig::AudioGenerationError.provider_error("audio failed")
    request = Crig::AudioGenerationError.request_error(Exception.new("bad form"))

    error.message.should eq("ProviderError: audio failed")
    error.kind.should eq(Crig::AudioGenerationError::Kind::ProviderError)
    request.kind.should eq(Crig::AudioGenerationError::Kind::RequestError)
    request.source_error.should be_a(Exception)
  end

  it "exposes image-generation error variants with source retention" do
    error = Crig::ImageGenerationError.response_error("bad image")
    json = Crig::ImageGenerationError.json_error(Exception.new("bad json"))

    error.message.should eq("ResponseError: bad image")
    error.kind.should eq(Crig::ImageGenerationError::Kind::ResponseError)
    json.kind.should eq(Crig::ImageGenerationError::Kind::JsonError)
    json.source_error.should be_a(Exception)
  end

  it "exposes transcription error variants with source retention" do
    error = Crig::TranscriptionError.http_error(Exception.new("timeout"))
    provider = Crig::TranscriptionError.provider_error("unavailable")

    error.message.should eq("HttpError: timeout")
    error.kind.should eq(Crig::TranscriptionError::Kind::HttpError)
    error.source_error.should be_a(Exception)
    provider.kind.should eq(Crig::TranscriptionError::Kind::ProviderError)
  end
end

describe Crig::Concurrency do
  it "captures successful fiber results" do
    result = Crig::Concurrency.run { 42 }.receive

    result.success?.should be_true
    result.unwrap.should eq(42)
  end

  it "captures raised exceptions for later unwrap" do
    result = Crig::Concurrency.run do
      raise Crig::TranscriptionError.new("boom")
    end.receive

    result.failure?.should be_true
    expect_raises(Crig::TranscriptionError, "boom") do
      result.unwrap
    end
  end
end

describe "channel-based model execution" do
  it "supports async completion sends" do
    model = FakeCompletionModel.new
    result = model.completion_request("hello").send_async(model).receive

    result.unwrap.raw_response.should eq("raw")
    request = model.last_request
    request.should_not be_nil
    request.try(&.chat_history.last.role.to_s).should eq("User")
  end

  it "supports async completion streams" do
    model = FakeCompletionModel.new
    result = model.completion_request("hello").stream_async(model).receive

    result.unwrap.should eq(["streamed"])
  end

  it "supports async audio generation sends" do
    model = FakeAudioGenerationModel.new
    result = model.audio_generation_request.text("hello").voice("alloy").send_async.receive

    result.unwrap.response.should eq("raw-audio")
  end

  it "supports async image generation sends" do
    model = FakeImageGenerationModel.new
    result = model.image_generation_request.prompt("draw a cat").send_async.receive

    result.unwrap.response.should eq("raw-image")
  end

  it "supports async transcription sends" do
    model = FakeTranscriptionModel.new
    result = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send_async.receive

    result.unwrap.response.should eq("raw-transcription")
  end

  it "surfaces async transcription failures through the channel result" do
    model = FailingTranscriptionModel.new
    result = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send_async.receive

    expect_raises(Crig::TranscriptionError, "provider unavailable for clip.wav") do
      result.unwrap
    end
  end
end

describe Crig::OneOrMany do
  it "builds a single item" do
    one_or_many = Crig::OneOrMany(String).one("hello")

    one_or_many.to_a.should eq(["hello"])
    one_or_many.len.should eq(1)
    one_or_many.empty?.should be_false
    one_or_many.is_empty.should be_false
    one_or_many.first.should eq("hello")
  end

  it "builds many items and preserves order" do
    one_or_many = Crig::OneOrMany(String).many(["hello", "world"])

    one_or_many.to_a.should eq(["hello", "world"])
    one_or_many.rest.should eq(["world"])
    one_or_many.last.should eq("world")
  end

  it "exposes rust-named first and last accessors" do
    one_or_many = Crig::OneOrMany(String).many(["hello", "world"])

    one_or_many.first_ref.should eq("hello")
    one_or_many.first_mut.should eq("hello")
    one_or_many.last_ref.should eq("world")
    one_or_many.last_mut.should eq("world")
  end

  it "merges multiple values" do
    merged = Crig::OneOrMany(String).merge([
      Crig::OneOrMany(String).many(["hello", "world"]),
      Crig::OneOrMany(String).one("sup"),
    ])

    merged.to_a.should eq(["hello", "world", "sup"])
  end

  it "supports push and insert" do
    one_or_many = Crig::OneOrMany(String).one("world")
    one_or_many.insert(0, "hello")
    one_or_many.push("sup")

    one_or_many.to_a.should eq(["hello", "world", "sup"])
  end

  it "supports owned iteration for a single item" do
    one_or_many = Crig::OneOrMany(String).one("hello")

    one_or_many.into_iter.to_a.should eq(["hello"])
  end

  it "supports owned iteration for multiple items" do
    one_or_many = Crig::OneOrMany(String).many(["hello", "world"])

    one_or_many.into_iter.to_a.should eq(["hello", "world"])
  end

  it "supports mutable-style iteration for a single item" do
    one_or_many = Crig::OneOrMany(MutableOneOrManyValue).one(MutableOneOrManyValue.new("hello"))

    one_or_many.iter_mut.each do |item|
      item.value = "#{item.value} world"
    end

    one_or_many.first.value.should eq("hello world")
  end

  it "supports mutable-style iteration for multiple reference items" do
    one_or_many = Crig::OneOrMany(MutableOneOrManyValue).many([
      MutableOneOrManyValue.new("hello"),
      MutableOneOrManyValue.new("world"),
    ])

    one_or_many.iter_mut.each_with_index do |item, index|
      item.value = "#{item.value} world" if index == 0
    end

    one_or_many.to_a.map(&.value).should eq(["hello world", "world"])
  end

  it "reports iterator size hints" do
    one = Crig::OneOrMany(String).one("bar")
    many = Crig::OneOrMany(String).many(["foo", "bar", "baz"])

    one.iter.size_hint.should eq({1, 1})
    many.iter.size_hint.should eq({1, 3})
    many.into_iter.size_hint.should eq({1, 3})
    many.iter_mut.size_hint.should eq({1, 3})
  end

  it "deserializes arrays into one-or-many values" do
    one_or_many = Crig::OneOrMany(Int32).from_json("[1,2,3]")

    one_or_many.len.should eq(3)
    one_or_many.first.should eq(1)
    one_or_many.rest.should eq([2, 3])
  end

  it "deserializes arrays of maps into one-or-many values" do
    one_or_many = Crig::OneOrMany(JSON::Any).from_json(%([{"key":"value1"},{"key":"value2"}]))

    one_or_many.len.should eq(2)
    one_or_many.first.should eq(JSON.parse(%({"key":"value1"})))
    one_or_many.rest.should eq([JSON.parse(%({"key":"value2"}))])
  end

  it "deserializes string-or-many fields from a string" do
    dummy = DummyOneOrManyStruct.from_json(%({"field":"hello"}))

    dummy.field.len.should eq(1)
    dummy.field.first.should eq(DummyOneOrManyString.new("hello"))
  end

  it "deserializes optional string-or-many fields from a string" do
    dummy = DummyOneOrManyStructOption.from_json(%({"field":"hello"}))

    dummy.field.should_not be_nil
    field = dummy.field.not_nil!
    field.len.should eq(1)
    field.first.should eq(DummyOneOrManyString.new("hello"))
  end

  it "deserializes optional string-or-many fields from a list" do
    dummy = DummyOneOrManyStructOption.from_json(%({"field":[{"string":"hello"},{"string":"world"}]}))

    dummy.field.should_not be_nil
    field = dummy.field.not_nil!
    field.len.should eq(2)
    field.first.should eq(DummyOneOrManyString.new("hello"))
    field.rest.should eq([DummyOneOrManyString.new("world")])
  end

  it "deserializes optional string-or-many fields from null" do
    dummy = DummyOneOrManyStructOption.from_json(%({"field":null}))

    dummy.field.should be_nil
  end

  it "deserializes null content through the optional converter" do
    dummy = DummyOneOrManyMessage.from_json(%({"role":"assistant","content":null}))

    dummy.role.should eq("assistant")
    dummy.content.should be_nil
  end

  it "rejects empty collections" do
    expect_raises(Crig::EmptyListError, "Cannot create OneOrMany with an empty vector.") do
      Crig::OneOrMany(String).many([] of String)
    end
  end
end

describe Crig::Embeddings do
  it "wraps embed errors with the original message" do
    Crig::Embeddings::EmbedError.new(Exception.new("boom")).message.should eq("boom")
  end

  it "builds parity-style embedding errors" do
    http = Crig::Embeddings::EmbeddingError.http_error(Exception.new("timeout"))
    http.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::HttpError)
    http.message.should eq("HttpError: timeout")
    http.source_error.try(&.message).should eq("timeout")

    json = Crig::Embeddings::EmbeddingError.json_error(Exception.new("bad json"))
    json.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::JsonError)
    json.message.should eq("JsonError: bad json")

    url = Crig::Embeddings::EmbeddingError.url_error(Exception.new("bad url"))
    url.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::UrlError)
    url.message.should eq("UrlError: bad url")

    document = Crig::Embeddings::EmbeddingError.document_error(Exception.new("bad document"))
    document.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::DocumentError)
    document.message.should eq("DocumentError: bad document")

    response = Crig::Embeddings::EmbeddingError.response_error("missing vector")
    response.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::ResponseError)
    response.message.should eq("ResponseError: missing vector")

    provider = Crig::Embeddings::EmbeddingError.provider_error("rate limited")
    provider.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::ProviderError)
    provider.message.should eq("ProviderError: rate limited")
  end

  it "collects texts from embeddable values" do
    Crig::Embeddings.to_texts(ExampleEmbedding.new(["hello", "world"])).should eq(["hello", "world"])
  end

  it "wraps embed failures as embed errors during text extraction" do
    error = expect_raises(Crig::Embeddings::EmbedError, "embed exploded") do
      Crig::Embeddings.to_texts(FailingExampleEmbedding.new)
    end

    error.message.should eq("embed exploded")
  end

  it "ports test_custom_embed" do
    definition = DerivedWordDefinitionCustom.new(
      "doc1",
      "house",
      DerivedDefinition.new(
        "a building in which people live; residence for human beings.",
        "https://www.dictionary.com/browse/house",
        "noun"
      )
    )

    Crig::Embeddings.to_texts(definition).should eq([
      %({"word":"a building in which people live; residence for human beings.","link":"https://www.dictionary.com/browse/house","speech":"noun"}),
    ])
  end

  it "ports test_custom_and_basic_embed" do
    definition = DerivedWordDefinitionCustomAndBasic.new(
      "doc1",
      "house",
      DerivedDefinition.new(
        "a building in which people live; residence for human beings.",
        "https://www.dictionary.com/browse/house",
        "noun"
      )
    )

    Crig::Embeddings.to_texts(definition).should eq([
      "house",
      %({"word":"a building in which people live; residence for human beings.","link":"https://www.dictionary.com/browse/house","speech":"noun"}),
    ])
  end

  it "ports test_single_embed" do
    definition = "a building in which people live; residence for human beings."
    word_definition = DerivedWordDefinitionSingle.new("doc1", "house", definition)

    Crig::Embeddings.to_texts(word_definition).should eq([definition])
  end

  it "ports test_embed_vec_non_string" do
    company = DerivedCompanyAges.new("doc1", "Google", [25, 30, 35, 40])

    Crig::Embeddings.to_texts(company).should eq(["25", "30", "35", "40"])
  end

  it "ports test_embed_vec_string" do
    company = DerivedCompanyNames.new("doc1", "Google", ["Alice", "Bob", "Charlie", "David"])

    Crig::Embeddings.to_texts(company).should eq(["Alice", "Bob", "Charlie", "David"])
  end

  it "ports test_multiple_embed_tags" do
    company = DerivedCompanyMultiple.new("doc1", "Google", [25, 30, 35, 40])

    Crig::Embeddings.to_texts(company).should eq(["Google", "25", "30", "35", "40"])
  end

  it "collects texts from primitives" do
    Crig::Embeddings.to_texts(42).should eq(["42"])
    Crig::Embeddings.to_texts(true).should eq(["true"])
  end

  it "collects texts from json and hash-like values" do
    json = JSON.parse(%({"hello":"world"}))

    Crig::Embeddings.to_texts(json).should eq([%({"hello":"world"})])
    Crig::Embeddings.to_texts({"hello" => "world"}).should eq([%({"hello":"world"})])
    Crig::Embeddings.to_texts({"hello", 42}).should eq(["hello", "42"])
  end

  it "stores embeddings and compares them by document" do
    left = Crig::Embeddings::Embedding.new("doc", [1.0, 2.0])
    right = Crig::Embeddings::Embedding.new("doc", [9.0])

    left.should eq(right)
    left.vec.should eq([1.0, 2.0])
  end

  it "supports single-text embedding through the model helper" do
    embedding = FakeEmbeddingModel.new.embed_text("hello")

    embedding.document.should eq("hello")
    embedding.vec.should eq([5.0, 0.0, 1.0])
  end

  it "supports single-image embedding through the image model helper" do
    embedding = FakeImageEmbeddingModel.new.embed_image(Bytes[1_u8, 2_u8, 3_u8])

    embedding.document.should eq("image:3")
    embedding.vec.should eq([3.0, 1.0])
  end

  it "computes dot product" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.dot_product(embedding_2).should eq(32.0)
  end

  it "computes cosine similarity" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.cosine_similarity(embedding_2, false).should eq(0.9875414397573881)
  end

  it "computes angular distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.angular_distance(embedding_2, false).should eq(0.0502980301830343)
  end

  it "computes euclidean distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.euclidean_distance(embedding_2).should eq(5.0)
  end

  it "computes manhattan distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.manhattan_distance(embedding_2).should eq(7.0)
  end

  it "computes chebyshev distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.chebyshev_distance(embedding_2).should eq(4.0)
  end

  it "builds a tool schema from a dynamic tool embedding" do
    schema = Crig::Embeddings::ToolSchema.try_from(FakeToolEmbedding.new)

    schema.name.should eq("nothing")
    schema.context["category"].as_s.should eq("utility")
    schema.embedding_docs.should eq(["Do nothing."])
    Crig::Embeddings.to_texts(schema).should eq(["Do nothing."])
  end

  it "builds embeddings for a single document" do
    results = Crig::Embeddings::EmbeddingsBuilder(FakeEmbeddingModel, ExampleMultiEmbedding)
      .new(FakeEmbeddingModel.new)
      .document(ExampleMultiEmbedding.new("doc0", ["alpha", "beta"]))
      .build

    results.size.should eq(1)
    results[0][0].id.should eq("doc0")
    results[0][1].to_a.map(&.document).should eq(["alpha", "beta"])
  end

  it "wraps embed failures as embed errors during builder document collection" do
    expect_raises(Crig::Embeddings::EmbedError, "embed exploded") do
      Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
        .document(FailingExampleEmbedding.new)
    end
  end

  it "builds embeddings from chained simple documents" do
    results = Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
      .simple_document("doc0", "alpha")
      .simple_document("doc1", "beta")
      .build

    results.map(&.[0].id).should eq(["doc0", "doc1"])
    results.map { |entry| entry[1].first.document }.should eq(["alpha", "beta"])
  end

  it "builds embeddings from all simple documents at once" do
    results = Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
      .all_simple_documents([{"doc0", "alpha"}, {"doc1", "beta"}])
      .build

    results.map(&.[0].id).should eq(["doc0", "doc1"])
    results.map { |entry| entry[1].first.document }.should eq(["alpha", "beta"])
  end

  it "builds embeddings for one or many documents" do
    results = Crig::Embeddings::EmbeddingsBuilder(FakeEmbeddingModel, ExampleMultiEmbedding)
      .new(FakeEmbeddingModel.new)
      .documents([
        ExampleMultiEmbedding.new("doc0", ["alpha", "beta"]),
        ExampleMultiEmbedding.new("doc1", ["gamma"]),
      ])
      .build

    results.size.should eq(2)
    results[0][0].id.should eq("doc0")
    results[0][1].to_a.map(&.document).should eq(["alpha", "beta"])
    results[1][0].id.should eq("doc1")
    results[1][1].to_a.map(&.document).should eq(["gamma"])
  end
end

describe Crig::EvalOutcome, tags: %w[evals] do
  it "tracks pass, fail, and invalid states" do
    pass_outcome = Crig::EvalOutcome(Crig::SemanticSimilarityMetricScore).pass(
      Crig::SemanticSimilarityMetricScore.new(0.95)
    )
    fail_outcome = Crig::EvalOutcome(Crig::SemanticSimilarityMetricScore).fail(
      Crig::SemanticSimilarityMetricScore.new(0.12)
    )
    invalid_outcome = Crig::EvalOutcome(Crig::SemanticSimilarityMetricScore).invalid("network error")

    pass_outcome.is_pass.should be_true
    pass_score = pass_outcome.score
    pass_score.should_not be_nil
    pass_score.as(Crig::SemanticSimilarityMetricScore).score.should eq(0.95)
    fail_outcome.is_pass.should be_false
    fail_score = fail_outcome.score
    fail_score.should_not be_nil
    fail_score.as(Crig::SemanticSimilarityMetricScore).score.should eq(0.12)
    invalid_outcome.score.should be_nil
    invalid_outcome.reason.should eq("network error")
  end

  it "round-trips tagged json payloads" do
    outcome = Crig::EvalOutcome(Crig::SemanticSimilarityMetricScore).pass(
      Crig::SemanticSimilarityMetricScore.new(0.81)
    )

    roundtrip = Crig::EvalOutcome(Crig::SemanticSimilarityMetricScore).from_json(outcome.to_json)

    roundtrip.kind.pass?.should be_true
    score = roundtrip.score
    score.should_not be_nil
    score.as(Crig::SemanticSimilarityMetricScore).score.should eq(0.81)
  end
end

describe Crig::SemanticSimilarityMetricBuilder do
  it "requires threshold and reference answer" do
    expect_raises(Crig::EvalError, "Field must not be null: threshold") do
      Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .reference_answer("hello")
        .build
    end

    expect_raises(Crig::EvalError, "Field must not be null: reference_answer") do
      Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .threshold(0.5)
        .build
    end
  end

  it "builds a metric with a precomputed reference embedding" do
    metric = Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
      .threshold(0.8)
      .reference_answer("hello")
      .build

    metric.reference_answer.should eq("hello")
    metric.reference_answer_embedding.document.should eq("hello")
  end

  it "wraps embedding build failures as eval errors" do
    expect_raises(Crig::EvalError, "Eval error: embedding provider unavailable for hello") do
      Crig::SemanticSimilarityMetric.builder(FailingEmbeddingModel.new)
        .threshold(0.5)
        .reference_answer("hello")
        .build
    end
  end
end

describe Crig::SemanticSimilarityMetric, tags: %w[evals semantic] do
  it "passes when cosine similarity clears the threshold" do
    metric = Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
      .threshold(0.99)
      .reference_answer("hello")
      .build

    outcome = metric.eval("helloo")

    outcome.kind.pass?.should be_true
    outcome.is_pass.should be_true
    score = outcome.score
    score.should_not be_nil
    score.as(Crig::SemanticSimilarityMetricScore).score.should be >= 0.99
  end

  it "fails when cosine similarity is below the threshold" do
    metric = Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
      .threshold(0.9999)
      .reference_answer("hello")
      .build

    outcome = metric.eval("a")

    outcome.kind.fail?.should be_true
    score = outcome.score
    score.should_not be_nil
    score.as(Crig::SemanticSimilarityMetricScore).score.should be < 0.9999
  end

  it "returns invalid when embedding the input fails" do
    metric = Crig::SemanticSimilarityMetric(FailingEmbeddingModel).new(
      FailingEmbeddingModel.new,
      0.5,
      "hello",
      Crig::Embeddings::Embedding.new("hello", [1.0, 0.0, 1.0])
    )

    outcome = metric.eval("world")

    outcome.kind.invalid?.should be_true
    outcome.reason.should eq("embedding provider unavailable for world")
  end

  it "evaluates batches synchronously through the eval protocol" do
    metric = Crig::SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
      .threshold(0.99)
      .reference_answer("hello")
      .build

    outcomes = metric.eval_batch(["hello", "a"], 4)

    outcomes.size.should eq(2)
    outcomes[0].kind.pass?.should be_true
    outcomes[1].kind.fail?.should be_true
  end
end

describe Crig::LlmJudgeBuilder do
  it "builds a judgment metric using the extractor runtime" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeMetricModel
        include Crig::Completion::CompletionModel

        getter last_request : Crig::Completion::Request::CompletionRequest?

        def initialize(@json : String)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(@json),
              )
            ),
            Crig::Completion::Usage.new,
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      struct ProbeMetricJudgment
        include JSON::Serializable
        include Crig::Judgment

        getter verdict : Bool
        getter explanation : String

        def initialize(@verdict : Bool, @explanation : String)
        end

        def passes : Bool
          @verdict
        end
      end

      model = ProbeMetricModel.new(%({"verdict":true,"explanation":"looks good"}))
      builder = Crig::LlmJudgeBuilder(ProbeMetricModel, ProbeMetricJudgment).new(
        Crig::ExtractorBuilder(ProbeMetricModel, ProbeMetricJudgment).new(model)
      )
      outcome = builder.build.eval("judge this")

      puts(JSON.build do |json|
        json.object do
          json.field "kind", outcome.kind.to_s
          json.field "explanation", outcome.output.not_nil!.explanation
          json.field "preamble", model.last_request.not_nil!.preamble
        end
      end)
    CRYSTAL

    result["kind"].as_s.should eq("Pass")
    result["explanation"].as_s.should eq("looks good")
    result["preamble"].as_s.includes?("Judge the prompt input by the schema given").should be_true
  end

  it "supports custom evaluator functions" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeMetricModel
        include Crig::Completion::CompletionModel

        def initialize(@json : String)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(@json),
              )
            ),
            Crig::Completion::Usage.new,
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      struct ProbeMetricJudgment
        include JSON::Serializable
        include Crig::Judgment

        getter verdict : Bool
        getter explanation : String

        def initialize(@verdict : Bool, @explanation : String)
        end

        def passes : Bool
          @verdict
        end
      end

      model = ProbeMetricModel.new(%({"verdict":false,"explanation":"close enough"}))
      metric = Crig::LlmJudgeBuilder(ProbeMetricModel, ProbeMetricJudgment).new(
        Crig::ExtractorBuilder(ProbeMetricModel, ProbeMetricJudgment).new(model)
      ).with_fn { |judgment| judgment.explanation.includes?("close") }.build
      outcome = metric.eval("judge this")

      puts(JSON.build do |json|
        json.object do
          json.field "kind", outcome.kind.to_s
        end
      end)
    CRYSTAL

    result["kind"].as_s.should eq("Pass")
  end
end

describe Crig::LlmScoreMetricBuilder do
  it "requires a threshold before building" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeMetricModel
        include Crig::Completion::CompletionModel

        def initialize(@json : String)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(@json),
              )
            ),
            Crig::Completion::Usage.new,
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      begin
        Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
          Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(
            ProbeMetricModel.new(%({"score":0.9,"feedback":"great"}))
          )
        ).build
      rescue ex : Crig::EvalError
        puts(JSON.build do |json|
          json.object do
            json.field "kind", ex.kind.to_s
            json.field "message", ex.message
          end
        end)
      end
    CRYSTAL

    result["kind"].as_s.should eq("FieldCannotBeNull")
    result["message"].as_s.should eq("Field must not be null: threshold")
  end

  it "builds a scoring metric and applies threshold/preamble rules" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeMetricModel
        include Crig::Completion::CompletionModel

        getter last_request : Crig::Completion::Request::CompletionRequest?

        def initialize(@json : String)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(@json),
              )
            ),
            Crig::Completion::Usage.new,
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeMetricModel.new(%({"score":0.9,"feedback":"great"}))
      metric = Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
        Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(model)
      ).criteria("Be correct")
        .criteria("Be concise")
        .threshold(0.8)
        .build
      outcome = metric.eval("score this")

      puts(JSON.build do |json|
        json.object do
          json.field "kind", outcome.kind.to_s
          json.field "feedback", outcome.output.not_nil!.feedback
          json.field "preamble", model.last_request.not_nil!.preamble
        end
      end)
    CRYSTAL

    result["kind"].as_s.should eq("Pass")
    result["feedback"].as_s.should eq("great")
    result["preamble"].as_s.includes?("Be correct").should be_true
    result["preamble"].as_s.includes?("Be concise").should be_true
  end

  it "invalidates out-of-range scores" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeMetricModel
        include Crig::Completion::CompletionModel

        def initialize(@json : String)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(@json),
              )
            ),
            Crig::Completion::Usage.new,
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      metric = Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
        Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(
          ProbeMetricModel.new(%({"score":1.5,"feedback":"bad range"}))
        )
      ).threshold(0.5)
        .build
      outcome = metric.eval("score this")

      puts(JSON.build do |json|
        json.object do
          json.field "kind", outcome.kind.to_s
          json.field "reason", outcome.reason
        end
      end)
    CRYSTAL

    result["kind"].as_s.should eq("Invalid")
    result["reason"].as_s.should eq("Score 1.5 outside valid range [0.0, 1.0]")
  end
end

describe Crig::ExtractionResponse do
  it "stores extracted data with usage" do
    response = Crig::ExtractionResponse(String).new(
      "hello",
      Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2)
    )

    response.data.should eq("hello")
    response.usage.input_tokens.should eq(1)
    response.usage.output_tokens.should eq(2)
  end
end

describe Crig::Extractor(FakeStructuredCompletionModel, WeatherPayload) do
  it "extracts payloads through the submit tool path" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct WeatherPayload
        include JSON::Serializable

        getter city : String
        getter temperature : Int32

        def initialize(@city : String, @temperature : Int32)
        end
      end

      class ProbeStructuredModel
        include Crig::Completion::CompletionModel

        getter last_request : Crig::Completion::Request::CompletionRequest?

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(%({"city":"Denver","temperature":72})),
              )
            ),
            Crig::Completion::Usage.new(output_tokens: 4),
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeStructuredModel.new
      agent = Crig::AgentBuilder(ProbeStructuredModel).new(model)
        .tool(Crig::ExtractorSubmitTool(WeatherPayload).new)
        .tool_choice(Crig::Completion::ToolChoice.required)
        .build
      payload = Crig::Extractor(ProbeStructuredModel, WeatherPayload).new(agent).extract("weather")

      puts(JSON.build do |json|
        json.object do
          json.field "city", payload.city
          json.field "temperature", payload.temperature
          json.field "tools" do
            json.array do
              model.last_request.not_nil!.tools.each do |tool|
                json.string(tool.name)
              end
            end
          end
        end
      end)
    CRYSTAL

    result["city"].as_s.should eq("Denver")
    result["temperature"].as_i.should eq(72)
    result["tools"].as_a.map(&.as_s).should contain("submit")
  end

  it "returns extracted data with usage" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct WeatherPayload
        include JSON::Serializable

        getter city : String
        getter temperature : Int32

        def initialize(@city : String, @temperature : Int32)
        end
      end

      class ProbeStructuredModel
        include Crig::Completion::CompletionModel

        def completion(request : Crig::Completion::Request::CompletionRequest)
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(%({"city":"Denver","temperature":72})),
              )
            ),
            Crig::Completion::Usage.new(output_tokens: 4),
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeStructuredModel.new
      agent = Crig::AgentBuilder(ProbeStructuredModel).new(model)
        .tool(Crig::ExtractorSubmitTool(WeatherPayload).new)
        .tool_choice(Crig::Completion::ToolChoice.required)
        .build
      response = Crig::Extractor(ProbeStructuredModel, WeatherPayload).new(agent).extract_with_usage("weather")

      puts(JSON.build do |json|
        json.object do
          json.field "city", response.data.city
          json.field "output_tokens", response.usage.output_tokens
        end
      end)
    CRYSTAL

    result["city"].as_s.should eq("Denver")
    result["output_tokens"].as_i.should eq(4)
  end

  it "forwards chat history into the completion request" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct WeatherPayload
        include JSON::Serializable

        getter city : String
        getter temperature : Int32

        def initialize(@city : String, @temperature : Int32)
        end
      end

      class ProbeStructuredModel
        include Crig::Completion::CompletionModel

        getter last_request : Crig::Completion::Request::CompletionRequest?

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(%({"city":"Denver","temperature":72})),
              )
            ),
            Crig::Completion::Usage.new(output_tokens: 4),
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeStructuredModel.new
      agent = Crig::AgentBuilder(ProbeStructuredModel).new(model)
        .tool(Crig::ExtractorSubmitTool(WeatherPayload).new)
        .tool_choice(Crig::Completion::ToolChoice.required)
        .build
      extractor = Crig::Extractor(ProbeStructuredModel, WeatherPayload).new(agent)
      history = [Crig::Completion::Message.assistant("Earlier answer")]

      extractor.extract_with_chat_history("weather", history)

      puts(JSON.build do |json|
        json.object do
          json.field "roles" do
            json.array do
              model.last_request.not_nil!.chat_history.each do |message|
                json.string(message.role.to_s)
              end
            end
          end
          json.field "texts" do
            json.array do
              model.last_request.not_nil!.chat_history.each do |message|
                text = message.content.to_a.compact_map do |item|
                  if item.is_a?(Crig::Completion::UserContent) && item.kind.text?
                    item.text.try(&.text)
                  elsif item.is_a?(Crig::Completion::AssistantContent) && item.kind.text?
                    item.text.try(&.text)
                  end
                end.first? || ""
                json.string(text)
              end
            end
          end
        end
      end)
    CRYSTAL

    result["roles"].as_a.map(&.as_s).should eq(["Assistant", "User"])
    result["texts"].as_a.first.as_s.includes?("Earlier answer").should be_true
    result["texts"].as_a.last.as_s.includes?("weather").should be_true
  end
end

describe Crig::ExtractorBuilder(FakeStructuredCompletionModel, WeatherPayload) do
  it "forwards defaults, builder settings, and dynamic context into the built extractor" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct ProbeWeatherPayload
        include JSON::Serializable

        getter city : String
        getter temperature : Int32

        def initialize(@city : String, @temperature : Int32)
        end
      end

      struct ProbeStoredDoc
        include JSON::Serializable

        getter id : String
        getter name : String

        def initialize(@id : String, @name : String)
        end
      end

      class ProbeStructuredCompletionModel
        include Crig::Completion::CompletionModel

        def completion(request : Crig::Completion::Request::CompletionRequest)
          submit_tool = request.tools.find { |tool| tool.name == "submit" }
          choice = if submit_tool
                     Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                       Crig::Completion::AssistantContent.tool_call(
                         "tool_call_submit",
                         "submit",
                         JSON.parse(%({"city":"Denver","temperature":72})),
                       )
                     )
                   else
                     Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                       Crig::Completion::AssistantContent.text(%({"city":"Denver","temperature":72}))
                     )
                   end

          Crig::Completion::CompletionResponse(String).new(
            choice,
            Crig::Completion::Usage.new(output_tokens: 4),
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          _ = request
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      class ProbeEmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        def max_documents : Int32
          2
        end

        def ndims : Int32
          1
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          texts.map { |text| Crig::Embeddings::Embedding.new("embed:#{text}", [1.0]) }.to_a
        end
      end

      def vector_embedding(document : String, values : Array(Float64)) : Crig::OneOrMany(Crig::Embeddings::Embedding)
        Crig::OneOrMany(Crig::Embeddings::Embedding).one(Crig::Embeddings::Embedding.new(document, values))
      end

      model = ProbeStructuredCompletionModel.new
      embedding_model = ProbeEmbeddingModel.new
      store = Crig::InMemoryVectorStore(ProbeStoredDoc).from_documents_with_ids([
        {
          "doc-1",
          ProbeStoredDoc.new("doc-1", "Denver"),
          vector_embedding("Denver weather", [1.0]),
        },
      ])
      index = store.index(embedding_model)
      request = Crig::VectorSearchRequest.new("weather", 1_u64)

      extractor = Crig::ExtractorBuilder(ProbeStructuredCompletionModel, ProbeWeatherPayload).new(model)
        .preamble("Only extract weather.")
        .context("Denver forecast")
        .additional_params(JSON.parse(%({"mode":"strict"})))
        .max_tokens(128)
        .tool_choice(Crig::Completion::ToolChoice.auto)
        .dynamic_context(1, index)
        .retries(2)
        .build

      puts(JSON.build do |json|
        json.object do
          json.field "retries", extractor.retries
          json.field "preamble", extractor.agent.preamble
          json.field "static_context" do
            json.array do
              extractor.agent.static_context.each { |doc| json.string(doc.text) }
            end
          end
          json.field "mode", extractor.agent.additional_params.try(&.["mode"].as_s)
          json.field "max_tokens", extractor.agent.max_tokens
          json.field "tool_choice_auto", extractor.agent.tool_choice == Crig::Completion::ToolChoice.auto
          json.field "static_tools" do
            json.array do
              extractor.agent.static_tools.each { |tool| json.string(tool.name) }
            end
          end
          json.field "has_tool_server", !extractor.agent.tool_server_handle.nil?
          json.field "dynamic_context_size", extractor.agent.dynamic_context.size
          json.field "first_dynamic_doc_id", extractor.agent.dynamic_context.first.search(request).first[1]
        end
      end)
    CRYSTAL

    result["retries"].as_i.should eq(2)
    result["preamble"].as_s.includes?(Crig::EXTRACTOR_PREAMBLE).should be_true
    result["preamble"].as_s.includes?("ADDITIONAL INSTRUCTIONS").should be_true
    result["static_context"].as_a.map(&.as_s).should eq(["Denver forecast"])
    result["mode"].as_s.should eq("strict")
    result["max_tokens"].as_i64.should eq(128)
    result["tool_choice_auto"].as_bool.should be_true
    result["static_tools"].as_a.map(&.as_s).should contain("submit")
    result["has_tool_server"].as_bool.should be_true
    result["dynamic_context_size"].as_i.should eq(1)
    result["first_dynamic_doc_id"].as_s.should eq("doc-1")
  end
end

describe Crig::ExtractionResponse(WeatherPayload) do
  it "stores extracted data and usage" do
    response = Crig::ExtractionResponse(WeatherPayload).new(
      WeatherPayload.new("Denver", 72),
      Crig::Completion::Usage.new(total_tokens: 4),
    )

    response.data.city.should eq("Denver")
    response.usage.total_tokens.should eq(4)
  end
end

describe Crig::ExtractionError do
  it "builds the parity-style no-data helper" do
    Crig::ExtractionError.no_data.message.should eq("No data extracted")
  end
end

describe Crig::Pipeline::AgentOps do
  it "looks up typed documents from an index" do
    lookup = Crig::Pipeline::AgentOps.lookup(PipelineMockIndex.new, 1, PipelineFoo)

    result = lookup.call("query").unwrap

    result.should eq([{1.0, "doc1", PipelineFoo.new("bar")}])
  end

  it "prompts through the prompt adapter" do
    prompt = Crig::Pipeline::AgentOps.prompt(PipelineMockModel.new, String)

    prompt.call("hello").unwrap.should eq("Mock response: hello")
  end

  it "prompts through agent instances using the same adapter" do
    model = FakeCompletionClientModel.new("gpt-4")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    prompt = Crig::Pipeline::AgentOps.prompt(agent, String)

    prompt.call("hello").unwrap.should eq("completion:gpt-4")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq("hello")
  end

  it "extracts structured output through the extractor adapter" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      struct WeatherPayload
        include JSON::Serializable

        getter city : String
        getter temperature : Int32

        def initialize(@city : String, @temperature : Int32)
        end
      end

      class ProbeStructuredModel
        include Crig::Completion::CompletionModel

        def completion(request : Crig::Completion::Request::CompletionRequest)
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.tool_call(
                "tool_call_submit",
                "submit",
                JSON.parse(%({"city":"Denver","temperature":72})),
              )
            ),
            Crig::Completion::Usage.new(output_tokens: 4),
            "raw",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          ["streamed"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      extractor = Crig::ExtractorBuilder(ProbeStructuredModel, WeatherPayload).new(
        ProbeStructuredModel.new
      ).build
      result = Crig::Pipeline::AgentOps.extract(extractor, String).call("weather").unwrap

      puts(JSON.build do |json|
        json.object do
          json.field "city", result.city
          json.field "temperature", result.temperature
        end
      end)
    CRYSTAL

    result["city"].as_s.should eq("Denver")
    result["temperature"].as_i.should eq(72)
  end
end

describe Crig::Pipeline do
  it "builds prompt pipelines from the root builder" do
    pipeline = Crig::Pipeline.new
      .map(->(input : String) { "User query: #{input}" })
      .prompt(PipelineMockModel.new)

    pipeline.call("What is a flurbo?").unwrap.should eq("Mock response: User query: What is a flurbo?")
  end

  it "supports explicit error builders with try_call" do
    pipeline = Crig::Pipeline.with_error(Nil)
      .map(->(input : String) { "User query: #{input}" })
      .prompt(PipelineMockModel.new)

    pipeline.try_call("What is a flurbo?").unwrap.should eq("Mock response: User query: What is a flurbo?")
  end

  it "supports lookup pipelines with map_ok" do
    pipeline = Crig::Pipeline.new
      .lookup(PipelineMockIndex.new, 1, PipelineFoo)
      .map_ok(->(docs : Array(Tuple(Float64, String, PipelineFoo))) { "Top documents:\n#{docs[0][2].foo}" })

    pipeline.try_call("What is a flurbo?").unwrap.should eq("Top documents:\nbar")
  end

  it "supports rag-style pipelines with parallel ops" do
    pipeline = Crig::Pipeline.new
      .chain(
        Crig::Pipeline.parallel(
          Crig::Pipeline::Passthrough(String).new,
          Crig::Pipeline::AgentOps.lookup(PipelineMockIndex.new, 1, PipelineFoo)
        )
      )
      .map(->(payload : Tuple(String, Crig::Pipeline::Result(Array(Tuple(Float64, String, PipelineFoo)), Crig::VectorStoreError))) do
        query = payload[0]
        maybe_docs = payload[1]
        docs = maybe_docs.unwrap
        "User query: #{query}\n\nTop documents:\n#{docs[0][2].foo}"
      end)
      .prompt(PipelineMockModel.new)

    pipeline.call("What is a flurbo?").unwrap.should eq(
      "Mock response: User query: What is a flurbo?\n\nTop documents:\nbar"
    )
  end
end

describe Crig::Pipeline::Op do
  it "supports sequential constructors and chained combinators" do
    op1 = Crig::Pipeline.map(->(x : Int32) { x + 1 })
    op2 = Crig::Pipeline.map(->(x : Int32) { x * 2 })
    op3 = Crig::Pipeline.map(->(x : Int32) { x * 3 })

    pipeline = Crig::Pipeline::Sequential(
      Crig::Pipeline::Sequential(
        typeof(op1),
        typeof(op2),
        Int32,
        Int32,
      ),
      typeof(op3),
      Int32,
      Int32,
    ).new(
      Crig::Pipeline::Sequential(typeof(op1), typeof(op2), Int32, Int32).new(op1, op2),
      op3
    )

    pipeline.call(1).should eq(12)

    chained = Crig::Pipeline.map(->(x : Int32) { x + 1 })
      .map(->(x : Int32) { x * 2 })
      .and_then(->(x : Int32) { x * 3 })

    chained.call(1).should eq(12)
  end

  it "supports passthrough and batch calls" do
    passthrough = Crig::Pipeline::Passthrough(String).new
    passthrough.call("hello").should eq("hello")

    batch = Crig::Pipeline.map(->(x : Int32) { x + 1 }).batch_call(2, [1, 2, 3])
    batch.should eq([2, 3, 4])
  end

  it "supports async calls through channels" do
    async_result = Crig::Pipeline.map(->(x : Int32) { x + 1 }).call_async(1).receive

    async_result.unwrap.should eq(2)
  end
end

describe Crig::Pipeline::TryOp do
  it "supports try_call and try_batch_call on result ops" do
    op = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end)

    op.try_call(2).unwrap.should eq(2)
    op.try_batch_call(2, [2, 4]).unwrap.should eq([2, 4])
  end

  it "supports async try calls through channels" do
    op = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end)

    op.try_call_async(2).receive.unwrap.unwrap.should eq(2)
  end

  it "maps successful results" do
    pipeline = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end)
      .map_ok(->(x : Int32) { x * 2 })
      .map_ok(->(x : Int32) { x - 1 })

    pipeline.try_call(2).unwrap.should eq(3)
  end

  it "maps error results" do
    pipeline = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end)
      .map_err(->(error : String) { "Error: #{error}" })
      .map_err(->(error : String) { error.size })

    pipeline.try_call(1).error.should eq(15)
  end

  it "supports and_then and or_else chaining" do
    and_then_pipeline = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end).and_then(->(x : Int32) { Crig::Pipeline::Result(Int32, String).ok((x * 2) - 1) })

    and_then_pipeline.try_call(2).unwrap.should eq(3)

    or_else_pipeline = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end).or_else(->(error : String) { Crig::Pipeline::Result(Int32, Int32).err("Error: #{error}".size) })

    or_else_pipeline.try_call(1).error.should eq(15)
  end

  it "chains normal ops on successful results" do
    pipeline = Crig::Pipeline.map(->(x : Int32) do
      if x.even?
        Crig::Pipeline::Result(Int32, String).ok(x)
      else
        Crig::Pipeline::Result(Int32, String).err("x is odd")
      end
    end).chain_ok(
      Crig::Pipeline.map(->(x : Int32) { x + 1 })
    )

    pipeline.try_call(2).unwrap.should eq(3)
  end

  it "runs try-parallel branches with fiber-backed channels" do
    op = Crig::Pipeline.parallel(
      Crig::Pipeline.map(->(x : Int32) { Crig::Pipeline::Result(Int32, String).ok(x + 1) }),
      Crig::Pipeline.map(->(x : Int32) { Crig::Pipeline::Result(Int32, String).ok(x - 1) })
    )

    op.try_call(5).unwrap.should eq({6, 4})
  end
end

describe Crig::Telemetry do
  it "exposes provider request metadata through the request extension protocol" do
    request = FakeTelemetryRequest.new

    request.get_input_messages.should eq(["user:hello"])
    request.get_system_prompt.should eq("You are concise.")
    request.get_model_name.should eq("fake-model")
    request.get_prompt.should eq("hello")
  end

  it "exposes provider response metadata through the response extension protocol" do
    response = FakeTelemetryResponse.new

    response.get_response_id.should eq("resp_123")
    response.get_response_model_name.should eq("fake-model")
    response.get_output_messages.should eq(["assistant:hi"])
    response.get_text_response.should eq("hi")
    response.get_usage.not_nil!.output_tokens.should eq(2)
  end

  it "records usage, response metadata, and serialized messages through the span combinator protocol" do
    span = FakeSpanCombinator.new
    response = FakeTelemetryResponse.new

    span.record_token_usage(response)
    span.record_response_metadata(response)
    span.record_model_input(response.get_output_messages)
    span.record_model_output(response.get_output_messages)

    span.events.should eq([
      "usage:1:2",
      "response:resp_123:fake-model",
      %(input:["assistant:hi"]),
      %(output:["assistant:hi"]),
    ])
  end
end

describe Crig::JSONUtils do
  it "detects empty or missing strings" do
    Crig::JSONUtils.empty_or_none(nil).should be_true
    Crig::JSONUtils.empty_or_none("").should be_true
    Crig::JSONUtils.empty_or_none("hello").should be_false
  end

  it "merges top-level json objects" do
    left = JSON.parse(%({"key1":"value1"}))
    right = JSON.parse(%({"key2":"value2"}))

    merged = Crig::JSONUtils.merge(left, right)

    merged["key1"].as_s.should eq("value1")
    merged["key2"].as_s.should eq("value2")
  end

  it "merges json objects in place" do
    left = JSON.parse(%({"key1":"value1"}))
    right = JSON.parse(%({"key2":"value2"}))

    Crig::JSONUtils.merge_inplace(left, right)

    left["key1"].as_s.should eq("value1")
    left["key2"].as_s.should eq("value2")
  end

  it "renders values to json strings" do
    Crig::JSONUtils.value_to_json_string(JSON.parse(%("hello"))).should eq("hello")
    Crig::JSONUtils.value_to_json_string(JSON.parse(%({"key":"value"}))).should eq(%({"key":"value"}))
  end

  it "serializes and deserializes stringified json" do
    dummy = DummyStringifiedJSON.new(JSON.parse(%({"key":"value"})))
    serialized = dummy.to_json
    inner = %({"key":"value"})
    payload = %({"data":#{inner.to_json}})
    parsed = DummyStringifiedJSON.from_json(payload)

    serialized.should eq(payload)
    parsed.data["key"].as_s.should eq("value")
  end

  it "deserializes empty stringified json as an empty object" do
    parsed = DummyStringifiedJSON.from_json(%({"data":""}))

    parsed.data.as_h.should eq({} of String => JSON::Any)
  end
end

describe Crig do
  it "exposes wasm compatibility markers and boxed future alias" do
    value = FakeWasmCompat.new
    future = Crig::WasmBoxedFuture(Int32).new { 42 }

    value.is_a?(Crig::WasmCompatSend).should be_true
    value.is_a?(Crig::WasmCompatSync).should be_true
    value.is_a?(Crig::WasmCompatSendStream).should be_true
    future.is_a?(Crig::WasmBoxedFuture(Int32)).should be_true
    future.call.should eq(42)
  end
end

describe Crig::RawStreamingToolCall, tags: %w[streaming tool_call] do
  it "supports builder-style updates" do
    tool_call = Crig::RawStreamingToolCall.new(
      "tool-1",
      "search",
      JSON.parse(%({"q":"crystal"}))
    )
      .with_internal_call_id("internal-1")
      .with_call_id("call-1")
      .with_signature("sig-1")
      .with_additional_params(JSON.parse(%({"provider":"local"})))

    tool_call.id.should eq("tool-1")
    tool_call.internal_call_id.should eq("internal-1")
    tool_call.call_id.should eq("call-1")
    tool_call.signature.should eq("sig-1")
    tool_call.additional_params.should_not be_nil
    tool_call.to_tool_call.function.name.should eq("search")
  end

  it "builds an empty tool call" do
    empty = Crig::RawStreamingToolCall.empty

    empty.id.should eq("")
    empty.name.should eq("")
  end
end

describe Crig::PauseControl, tags: %w[streaming control] do
  it "pauses and resumes" do
    control = Crig::PauseControl.new

    control.is_paused.should be_false
    control.pause
    control.is_paused.should be_true
    control.resume
    control.is_paused.should be_false
  end
end

describe Crig::StreamingCompletionResponse do
  it "aggregates text, reasoning, tool calls, and final response" do
    stream = Crig::StreamingCompletionResponse(Crig::MockResponse).stream([
      Crig::RawStreamingChoice(Crig::MockResponse).message("Hello"),
      Crig::RawStreamingChoice(Crig::MockResponse).message(" world"),
      Crig::RawStreamingChoice(Crig::MockResponse).reasoning_delta("reason-1", "Think"),
      Crig::RawStreamingChoice(Crig::MockResponse).reasoning_delta("reason-1", " harder"),
      Crig::RawStreamingChoice(Crig::MockResponse).tool_call(
        Crig::RawStreamingToolCall.new("tool-1", "search", JSON.parse(%({"q":"Crystal"})))
          .with_internal_call_id("internal-1")
      ),
      Crig::RawStreamingChoice(Crig::MockResponse).final_response(Crig::MockResponse.new(15)),
      Crig::RawStreamingChoice(Crig::MockResponse).message_id("msg-1"),
    ])

    items = stream.consume

    items.size.should eq(6)
    items[0].kind.text?.should be_true
    items[1].kind.text?.should be_true
    items[2].kind.reasoning_delta?.should be_true
    items[3].kind.reasoning_delta?.should be_true
    items[4].kind.tool_call?.should be_true
    items[5].kind.final?.should be_true

    stream.response.should eq(Crig::MockResponse.new(15))
    stream.message_id.should eq("msg-1")
    stream.final_response_yielded.should be_true
    stream.choice.to_a[0].text.not_nil!.text.should eq("Hello world")
    stream.choice.to_a[1].reasoning.not_nil!.display_text.should eq("Think harder")
    stream.choice.to_a[2].tool_call.not_nil!.function.name.should eq("search")
    stream.to_completion_response.raw_response.should eq(Crig::MockResponse.new(15))
  end

  it "returns no chunks while paused and supports cancel" do
    stream = Crig::StreamingCompletionResponse(Crig::MockResponse).stream([
      Crig::RawStreamingChoice(Crig::MockResponse).message("Hello"),
    ])

    stream.pause
    stream.consume.should eq([] of Crig::StreamedAssistantContent(Crig::MockResponse))
    stream.resume
    stream.cancel
    stream.consume.should eq([] of Crig::StreamedAssistantContent(Crig::MockResponse))
  end
end

describe Crig::MockResponse do
  it "exposes token usage from the mock token count" do
    response = Crig::MockResponse.new(15)

    response.token_usage.try(&.total_tokens).should eq(15)
  end
end

describe Crig::StreamedUserContent, tags: %w[streaming user] do
  it "wraps tool results with the internal call id" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool-1",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("done")
      )
    )

    content = Crig::StreamedUserContent.tool_result(tool_result, "internal-1")

    content.tool_result.try(&.id).should eq("tool-1")
    content.internal_call_id.should eq("internal-1")
  end
end

describe Crig::VectorStore::VectorSearchRequestBuilder do
  it "builds a vector search request with optional fields" do
    filter = Crig::Filter.eq("topic", JSON.parse(%("crystal")))
    request = Crig::VectorSearchRequest.builder
      .query("vector search")
      .samples(5)
      .threshold(0.75)
      .additional_params(JSON.parse(%({"mode":"semantic"})))
      .filter(filter)
      .build

    request.query.should eq("vector search")
    request.samples.should eq(5_u64)
    request.threshold.should eq(0.75)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["mode"].as_s.should eq("semantic")
    request.filter.should eq(filter)
  end

  it "requires query before build" do
    expect_raises(Crig::BuilderError, "`query` is a required variable for building a vector search request") do
      Crig::VectorSearchRequest.builder.samples(2).build
    end
  end

  it "requires samples before build" do
    expect_raises(Crig::BuilderError, "`samples` is a required variable for building a vector search request") do
      Crig::VectorSearchRequest.builder.query("vector search").build
    end
  end

  it "rejects non-object additional params" do
    expect_raises(Crig::BuilderError, "Expected JSON object for additional params, got something else") do
      Crig::VectorSearchRequest.builder
        .query("vector search")
        .samples(1)
        .additional_params(JSON.parse(%("bad")))
        .build
    end
  end
end

describe Crig::VectorStore::VectorSearchRequest do
  it "maps filters into backend-specific types" do
    filter = Crig::Filter
      .eq("topic", JSON.parse(%("crystal")))
      .and_(Crig::Filter.gt("score", JSON.parse(%(3))))

    request = Crig::VectorSearchRequest.new("query", 4_u64, filter: filter)
    mapped = request.map_filter { |value| RecordedFilter.from_filter(value) }

    mapped.filter.should_not be_nil
    filter_description = mapped.filter.try(&.description)
    filter_description.should eq(%(and(eq(topic,"crystal"),gt(score,3))))
  end

  it "propagates filter conversion errors from try_map_filter" do
    request = Crig::VectorSearchRequest.new(
      "query",
      4_u64,
      filter: Crig::Filter.eq("topic", JSON.parse(%("crystal"))),
    )

    expect_raises(Crig::FilterError, "Missing field 'metadata.topic'") do
      request.try_map_filter do |_value|
        raise Crig::FilterError.missing_field("metadata.topic")
      end
    end
  end
end

describe Crig::FilterError do
  it "builds parity-style filter errors" do
    Crig::FilterError.expected("json object", "string").message.should eq("Expected: json object, got: string")
    Crig::FilterError.type_error("non-JSON filter value").message.should eq("Cannot compile 'non-JSON filter value' to the backend's filter type")
    Crig::FilterError.missing_field("metadata.topic").message.should eq("Missing field 'metadata.topic'")
    Crig::FilterError.must("samples", "be positive").message.should eq("'samples' must be positive")
    Crig::FilterError.serialization("boom").message.should eq("Filter serialization failed: boom")
  end
end

describe Crig::VectorStoreError do
  it "builds parity-style vector store errors" do
    embedding = Crig::VectorStoreError.embedding_error(Exception.new("embed boom"))
    embedding.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::EmbeddingError)
    embedding.message.should eq("Embedding error: embed boom")
    embedding.source_error.try(&.message).should eq("embed boom")

    datastore = Crig::VectorStoreError.datastore_error(Exception.new("db boom"))
    datastore.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::DatastoreError)
    datastore.message.should eq("Datastore error: db boom")

    filter = Crig::VectorStoreError.filter_error(Crig::FilterError.missing_field("metadata.topic"))
    filter.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::FilterError)
    filter.message.should eq("Filter error: Missing field 'metadata.topic'")

    missing_id = Crig::VectorStoreError.missing_id("doc-1")
    missing_id.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::MissingIdError)
    missing_id.message.should eq("Missing Id: doc-1")

    external = Crig::VectorStoreError.external_api_error(429, "rate limited")
    external.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::ExternalApiError)
    external.status_code.should eq(429)
    external.message.should eq("External call to API returned an error. Error code: 429 Message: rate limited")

    builder = Crig::BuilderError.new("`query` is missing")
    builder.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::BuilderError)
    builder.message.should eq("Error while building VectorSearchRequest: `query` is missing")
  end
end

describe Crig::Filter do
  it "preserves the upstream satisfies semantics" do
    eq_filter = Crig::Filter.eq("topic", JSON.parse(%("crystal")))
    gt_filter = Crig::Filter.gt("score", JSON.parse(%(3)))
    lt_filter = Crig::Filter.lt("score", JSON.parse(%(3)))

    eq_filter.satisfies(JSON.parse(%({"topic":"crystal"}))).should be_true
    eq_filter.satisfies(JSON.parse(%({"topic":"other"}))).should be_false
    gt_filter.satisfies(JSON.parse(%({"score":4}))).should be_false
    lt_filter.satisfies(JSON.parse(%({"score":2}))).should be_false
  end

  it "evaluates composed filters recursively" do
    left = Crig::Filter.eq("topic", JSON.parse(%("crystal")))
    right = Crig::Filter.eq("kind", JSON.parse(%("guide")))

    left.and_(right).satisfies(JSON.parse(%({"topic":"crystal"}))).should be_false
    left.or_(right).satisfies(JSON.parse(%({"topic":"crystal"}))).should be_true
  end
end

describe Crig::IndexStrategy do
  it "defaults to brute force and exposes lsh settings" do
    brute_force = Crig::IndexStrategy.brute_force
    lsh = Crig::IndexStrategy.lsh(5, 10)

    brute_force.brute_force?.should be_true
    brute_force.lsh?.should be_false
    lsh.lsh?.should be_true
    lsh.num_tables.should eq(5)
    lsh.num_hyperplanes.should eq(10)
  end
end

describe Crig::InMemoryVectorStoreBuilder(String) do
  it "builds stores with explicit ids and a custom strategy" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {"doc-a", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc-b", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
      ])
      .build

    store.index_strategy.lsh?.should be_true
    store.len.should eq(2)
    store.embeddings["doc-a"][0].should eq("glarb-garb")
    store.embeddings["doc-b"][1].first.document.should eq("marble-marble")
  end

  it "assigns auto ids using the current builder size" do
    store = Crig::InMemoryVectorStore(String).builder
      .documents([
        {"glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
        {"flumb-flumb", vector_embedding("flumb-flumb", [0.3, 0.7, 0.1])},
      ])
      .build

    store.add_documents([
      {"brotato", vector_embedding("brotato", [0.3, 0.7, 0.1])},
      {"ping-pong", vector_embedding("ping-pong", [0.7, -0.3, 0.0])},
    ])

    store.embeddings.keys.sort!.should eq(["doc0", "doc1", "doc2", "doc3", "doc4"])
    store.embeddings["doc3"][0].should eq("brotato")
    store.embeddings["doc4"][0].should eq("ping-pong")
  end

  it "supports ids generated from documents" do
    store = Crig::InMemoryVectorStore(String).builder
      .documents_with_id_f([
        {"first", vector_embedding("first", [1.0, 0.0])},
        {"second", vector_embedding("second", [0.0, 1.0])},
      ]) { |document| "id-#{document}" }
      .build

    store.embeddings.keys.sort!.should eq(["id-first", "id-second"])
  end
end

describe Crig::InMemoryVectorStore(String) do
  it "builds from document helpers and exposes collection accessors" do
    store = Crig::InMemoryVectorStore(String).from_documents_with_ids([
      {"doc-1", "first", vector_embedding("first", [1.0, 0.0])},
      {"doc-2", "second", vector_embedding("second", [0.0, 1.0])},
    ])

    iterated_ids = store.iter.map(&.[0]).to_a.sort!

    store.empty?.should be_false
    store.len.should eq(2)
    iterated_ids.should eq(["doc-1", "doc-2"])
  end

  it "matches the upstream single-embedding ranking behavior" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {"doc1", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc2", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
        {"doc3", "flumb-flumb", vector_embedding("flumb-flumb", [0.3, 0.7, 0.1])},
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6]),
      1,
    )

    ranking.map { |result| {result.score, result.id, result.document} }.should eq([
      {0.9807965956109156, "doc1", "glarb-garb"},
    ])
  end

  it "uses the best embedding per document when ranking" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {
          "doc1",
          "glarb-garb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
            Crig::Embeddings::Embedding.new("don't-choose-me", [-0.5, 0.9, 0.1]),
          ]),
        },
        {
          "doc2",
          "marble-marble",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("marble-marble", [0.7, -0.3, 0.0]),
            Crig::Embeddings::Embedding.new("sandwich", [0.5, 0.5, -0.7]),
          ]),
        },
        {
          "doc3",
          "flumb-flumb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("flumb-flumb", [0.3, 0.7, 0.1]),
            Crig::Embeddings::Embedding.new("banana", [0.1, -0.5, -0.5]),
          ]),
        },
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6]),
      1,
    )

    ranking.map { |result| {result.score, result.id, result.document, result.embedding_document} }.should eq([
      {0.9807965956109156, "doc1", "glarb-garb", "glarb-garb"},
    ])
  end

  it "uses the configured lsh index when the strategy requests it" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(3, 5))
      .documents_with_ids([
        {"doc1", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc2", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
      1,
    )

    ranking.size.should eq(1)
    ranking[0].id.should eq("doc1")
  end
end

describe Crig::InMemoryVectorStore(StoredDoc) do
  it "returns stored documents by id with typed deserialization" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0])},
      {"doc-2", StoredDoc.new("doc-2", "second"), vector_embedding("second", [0.0, 1.0])},
    ])

    document = store.get_document("doc-2", StoredDoc)

    document.should_not be_nil
    document = document.as(StoredDoc)
    document.id.should eq("doc-2")
    document.name.should eq("second")
    store.get_document("missing", StoredDoc).should be_nil
  end

  it "wraps the store in an index facade" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0])},
    ])

    index = store.index(FakeEmbeddingModel.new)

    index.model.should be_a(FakeEmbeddingModel)
    index.store.len.should eq(1)
    index.len.should eq(1)
    index.empty?.should be_false
    index.iter.map(&.[0]).to_a.should eq(["doc-1"])
  end

  it "returns typed top-n results through the index facade" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
      {"doc-2", StoredDoc.new("doc-2", "second"), vector_embedding("second", [0.0, 1.0, 0.0])},
    ])
    index = store.index(FakeEmbeddingModel.new)
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    results = index.top_n(request, StoredDoc)

    results.size.should eq(1)
    results[0][1].should eq("doc-1")
    results[0][2].name.should eq("first")
    index.top_n_ids(request).should eq([{results[0][0], "doc-1"}])
  end

  it "builds vector-store output payloads from index calls" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])
    index = store.index(FakeEmbeddingModel.new)
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    outputs = index.call(request)

    outputs.size.should eq(1)
    outputs[0].id.should eq("doc-1")
    outputs[0].document["name"].as_s.should eq("first")
  end

  it "exposes a tool definition for vector-store calls" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])

    definition = store.index(FakeEmbeddingModel.new).definition

    definition.name.should eq("search_vector_store")
    definition.parameters["required"].as_a.map(&.as_s).should eq(["query", "samples"])
  end
end

describe Crig::InMemoryVectorStore(JSON::Any) do
  it "prunes oversized arrays from dynamic vector-store output" do
    large_array = Array.new(401) { 1 }
    document = JSON.parse({"name" => "first", "huge" => large_array}.to_json)
    store = Crig::InMemoryVectorStore(JSON::Any).from_documents_with_ids([
      {"doc-1", document, vector_embedding("first", [1.0, 0.0, 0.0])},
    ])
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    outputs = store.index(FakeEmbeddingModel.new).call(request)

    outputs[0].document["name"].as_s.should eq("first")
    outputs[0].document["huge"]?.should be_nil
  end

  it "supports insert_documents as a store helper" do
    store = Crig::InMemoryVectorStore(JSON::Any).new
    store.insert_documents([
      {JSON.parse(%({"name":"first"})), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])

    store.len.should eq(1)
    store.embeddings["doc0"][0]["name"].as_s.should eq("first")
  end
end

describe Crig::LSH do
  it "builds deterministic hyperplanes for the same shape" do
    left = Crig::LSH.new(3, 2, 4)
    right = Crig::LSH.new(3, 2, 4)

    left.hyperplanes.should eq(right.hyperplanes)
    left.hash([0.1, 0.2, 0.3], 0).should eq(right.hash([0.1, 0.2, 0.3], 0))
  end

  it "hashes vectors per table into bitsets" do
    lsh = Crig::LSH.new(3, 2, 4)
    hash = lsh.hash([0.1, 0.2, 0.3], 1)

    hash.should be_a(UInt64)
    hash.should be >= 0_u64
  end
end

describe Crig::LSHIndex do
  it "returns inserted ids for matching query buckets" do
    index = Crig::LSHIndex.new(3, 3, 5)
    embedding = [0.1, 0.2, 0.3]

    index.insert("doc-1", embedding)
    index.insert("doc-1", embedding)
    index.insert("doc-2", [-0.1, 0.4, 0.3])

    candidates = index.query(embedding)

    candidates.includes?("doc-1").should be_true
    candidates.count("doc-1").should eq(1)
  end

  it "clears all tables" do
    index = Crig::LSHIndex.new(3, 2, 4)
    embedding = [0.1, 0.2, 0.3]

    index.insert("doc-1", embedding)
    index.clear

    index.query(embedding).should eq([] of String)
  end
end

describe Crig::ImageGenerationRequestBuilder do
  it "builds image generation requests" do
    model = FakeImageGenerationModel.new
    request = Crig::ImageGenerationRequestBuilder.new(model)
      .prompt("draw a cat")
      .width(512)
      .height(768)
      .additional_params(JSON.parse(%({"style":"pixel"})))
      .build

    request.prompt.should eq("draw a cat")
    request.width.should eq(512)
    request.height.should eq(768)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["style"].as_s.should eq("pixel")
  end

  it "sends image generation requests through a model" do
    model = FakeImageGenerationModel.new
    response = Crig::ImageGenerationRequestBuilder.new(model)
      .prompt("draw a cat")
      .send

    response.image.should eq(Bytes[1_u8, 2_u8, 3_u8])
    response.response.should eq("raw-image")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::ImageGenerationRequest).prompt.should eq("draw a cat")
  end
end

describe Crig::AudioGenerationRequestBuilder do
  it "builds audio generation requests" do
    model = FakeAudioGenerationModel.new
    request = Crig::AudioGenerationRequestBuilder.new(model)
      .text("hello world")
      .voice("alloy")
      .speed(1.5_f32)
      .additional_params(JSON.parse(%({"format":"mp3"})))
      .build

    request.text.should eq("hello world")
    request.voice.should eq("alloy")
    request.speed.should eq(1.5_f32)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["format"].as_s.should eq("mp3")
  end

  it "sends audio generation requests through a model" do
    model = FakeAudioGenerationModel.new
    response = Crig::AudioGenerationRequestBuilder.new(model)
      .text("hello world")
      .voice("alloy")
      .send

    response.audio.should eq(Bytes[4_u8, 5_u8])
    response.response.should eq("raw-audio")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::AudioGenerationRequest).text.should eq("hello world")
    model.last_request.as(Crig::AudioGenerationRequest).voice.should eq("alloy")
  end
end

describe Crig::TranscriptionRequestBuilder do
  it "builds transcription requests" do
    model = FakeTranscriptionModel.new
    request = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8, 2_u8, 3_u8])
      .filename("audio.mp3")
      .language("en")
      .prompt("transcribe clearly")
      .temperature(0.5)
      .additional_params(JSON.parse(%({"format":"verbose"})))
      .build

    request.data.should eq(Bytes[1_u8, 2_u8, 3_u8])
    request.filename.should eq("audio.mp3")
    request.language.should eq("en")
    request.prompt.should eq("transcribe clearly")
    request.temperature.should eq(0.5)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["format"].as_s.should eq("verbose")
  end

  it "loads transcription data from a file path" do
    model = FakeTranscriptionModel.new
    dir = File.join(Dir.tempdir, "crig-transcription-builder-#{Random::Secure.hex(8)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.wav")

    begin
      File.write(path, "abc")

      request = Crig::TranscriptionRequestBuilder.new(model)
        .load_file(path)
        .build

      request.filename.should eq("sample.wav")
      request.data.should eq("abc".to_slice)
    ensure
      File.delete?(path)
      Dir.delete(dir)
    end
  end

  it "merges transcription additional params" do
    model = FakeTranscriptionModel.new
    request = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8])
      .additional_params(JSON.parse(%({"a":1})))
      .additional_params(JSON.parse(%({"b":2})))
      .build

    request.additional_params.should_not be_nil
    params = request.additional_params.as(JSON::Any)
    params["a"].as_i.should eq(1)
    params["b"].as_i.should eq(2)
  end

  it "sends transcription requests through a model" do
    model = FakeTranscriptionModel.new
    response = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8, 2_u8])
      .filename("audio.mp3")
      .send

    response.text.should eq("hello world")
    response.response.should eq("raw-transcription")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::TranscriptionRequest).filename.should eq("audio.mp3")
  end
end

describe Crig::Model::Model do
  it "builds from id only" do
    model = Crig::Model::Model.from_id("gpt-4")

    model.id.should eq("gpt-4")
    model.name.should be_nil
    model.description.should be_nil
    model.type.should be_nil
    model.created_at.should be_nil
    model.owned_by.should be_nil
    model.context_length.should be_nil
  end

  it "builds with id and name" do
    model = Crig::Model::Model.new("gpt-4", "GPT-4")

    model.id.should eq("gpt-4")
    model.name.should eq("GPT-4")
  end

  it "uses name for display when present" do
    Crig::Model::Model.new("gpt-4", "GPT-4").display_name.should eq("GPT-4")
    Crig::Model::Model.from_id("gpt-4").display_name.should eq("gpt-4")
    Crig::Model::Model.new("gpt-4", "GPT-4").to_s.should eq("GPT-4")
  end

  it "round-trips via json" do
    model = Crig::Model::Model.new(
      "gpt-4",
      name: "GPT-4",
      type: "chat",
      created_at: 1_677_610_600_i64,
      owned_by: "openai",
      context_length: 8192,
    )

    parsed = Crig::Model::Model.from_json(model.to_json)

    parsed.id.should eq("gpt-4")
    parsed.name.should eq("GPT-4")
    parsed.type.should eq("chat")
  end
end

describe Crig::Model::ModelList do
  it "builds and inspects list state" do
    list = Crig::Model::ModelList.new([Crig::Model::Model.from_id("gpt-4")])

    list.len.should eq(1)
    list.empty?.should be_false
    list.iter.to_a.size.should eq(1)
  end

  it "supports empty lists" do
    list = Crig::Model::ModelList.new([] of Crig::Model::Model)

    list.empty?.should be_true
    list.is_empty.should be_true
    list.len.should eq(0)
  end

  it "round-trips via json" do
    list = Crig::Model::ModelList.new([Crig::Model::Model.from_id("gpt-4")])
    parsed = Crig::Model::ModelList.from_json(list.to_json)

    parsed.len.should eq(1)
    parsed.data.first.id.should eq("gpt-4")
  end

  it "supports borrowed and owned iteration helpers" do
    list = Crig::Model::ModelList.new([
      Crig::Model::Model.from_id("gpt-4"),
      Crig::Model::Model.from_id("gpt-3.5-turbo"),
    ])

    list.iter.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
    list.into_iter.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
    list.map(&.id).to_a.should eq(["gpt-4", "gpt-3.5-turbo"])
  end
end

describe Crig::Model::ModelListingError do
  it "formats each error variant" do
    Crig::Model::ModelListingError.api_error(404, "Not found").to_s.should eq("API error (status 404): Not found")
    Crig::Model::ModelListingError.request_error("Connection failed").to_s.should eq("Request error: Connection failed")
    Crig::Model::ModelListingError.parse_error("Invalid JSON").to_s.should eq("Parse error: Invalid JSON")
    Crig::Model::ModelListingError.auth_error("Invalid API key").to_s.should eq("Authentication error: Invalid API key")
    Crig::Model::ModelListingError.rate_limit_error("Too many requests").to_s.should eq("Rate limit error: Too many requests")
    Crig::Model::ModelListingError.service_unavailable("Maintenance mode").to_s.should eq("Service unavailable: Maintenance mode")
    Crig::Model::ModelListingError.unknown_error("Something went wrong").to_s.should eq("Unknown error: Something went wrong")
  end

  it "round-trips via json" do
    error = Crig::Model::ModelListingError.api_error(404, "Not found")
    parsed = Crig::Model::ModelListingError.from_json(error.to_json)

    parsed.kind.api_error?.should be_true
    parsed.status_code.should eq(404)
    parsed.message.should eq("Not found")
  end
end

describe Crig::Completion::Message, tags: %w[completion message] do
  it "builds a user message" do
    message = Crig::Completion::Message.user("hello")

    message.role.user?.should be_true
    message.rag_text.should eq("hello")
  end

  it "builds an assistant message with an id" do
    message = Crig::Completion::Message.assistant_with_id("assistant-1", "hi")

    message.role.assistant?.should be_true
    message.id.should eq("assistant-1")
  end

  it "builds a tool result message" do
    message = Crig::Completion::Message.tool_result_with_call_id("tool-1", "call-1", "done")
    content = message.content.first.as(Crig::Completion::UserContent)
    tool_result = content.tool_result
    tool_result.should_not be_nil
    text = tool_result.as(Crig::Completion::ToolResult).content.first.text
    text.should_not be_nil

    content.kind.tool_result?.should be_true
    tool_result.as(Crig::Completion::ToolResult).call_id.should eq("call-1")
    text.as(Crig::Completion::Text).text.should eq("done")
  end
end

describe Crig::Examples::EnumDispatch::ProviderRegistry do
  it "ports ProviderRegistry.new and agent dispatch" do
    registry = Crig::Examples::EnumDispatch::ProviderRegistry.new(
      {
        "openai" => ->(config : Crig::Examples::EnumDispatch::AgentConfig) do
          Crig::Examples::EnumDispatch::Agents.new(
            Crig::AgentBuilder(EnumDispatchOpenAIModel).new(EnumDispatchOpenAIModel.new)
              .name(config.name)
              .preamble(config.preamble)
              .build
          )
        end,
        "anthropic" => ->(config : Crig::Examples::EnumDispatch::AgentConfig) do
          Crig::Examples::EnumDispatch::Agents.new(
            Crig::AgentBuilder(EnumDispatchAnthropicModel).new(EnumDispatchAnthropicModel.new)
              .name(config.name)
              .preamble(config.preamble)
              .build
          )
        end,
      }
    )

    openai_agent = registry.agent(
      "openai",
      Crig::Examples::EnumDispatch::AgentConfig.new(
        name: "Assistant",
        preamble: "You are a helpful assistant",
      )
    )
    anthropic_agent = registry.agent(
      "anthropic",
      Crig::Examples::EnumDispatch::AgentConfig.new(
        name: "Assistant",
        preamble: "You are an unhelpful assistant",
      )
    )

    openai_agent.should_not be_nil
    anthropic_agent.should_not be_nil
    openai_agent.not_nil!.prompt("How much does 4oz of parmesan cheese weigh").should eq("Helpful")
    anthropic_agent.not_nil!.prompt("How much does 4oz of parmesan cheese weigh").should eq("Unhelpful")
    registry.agent(
      "missing",
      Crig::Examples::EnumDispatch::AgentConfig.new(
        name: "Assistant",
        preamble: "unused",
      )
    ).should be_nil
  end
end

describe Crig::HttpClient do
  it "builds bearer auth headers and applies them to requests" do
    header = Crig::HttpClient.make_auth_header("secret").unwrap
    header.should eq({"Authorization", "Bearer secret"})

    headers = HTTP::Headers.new
    Crig::HttpClient.bearer_auth_header(headers, "secret").unwrap
    headers["Authorization"].should eq("Bearer secret")

    request = HTTP::Request.new("GET", "/status")
    Crig::HttpClient.with_bearer_auth(request, "secret").unwrap.headers["Authorization"].should eq("Bearer secret")
  end

  it "returns NoHeaders for builder auth when headers are unavailable" do
    builder = Crig::HttpClient::RequestBuilder.new("GET", "/status", nil)

    result = Crig::HttpClient.with_bearer_auth(builder, "secret")

    result.error.not_nil!.kind.no_headers?.should be_true
  end

  it "preserves structured error metadata for rust-shaped variants" do
    status = Crig::HttpClient::Error.invalid_status_code_with_message(422, "bad payload")
    status.kind.invalid_status_code_with_message?.should be_true
    status.status_code.should eq(422)
    status.detail.should eq("bad payload")

    content_type = Crig::HttpClient::Error.invalid_content_type("application/json")
    content_type.kind.invalid_content_type?.should be_true
    content_type.detail.should eq("application/json")

    source = Exception.new("boom")
    instance = Crig::HttpClient::Error.instance(source)
    instance.kind.instance?.should be_true
    instance.source.should be(source)
    instance.detail.should eq("boom")
  end

  it "supports generic result error payloads" do
    result = Crig::HttpClient::Result(Int32, String).err("transport failure")

    result.error.should eq("transport failure")
  end

  it "decodes text bodies with replacement characters for invalid utf-8" do
    channel = Channel(Crig::HttpClient::Result(Array(UInt8), Crig::HttpClient::Error)).new(1)
    channel.send(Crig::HttpClient::Result(Array(UInt8), Crig::HttpClient::Error).ok(Bytes[0xFF, 0x61].to_a))
    channel.close

    response = Crig::HttpClient::Response.new(Crig::HttpClient::LazyBody(Array(UInt8)).new(channel))
    Crig::HttpClient.text(response).should eq("#{Char::REPLACEMENT}a")
  end

  it "supports NoBody and mock streaming client" do
    client = Crig::HttpClient::MockStreamingClient.new(
      "body".to_slice,
      200,
      HTTP::Headers.new,
      ["chunk-1".to_slice, "chunk-2".to_slice]
    )
    request = HTTP::Request.new("POST", "/stream")

    first_reply = client.send(request)
    second_reply = client.send(request)

    first_reply.unwrap.body.receive.unwrap.should eq("body".to_slice)
    second_reply.unwrap.body.receive.unwrap.should eq("body".to_slice)
    first_reply.unwrap.status_code.should eq(200)
    first_reply.unwrap.headers.empty?.should be_true

    streaming = client.send_streaming(request).unwrap
    streaming.receive.not_nil!.unwrap.should eq("chunk-1".to_slice)
    streaming.receive.not_nil!.unwrap.should eq("chunk-2".to_slice)
    streaming.receive?.should be_nil
    client.sent_requests.should eq([{"POST", "/stream"}, {"POST", "/stream"}, {"POST", "/stream"}])
    Crig::HttpClient::NoBody.new.to_slice.should be_empty
  end

  it "returns InvalidStatusCodeWithMessage for non-success request responses" do
    client = Crig::HttpClient::MockStreamingClient.new(
      "bad payload".to_slice,
      422
    )
    request = HTTP::Request.new("POST", "/status")

    result = client.send(request)

    result.error.not_nil!.kind.invalid_status_code_with_message?.should be_true
    result.error.not_nil!.status_code.should eq(422)
    result.error.not_nil!.detail.should eq("bad payload")
  end

  it "wraps channel-backed transport items in typed streams" do
    channel = Channel(Crig::HttpClient::Result(String, Crig::HttpClient::Error)).new(1)
    channel.send(Crig::HttpClient::Result(String, Crig::HttpClient::Error).ok("hello"))
    channel.close

    stream = Crig::HttpClient::Stream(Crig::HttpClient::Result(String, Crig::HttpClient::Error)).new(channel)
    body = Crig::HttpClient::LazyBody(String).new(stream)

    stream.receive.unwrap.should eq("hello")
    body.receive?.should be_nil
  end
end

describe Crig::HttpClient::MultipartForm, tags: %w[http_client multipart] do
  it "ports test_multipart_encoding" do
    form = Crig::HttpClient::MultipartForm.new
      .text("field1", "value1")
      .text("field2", "value2")

    boundary, body = form.encode
    body_str = String.new(body)

    body_str.should contain("field1")
    body_str.should contain("value1")
    body_str.should contain(boundary)
  end

  it "ports test_file_part" do
    form = Crig::HttpClient::MultipartForm.new.file(
      "upload",
      "test.txt",
      "text/plain",
      "file contents".to_slice
    )

    _, body = form.encode
    body_str = String.new(body)

    body_str.should contain(%(filename="test.txt"))
    body_str.should contain("Content-Type: text/plain")
    body_str.should contain("file contents")
  end
end

describe Crig::HttpClient::ExponentialBackoff do
  it "backs off exponentially and respects bounds" do
    policy = Crig::HttpClient::ExponentialBackoff.new(300.milliseconds, 2.0, 5.seconds, 2)
    error = Crig::HttpClient::Error.stream_ended

    policy.retry(error, nil).should eq(300.milliseconds)
    policy.retry(error, {1, 300.milliseconds}).should eq(600.milliseconds)
    policy.retry(error, {2, 600.milliseconds}).should be_nil
  end

  it "updates reconnection time" do
    policy = Crig::HttpClient::ExponentialBackoff.new(300.milliseconds, 2.0, 500.milliseconds, nil)

    policy.set_reconnection_time(1.second)
    policy.start.should eq(1.second)
    policy.max_duration.should eq(1.second)
  end
end

describe Crig::HttpClient::Constant do
  it "returns the same delay until max retries" do
    policy = Crig::HttpClient::Constant.new(200.milliseconds, 1)
    error = Crig::HttpClient::Error.stream_ended

    policy.retry(error, nil).should eq(200.milliseconds)
    policy.retry(error, {1, 200.milliseconds}).should be_nil
  end
end

describe Crig::HttpClient::Never do
  it "never retries" do
    policy = Crig::HttpClient::Never.new
    policy.retry(Crig::HttpClient::Error.stream_ended, nil).should be_nil
  end
end

describe Crig::HttpClient::GenericEventSource, tags: %w[http_client sse] do
  it "emits open and parsed message events through a dedicated channel" do
    client = Crig::HttpClient::MockStreamingClient.new(
      Bytes.empty,
      200,
      HTTP::Headers.new,
      [
        "id: evt-1\nevent: update\ndata: hello\nretry: 250\n\n".to_slice,
        "data: world\n\n".to_slice,
      ]
    )
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.new(client, request)

    open = source.receive?.not_nil!.unwrap
    open.kind.open?.should be_true

    first = source.receive?.not_nil!.unwrap
    first.kind.message?.should be_true
    first.message.not_nil!.id.should eq("evt-1")
    first.message.not_nil!.event.should eq("update")
    first.message.not_nil!.data.should eq("hello")
    source.last_event_id.should eq("evt-1")

    second = source.receive?.not_nil!.unwrap
    second.kind.message?.should be_true
    second.message.not_nil!.data.should eq("world")
    source.receive?.should be_nil
  end

  it "reconnects after stream errors and forwards last-event-id on the next request" do
    client = ReconnectingSseClient.new
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.with_retry_policy(
      client,
      request,
      Crig::HttpClient::Constant.new(Time::Span.zero, 1)
    )

    first_open = source.receive?.not_nil!.unwrap
    first_open.kind.open?.should be_true

    first_message = source.receive?.not_nil!.unwrap
    first_message.kind.message?.should be_true
    first_message.message.not_nil!.id.should eq("evt-1")
    first_message.message.not_nil!.data.should eq("first")
    source.last_event_id.should eq("evt-1")

    reconnect_error = source.receive?.not_nil!
    reconnect_error.error.not_nil!.message.should eq("Stream ended")

    second_open = source.receive?.not_nil!.unwrap
    second_open.kind.open?.should be_true

    recovered = source.receive?.not_nil!.unwrap
    recovered.kind.message?.should be_true
    recovered.message.not_nil!.data.should eq("recovered")
    source.last_event_id.should eq("evt-1")

    source.receive?.should be_nil
    client.sent_requests.size.should eq(2)
    client.sent_requests.first.headers["Accept"].should eq("text/event-stream")
    client.sent_requests.first.headers["Last-Event-ID"]?.should be_nil
    client.sent_requests.last.headers["Last-Event-ID"].should eq("evt-1")
  end

  it "retries when the initial streaming connection fails before opening" do
    client = FailingConnectSseClient.new
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.with_retry_policy(
      client,
      request,
      Crig::HttpClient::Constant.new(Time::Span.zero, 1)
    )

    initial_error = source.receive?.not_nil!
    initial_error.error.not_nil!.kind.stream_ended?.should be_true

    open = source.receive?.not_nil!.unwrap
    open.kind.open?.should be_true

    connected = source.receive?.not_nil!.unwrap
    connected.kind.message?.should be_true
    connected.message.not_nil!.data.should eq("connected")
    source.receive?.should be_nil
  end

  it "ignores invalid utf-8 chunks and continues polling later events" do
    client = InvalidUtf8SseClient.new
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.new(client, request)

    open = source.receive?.not_nil!.unwrap
    open.kind.open?.should be_true

    recovered = source.receive?.not_nil!.unwrap
    recovered.kind.message?.should be_true
    recovered.message.not_nil!.data.should eq("recovered")
    source.receive?.should be_nil
  end

  it "fails fast on non-200 streaming responses" do
    client = Crig::HttpClient::MockStreamingClient.new(
      Bytes.empty,
      200,
      HTTP::Headers.new,
      ["data: ignored\n\n".to_slice],
      500
    )
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.new(client, request)

    result = source.receive?.not_nil!
    result.error.not_nil!.message.should eq("Invalid status code: 500")
    source.receive?.should be_nil
  end

  it "fails fast when content type is not text/event-stream" do
    client = Crig::HttpClient::MockStreamingClient.new(
      Bytes.empty,
      200,
      HTTP::Headers.new,
      ["data: ignored\n\n".to_slice],
      200,
      HTTP::Headers{"Content-Type" => "application/json"}
    )
    request = HTTP::Request.new("GET", "/events")
    source = Crig::HttpClient::GenericEventSource.new(client, request)

    result = source.receive?.not_nil!
    result.error.not_nil!.message.should eq(%(Invalid content type was returned: "application/json"))
    source.receive?.should be_nil
  end
end

describe Crig::Providers::Ollama do
  it "supports client initialization" do
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new)
    from_builder = Crig::Providers::Ollama::Client.builder.api_key(Crig::Nothing.new).build

    client.base_url.should eq(Crig::Providers::Ollama::OLLAMA_API_BASE_URL)
    from_builder.base_url.should eq(Crig::Providers::Ollama::OLLAMA_API_BASE_URL)
  end

  it "converts tool definitions to ollama format" do
    internal_tool = Crig::Completion::ToolDefinition.new(
      "get_current_weather",
      "Get the current weather for a location",
      JSON.parse(%({
        "type":"object",
        "properties":{"location":{"type":"string"}},
        "required":["location"]
      }))
    )

    ollama_tool = Crig::Providers::Ollama::ToolDefinition.from_core(internal_tool)

    ollama_tool.type_field.should eq("function")
    ollama_tool.function.name.should eq("get_current_weather")
    ollama_tool.function.parameters["properties"]["location"]["type"].as_s.should eq("string")
  end

  it "converts provider messages back into core messages" do
    provider_msg = Crig::Providers::Ollama::Message.user("Test message")
    comp_msg = provider_msg.to_core_message

    comp_msg.role.user?.should be_true
    first_content = comp_msg.content.first.as(Crig::Completion::UserContent)
    first_content.kind.text?.should be_true
    first_content.text.not_nil!.text.should eq("Test message")
  end

  it "converts assistant reasoning into ollama thinking" do
    internal_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("Step 1: Consider the problem").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("The answer is X").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    provider_msgs = Crig::Providers::Ollama::Message.from_core_message(internal_msg)

    provider_msgs.size.should eq(1)
    provider_msg = provider_msgs.first
    provider_msg.kind.assistant?.should be_true
    provider_msg.thinking.should eq("Step 1: Consider the problem")
    provider_msg.content.should eq("The answer is X")
  end

  it "deserializes chat responses with thinking content" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"The answer is 42.","thinking":"Let me think about this carefully.","images":null,"tool_calls":[]},
      "done":true,
      "total_duration":8000000000,
      "load_duration":6000000,
      "prompt_eval_count":61,
      "prompt_eval_duration":400000000,
      "eval_count":468,
      "eval_duration":7700000000
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.kind.assistant?.should be_true
    chat_resp.message.thinking.should eq("Let me think about this carefully.")
    chat_resp.message.content.should eq("The answer is 42.")
  end

  it "keeps empty thinking content when deserializing" do
    sample = JSON.parse(%({
      "model":"llama3.2",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"Response","thinking":"","images":null,"tool_calls":[]},
      "done":true
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.thinking.should eq("")
    chat_resp.message.content.should eq("Response")
  end

  it "deserializes streaming responses with thinking content" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"","thinking":"Analyzing the problem...","images":null,"tool_calls":[]},
      "done":false
    }))

    chunk = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chunk.message.thinking.should eq("Analyzing the problem...")
    chunk.message.content.should eq("")
  end

  it "deserializes thinking responses with tool calls" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{
        "role":"assistant",
        "content":"Let me check the weather.",
        "thinking":"User wants weather info, I should use the weather tool",
        "images":null,
        "tool_calls":[{"type":"function","function":{"name":"get_weather","arguments":{"location":"San Francisco"}}}]
      },
      "done":true
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.thinking.should eq("User wants weather info, I should use the weather tool")
    chat_resp.message.content.should eq("Let me check the weather.")
    chat_resp.message.tool_calls.size.should eq(1)
    chat_resp.message.tool_calls.first.function.name.should eq("get_weather")
  end

  it "extracts think and keep_alive as top-level request params" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":true,"keep_alive":"-1m","num_ctx":4096}))
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.should eq(JSON.parse(%({
      "model":"qwen3:8b",
      "messages":[
        {"role":"system","content":"You are a helpful assistant."},
        {"role":"user","content":"What is 2 + 2?"}
      ],
      "temperature":0.7,
      "stream":false,
      "think":true,
      "max_tokens":1024,
      "keep_alive":"-1m",
      "options":{"temperature":0.7,"num_ctx":4096}
    })))
  end

  it "defaults think to false when omitted" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello!")),
      preamble: "You are a helpful assistant.",
      temperature: 0.5
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.2", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.should eq(JSON.parse(%({
      "model":"llama3.2",
      "messages":[
        {"role":"system","content":"You are a helpful assistant."},
        {"role":"user","content":"Hello!"}
      ],
      "temperature":0.5,
      "stream":false,
      "think":false,
      "options":{"temperature":0.5}
    })))
  end

  it "serializes output schema into format" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("How old is Ollama?")),
      model: "llama3.1",
      output_schema: JSON.parse(%({
        "type":"object",
        "properties":{"age":{"type":"integer"},"available":{"type":"boolean"}},
        "required":["age","available"]
      }))
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.1", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized["format"].should eq(JSON.parse(%({
      "type":"object",
      "properties":{"age":{"type":"integer"},"available":{"type":"boolean"}},
      "required":["age","available"]
    })))
  end

  it "omits format when there is no output schema" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello!")),
      model: "llama3.1"
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.1", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.as_h.has_key?("format").should be_false
  end
end

describe Crig::Providers::Groq do
  it "serializes groq requests" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello world!")),
      additional_params: JSON.parse(%({"include_reasoning":true,"reasoning_format":"parsed"}))
    )

    groq = Crig::Providers::Groq::GroqCompletionRequest.from_request("openai/gpt-120b-oss", completion_request)
    json = JSON.parse(groq.to_json)

    json.should eq(JSON.parse(%({
      "model":"openai/gpt-120b-oss",
      "messages":[{"role":"user","content":"Hello world!"}],
      "stream":false,
      "include_reasoning":true,
      "reasoning_format":"parsed"
    })))
  end

  it "supports client initialization" do
    client = Crig::Providers::Groq::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Groq::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Groq::GROQ_API_BASE_URL)
  end
end

describe Crig::Providers::Galadriel do
  it "supports client initialization" do
    client = Crig::Providers::Galadriel::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Galadriel::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Galadriel::GALADRIEL_API_BASE_URL)
  end
end

describe Crig::Providers::Hyperbolic do
  it "supports client initialization" do
    client = Crig::Providers::Hyperbolic::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Hyperbolic::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Hyperbolic::HYPERBOLIC_API_BASE_URL)
  end
end

describe Crig::Providers::HuggingFace do
  it "supports client initialization" do
    client = Crig::Providers::HuggingFace::Client.new("dummy-key")
    client_from_builder = Crig::Providers::HuggingFace::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::HuggingFace::HUGGINGFACE_API_BASE_URL)
  end

  it "uses the request model override when present" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
      model: "meta-llama/Meta-Llama-3.1-8B-Instruct",
    )

    payload = Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("mistralai/Mistral-7B", request)
    JSON.parse(payload.to_json)["model"].as_s.should eq("meta-llama/Meta-Llama-3.1-8B-Instruct")
  end

  it "uses the default model when the request does not override it" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
    )

    payload = Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("mistralai/Mistral-7B", request)
    JSON.parse(payload.to_json)["model"].as_s.should eq("mistralai/Mistral-7B")
  end

  it "deserializes assistant and user messages like the Rust tests" do
    assistant_message = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","content":"\\n\\nHello there, how may I assist you today?"}
    )))
    assistant_message2 = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","content":[{"type":"text","text":"\\n\\nHello there, how may I assist you today?"}],"tool_calls":null}
    )))
    assistant_message3 = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","tool_calls":[{"id":"call_h89ipqYUjEpCPI6SxspMnoUU","type":"function","function":{"name":"subtract","arguments":{"x":2,"y":5}}}],"content":null,"refusal":null}
    )))
    user_message = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"user","content":[{"type":"text","text":"What's in this image?"},{"type":"image_url","image_url":{"url":"https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"}}]}
    )))

    assistant_message.kind.assistant?.should be_true
    assistant_message.assistant_content[0].text.should eq("\n\nHello there, how may I assist you today?")

    assistant_message2.kind.assistant?.should be_true
    assistant_message2.assistant_content[0].text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.tool_calls.should be_empty

    assistant_message3.kind.assistant?.should be_true
    assistant_message3.assistant_content.should be_empty
    assistant_message3.tool_calls[0].id.should eq("call_h89ipqYUjEpCPI6SxspMnoUU")
    assistant_message3.tool_calls[0].function.name.should eq("subtract")
    assistant_message3.tool_calls[0].function.arguments["x"].as_i.should eq(2)
    assistant_message3.tool_calls[0].function.arguments["y"].as_i.should eq(5)

    user_message.kind.user?.should be_true
    user_message.user_content.not_nil!.first.kind.text?.should be_true
    user_message.user_content.not_nil!.first.text.should eq("What's in this image?")
    user_message.user_content.not_nil!.to_a[1].kind.image_url?.should be_true
    user_message.user_content.not_nil!.to_a[1].image_url.not_nil!.url.should eq("https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg")
  end

  it "round-trips message conversion through the core message model" do
    user_message = Crig::Completion::Message.user("Hello")
    assistant_message = Crig::Completion::Message.assistant("Hi there!")

    converted_user = Crig::Providers::HuggingFace::Message.from_core_message(user_message)
    converted_assistant = Crig::Providers::HuggingFace::Message.from_core_message(assistant_message)

    converted_user[0].user_content.not_nil!.first.text.should eq("Hello")
    converted_assistant[0].assistant_content[0].text.should eq("Hi there!")

    converted_user[0].to_core_message.should eq(user_message)
    converted_assistant[0].to_core_message.should eq(assistant_message)
  end

  it "deserializes tool-call responses from multiple subproviders" do
    fireworks_response = Crig::Providers::HuggingFace::CompletionResponse.from_json(%(
      {"choices":[{"finish_reason":"tool_calls","index":0,"message":{"role":"assistant","tool_calls":[{"function":{"arguments":"{\\"x\\": 2, \\"y\\": 5}","name":"subtract"},"id":"call_1BspL6mQqjKgvsQbH1TIYkHf","index":0,"type":"function"}]}}],"created":1740704000,"id":"2a81f6a1-4866-42fb-9902-2655a2b5b1ff","model":"accounts/fireworks/models/deepseek-v3","object":"chat.completion","usage":{"completion_tokens":26,"prompt_tokens":248,"total_tokens":274}}
    ))
    novita_response = Crig::Providers::HuggingFace::CompletionResponse.from_json(%(
      {"choices":[{"finish_reason":"tool_calls","index":0,"logprobs":null,"message":{"audio":null,"content":null,"function_call":null,"reasoning_content":null,"refusal":null,"role":"assistant","tool_calls":[{"function":{"arguments":"{\\"x\\": \\"2\\", \\"y\\": \\"5\\"}","name":"subtract"},"id":"chatcmpl-tool-f6d2af7c8dc041058f95e2c2eede45c5","type":"function"}]},"stop_reason":128008}],"created":1740704592,"id":"chatcmpl-a92c60ae125c47c998ecdcb53387fed4","model":"meta-llama/Meta-Llama-3.1-8B-Instruct-fast","object":"chat.completion","prompt_logprobs":null,"service_tier":null,"system_fingerprint":null,"usage":{"completion_tokens":28,"completion_tokens_details":null,"prompt_tokens":335,"prompt_tokens_details":null,"total_tokens":363}}
    ))

    fireworks_response.choices.first.message.tool_calls.first.function.arguments["x"].as_i.should eq(2)
    novita_response.choices.first.message.tool_calls.first.function.arguments["x"].as_s.should eq("2")
  end

  it "silently skips assistant reasoning-only history items" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    Crig::Providers::HuggingFace::Message.from_core_message(assistant).should eq([] of Crig::Providers::HuggingFace::Message)
  end

  it "preserves assistant text and tool calls when reasoning is present" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("visible").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "subtract", JSON.parse(%({"x":2,"y":1}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    converted = Crig::Providers::HuggingFace::Message.from_core_message(assistant)

    converted.size.should eq(1)
    converted[0].assistant_content.map(&.text).should eq(["visible"])
    converted[0].tool_calls.size.should eq(1)
    converted[0].tool_calls[0].id.should eq("call_1")
    converted[0].tool_calls[0].function.name.should eq("subtract")
    converted[0].tool_calls[0].function.arguments["x"].as_i.should eq(2)
  end

  it "errors when all request messages are filtered out" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(
        Crig::Completion::Message.new(
          Crig::Completion::Message::Role::Assistant,
          Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
            Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          ),
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, "HuggingFace request has no provider-compatible messages after conversion") do
      Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("meta/test-model", request)
    end
  end
end

describe Crig::Providers::Mistral do
  it "supports client initialization" do
    client = Crig::Providers::Mistral::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Mistral::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Mistral::MISTRAL_API_BASE_URL)
  end

  it "deserializes completion responses" do
    response = Crig::Providers::Mistral::CompletionResponse.from_json(%(
      {"id":"cmpl-e5cc70bb28c444948073e77776eb30ef","object":"chat.completion","model":"mistral-small-latest","usage":{"prompt_tokens":16,"completion_tokens":34,"total_tokens":50},"created":1702256327,"choices":[{"index":0,"message":{"content":"string","tool_calls":[{"id":"null","type":"function","function":{"name":"string","arguments":"{ }"},"index":0}],"prefix":false,"role":"assistant"},"finish_reason":"stop"}]}
    ))

    response.model.should eq(Crig::Providers::Mistral::MISTRAL_SMALL)
    response.id.should eq("cmpl-e5cc70bb28c444948073e77776eb30ef")
    response.usage.not_nil!.prompt_tokens.should eq(16)
    response.usage.not_nil!.completion_tokens.should eq(34)
    response.usage.not_nil!.total_tokens.should eq(50)
    response.choices.size.should eq(1)
  end

  it "skips assistant reasoning during message conversion" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    Crig::Providers::Mistral::Message.from_core_message(assistant).should eq([] of Crig::Providers::Mistral::Message)
  end

  it "preserves assistant text and tool calls when reasoning is present" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("visible").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "subtract", JSON.parse(%({"x":2,"y":1}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    converted = Crig::Providers::Mistral::Message.from_core_message(assistant)

    converted.size.should eq(1)
    converted[0].content.should eq("visible")
    converted[0].tool_calls.size.should eq(1)
    converted[0].tool_calls[0].id.should eq("call_1")
    converted[0].tool_calls[0].function.name.should eq("subtract")
    converted[0].tool_calls[0].function.arguments["x"].as_i.should eq(2)
  end

  it "maps streaming assistant content while skipping reasoning" do
    Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.reasoning("hidden")
    ).should be_nil

    text_choice = Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.text("visible")
    )
    text_choice.should eq(Crig::RawStreamingChoice(Crig::Providers::Mistral::CompletionResponse).message("visible"))

    tool_choice = Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.tool_call("call_2", "add", JSON.parse(%({"x":2,"y":3})))
    )
    tool_choice.should_not be_nil
    tool_choice.not_nil!.kind.tool_call?.should be_true
    tool_choice.not_nil!.tool_call.not_nil!.id.should eq("call_2")
    tool_choice.not_nil!.tool_call.not_nil!.name.should eq("add")
    tool_choice.not_nil!.tool_call.not_nil!.arguments.should eq(JSON.parse(%({"x":2,"y":3})))
  end

  it "errors when all request messages are filtered out" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(
        Crig::Completion::Message.new(
          Crig::Completion::Message::Role::Assistant,
          Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
            Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          ),
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, "Mistral request has no provider-compatible messages after conversion") do
      Crig::Providers::Mistral::MistralCompletionRequest.from_request(Crig::Providers::Mistral::MISTRAL_SMALL, request)
    end
  end

  it "deserializes mistral transcription responses" do
    response = Crig::Providers::Mistral::MistralTranscriptionResponse.from_json(%(
      {"model":"voxtral-mini-latest","text":"The sun was setting slowly, casting long shadows across the empty field.","language":null,"segments":[{"text":"The sun was setting slowly, casting long shadows across the empty field.","start":0.2,"end":4.6,"speaker_id":"speaker_1","type":"transcription_segment"}],"usage":{"prompt_audio_seconds":5,"prompt_tokens":5,"total_tokens":404,"completion_tokens":24,"prompt_tokens_details":{"cached_tokens":368}},"finish_reason":null}
    ))

    response.language.should be_nil
    response.model.should eq(Crig::Providers::Mistral::VOXTRAL_MINI)
    response.segments.size.should eq(1)
    response.segments[0].start.should eq(0.2_f32)
    response.segments[0].end.should eq(4.6_f32)
    response.segments[0].speaker_id.should eq("speaker_1")
    response.segments[0].segment_type.should eq("transcription_segment")
    response.usage.prompt_audio_seconds.should eq(5)
    response.usage.prompt_tokens.should eq(5)
    response.usage.total_tokens.should eq(404)
    response.usage.prompt_tokens_details.not_nil!["cached_tokens"].as_i.should eq(368)
  end

  it "converts mistral transcription responses into core responses" do
    mistral_response = Crig::Providers::Mistral::MistralTranscriptionResponse.new(
      model: Crig::Providers::Mistral::VOXTRAL_MINI,
      segments: [
        Crig::Providers::Mistral::SegmentChunk.new(
          0.0_f32,
          1.0_f32,
          "Lorem Ipsum is simply dummy text of the printing and typesetting industry.",
          segment_type: "speech",
        ),
      ],
      text: "Lorem Ipsum is simply dummy text of the printing and typesetting industry.",
      usage: Crig::Providers::Mistral::TranscriptionUsage.new(
        prompt_audio_seconds: 1,
        prompt_tokens: 10,
        total_tokens: 20,
        completion_tokens: 10,
      ),
      language: "en",
    )

    response = mistral_response.to_crig_response

    response.text.should eq("Lorem Ipsum is simply dummy text of the printing and typesetting industry.")
    response.response.model.should eq(Crig::Providers::Mistral::VOXTRAL_MINI)
    response.response.language.should eq("en")
  end
end

describe Crig::Completion::MimeType do
  it "round-trips known media types" do
    image = Crig::Completion::MimeType.from_mime_type("image/png")
    document = Crig::Completion::MimeType.from_mime_type("text/plain")
    audio = Crig::Completion::MimeType.from_mime_type("audio/mp3")
    video = Crig::Completion::MimeType.from_mime_type("video/webm")

    image.should_not be_nil
    document.should_not be_nil
    audio.should_not be_nil
    video.should_not be_nil

    Crig::Completion::MimeType.to_mime_type(image.as(Crig::Completion::MediaType)).should eq("image/png")
    Crig::Completion::MimeType.to_mime_type(document.as(Crig::Completion::MediaType)).should eq("text/plain")
    Crig::Completion::MimeType.to_mime_type(audio.as(Crig::Completion::MediaType)).should eq("audio/mp3")
    Crig::Completion::MimeType.to_mime_type(video.as(Crig::Completion::MediaType)).should eq("video/webm")
  end
end

describe Crig::Completion::DocumentSourceKind do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::DocumentSourceKind.url("https://example.com/file"),
      Crig::Completion::DocumentSourceKind.base64("Zm9v"),
      Crig::Completion::DocumentSourceKind.raw(Bytes[1_u8, 2_u8, 3_u8]),
      Crig::Completion::DocumentSourceKind.string("hello"),
      Crig::Completion::DocumentSourceKind.unknown,
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::DocumentSourceKind.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.string_value.should eq(variant.string_value)
      roundtrip.bytes_value.should eq(variant.bytes_value)
    end
  end
end

describe Crig::Completion::Reasoning do
  it "tracks reasoning constructors and accessors" do
    reasoning = Crig::Completion::Reasoning.new_with_signature("hello", "sig")
      .with_id("reason-1")

    reasoning.first_text.should eq("hello")
    reasoning.first_signature.should eq("sig")
    reasoning.id.should eq("reason-1")
    reasoning.display_text.should eq("hello")
  end

  it "tracks encrypted and summary content" do
    encrypted = Crig::Completion::Reasoning.encrypted("secret")
    encrypted.encrypted_content.should eq("secret")

    summary = Crig::Completion::Reasoning.summaries(["one", "two"])
    summary.display_text.should eq("one\ntwo")
  end
end

describe Crig::Completion::ReasoningContent, tags: %w[completion content] do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::ReasoningContent.text("plain", "sig"),
      Crig::Completion::ReasoningContent.encrypted("opaque"),
      Crig::Completion::ReasoningContent.redacted("redacted"),
      Crig::Completion::ReasoningContent.summary("summary"),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::ReasoningContent.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.text.should eq(variant.text)
      roundtrip.signature.should eq(variant.signature)
      roundtrip.data.should eq(variant.data)
      roundtrip.summary.should eq(variant.summary)
    end
  end
end

describe Crig::Completion::ToolResultContent, tags: %w[completion content] do
  it "parses text tool output" do
    content = Crig::Completion::ToolResultContent.from_tool_output("plain text")
    text = content.first.text
    text.should_not be_nil

    content.first.kind.text?.should be_true
    text.as(Crig::Completion::Text).text.should eq("plain text")
  end

  it "parses image tool output" do
    content = Crig::Completion::ToolResultContent.from_tool_output(%({"type":"image","data":"https://example.com/image.png","mimeType":"image/png"}))
    image = content.first.image
    image.should_not be_nil

    content.first.kind.image?.should be_true
    image.as(Crig::Completion::Image).try_into_url.should eq("https://example.com/image.png")
  end

  it "builds raw image content helpers" do
    content = Crig::Completion::ToolResultContent.image_raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG)
    image = content.image

    content.kind.image?.should be_true
    image.should_not be_nil
    image.as(Crig::Completion::Image).data.kind.raw?.should be_true
  end
end

describe Crig::Completion::Usage, tags: %w[completion usage] do
  it "accumulates usage totals" do
    a = Crig::Completion::Usage.new(
      input_tokens: 1,
      output_tokens: 2,
      total_tokens: 3,
      cached_input_tokens: 4,
    )
    b = Crig::Completion::Usage.new(
      input_tokens: 10,
      output_tokens: 20,
      total_tokens: 30,
      cached_input_tokens: 40,
    )

    (a + b).should eq(
      Crig::Completion::Usage.new(
        input_tokens: 11,
        output_tokens: 22,
        total_tokens: 33,
        cached_input_tokens: 44,
      )
    )
  end

  it "supports in-place accumulation" do
    usage = Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3, cached_input_tokens: 4)
    usage.add!(Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 20, total_tokens: 30, cached_input_tokens: 40))

    usage.should eq(
      Crig::Completion::Usage.new(
        input_tokens: 11,
        output_tokens: 22,
        total_tokens: 33,
        cached_input_tokens: 44,
      )
    )
  end
end

describe Crig::Completion::CompletionResponse do
  it "stores assistant content, usage, and raw response" do
    response = Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("hello")),
      Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3),
      "raw",
      "msg-1",
    )

    response.choice.first.kind.text?.should be_true
    response.usage.total_tokens.should eq(3)
    response.raw_response.should eq("raw")
    response.message_id.should eq("msg-1")
  end
end

describe Crig::Completion::ToolDefinition, tags: %w[completion tool] do
  it "round-trips via JSON::Serializable" do
    definition = Crig::Completion::ToolDefinition.new(
      "weather",
      "Fetch weather",
      JSON.parse(%({"type":"object"}))
    )

    parsed = Crig::Completion::ToolDefinition.from_json(definition.to_json)

    parsed.name.should eq("weather")
    parsed.description.should eq("Fetch weather")
    parsed.parameters["type"].as_s.should eq("object")
  end
end

describe Crig::ToolError do
  it "wraps tool-call errors with the upstream prefix" do
    error = Crig::ToolError.tool_call_error(Exception.new("boom"))

    error.message.should eq("ToolCallError: boom")
    error.kind.should eq(Crig::ToolError::Kind::ToolCallError)
  end

  it "does not double-wrap tool-call errors" do
    error = Crig::ToolError.tool_call_error(Exception.new("ToolCallError: boom"))

    error.message.should eq("ToolCallError: boom")
    error.kind.should eq(Crig::ToolError::Kind::ToolCallError)
  end

  it "wraps json errors with the upstream prefix" do
    error = Crig::ToolError.json_error(Exception.new("bad json"))

    error.message.should eq("JsonError: bad json")
    error.kind.should eq(Crig::ToolError::Kind::JsonError)
    error.source_error.should be_a(Exception)
  end
end

describe Crig::ToolDyn do
  it "serializes typed tool output from parsed json args" do
    tool = EchoTool.new

    tool.call(%({"value":"hello"})).should eq(%("hello"))
  end

  it "uses the default NAME-backed tool name when not overridden" do
    DefaultNamedTool.new.name.should eq("default-named")
  end

  it "wraps json parse failures as tool errors" do
    tool = EchoTool.new

    expect_raises(Crig::ToolError, "JsonError: Unexpected char") do
      tool.call("not-json")
    end
  end

  it "wraps tool call failures as tool errors" do
    tool = FailingEchoTool.new

    expect_raises(Crig::ToolError, "ToolCallError: boom") do
      tool.call(%({"value":"hello"}))
    end
  end

  it "preserves recursive tool call prefixes" do
    tool = RecursiveFailingTool.new

    expect_raises(Crig::ToolError, "ToolCallError: already wrapped") do
      tool.call(%({"value":"hello"}))
    end
  end

  it "lets agents act as dynamic tools" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"

      class ProbeToolModel
        include Crig::Completion::CompletionModel

        property last_request : Crig::Completion::Request::CompletionRequest?
        getter model : String

        def initialize(@model : String)
        end

        def name : String
          @model
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(
              Crig::Completion::AssistantContent.text("completion:#{@model}")
            ),
            Crig::Completion::Usage.new,
            "raw:#{@model}",
          )
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          @last_request = request
          ["chunk:#{@model}"]
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
        end
      end

      model = ProbeToolModel.new("agent-tool")
      agent = Crig::AgentBuilder(ProbeToolModel).new(model).name("calculator_agent").build
      response = agent.call(%({"prompt":"Calculate 2 - 5"}))
      request = model.last_request.not_nil!

      puts(JSON.build do |json|
        json.object do
          json.field "name", agent.name
          json.field "definition_name", agent.definition("").name
          json.field "response", response
          json.field "prompt", request.chat_history.last.rag_text
        end
      end)
    CRYSTAL

    result["name"].as_s.should eq("calculator_agent")
    result["definition_name"].as_s.should eq("calculator_agent")
    result["response"].as_s.should eq("completion:agent-tool")
    result["prompt"].as_s.should eq("Calculate 2 - 5")
  end
end

describe "Crig.rig_tool" do
  it "ports the calculator rig_tool test" do
    tool = Calculator.new
    definition = tool.definition("")

    tool.name.should eq("calculator")
    definition.name.should eq("calculator")
    definition.description.should eq("Perform basic arithmetic operations")
    definition.parameters["properties"]["x"]["description"].as_s.should eq("First number in the calculation")
    definition.parameters["required"].as_a.map(&.as_s).should eq(["x", "y", "operation"])

    [
      {CalculatorParameters.new(5, 3, "add"), 8},
      {CalculatorParameters.new(5, 3, "subtract"), 2},
      {CalculatorParameters.new(5, 3, "multiply"), 15},
      {CalculatorParameters.new(6, 2, "divide"), 3},
    ].each do |input, expected|
      tool.call(input.to_json).should eq(expected.to_json)
    end

    expect_raises(Crig::ToolError, "ToolCallError: Division by zero") do
      tool.call(CalculatorParameters.new(5, 0, "divide").to_json)
    end

    expect_raises(Crig::ToolError, "ToolCallError: Unknown operation: power") do
      tool.call(CalculatorParameters.new(5, 3, "power").to_json)
    end

    SyncCalculator.new.call(SyncCalculatorParameters.new(5, 3, "add").to_json).should eq("8")
    CALCULATOR.name.should eq("calculator")
    SYNC_CALCULATOR.name.should eq("sync_calculator")
  end

  it "uses the default description when one is not provided" do
    tool = CountRs.new
    definition = tool.definition("")

    definition.description.should eq("Function to count_rs")
    tool.call(CountRsParameters.new("Rig rocks").to_json).should eq("2")
  end
end

describe Crig::ThinkTool do
  it "exposes the think error as a normal crystal exception" do
    Crig::ThinkError.new("boom").message.should eq("boom")
  end

  it "builds the upstream think definition" do
    tool = Crig::ThinkTool.new
    definition = tool.definition("")

    definition.name.should eq("think")
    definition.description.should contain("Use the tool to think about something")
    definition.parameters["required"][0].as_s.should eq("thought")
  end

  it "echoes the thought content back" do
    tool = Crig::ThinkTool.new

    tool.call(%({"thought":"I should verify the user"})).should eq(%("I should verify the user"))
  end
end

describe Crig::ToolSet do
  it "builds from tools and returns definitions" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new])

    toolset.contains("echo").should be_true
    toolset.get_tool_definitions.map(&.name).should eq(["echo"])
  end

  it "adds tools, merges toolsets, and deletes tools" do
    toolset = Crig::ToolSet.new
    toolset.add_tool(EchoTool.new)
    toolset.contains("echo").should be_true

    extra = Crig::ToolSet.from_tools([Crig::ThinkTool.new])
    toolset.add_tools(extra)
    toolset.contains("think").should be_true

    toolset.delete_tool("echo")
    toolset.contains("echo").should be_false
    toolset.tools.size.should eq(1)
  end

  it "calls tools by name" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new])

    toolset.call("echo", %({"value":"hello"})).should eq(%("hello"))
  end

  it "raises not found errors for missing tools" do
    toolset = Crig::ToolSet.new

    error = expect_raises(Crig::ToolSetError, "ToolNotFoundError: missing") do
      toolset.call("missing", "{}")
    end

    error.kind.should eq(Crig::ToolSetError::Kind::ToolNotFoundError)
    error.source_error.should be_nil
  end

  it "wraps tool call errors as tool set errors" do
    toolset = Crig::ToolSet.from_tools([FailingEchoTool.new])

    error = expect_raises(Crig::ToolSetError, "ToolCallError: boom") do
      toolset.call("echo", %({"value":"hello"}))
    end

    error.kind.should eq(Crig::ToolSetError::Kind::ToolCallError)
    error.source_error.should be_a(Crig::ToolError)
  end

  it "returns schemas for embedding-backed tools only" do
    toolset = Crig::ToolSet.builder
      .static_tool(EchoTool.new)
      .dynamic_tool(EmbeddedEchoTool.new)
      .build

    schemas = toolset.schemas

    schemas.size.should eq(1)
    schemas.first.name.should eq("embedded-echo")
    schemas.first.context["category"].as_s.should eq("utility")
    schemas.first.embedding_docs.should eq(["Echo values back to the caller."])
  end

  it "initializes embedding-backed tools from runtime state and stored context" do
    tool = StatefulEmbeddedEchoTool.init("runtime", EmbeddedEchoContext.new("utility"))

    tool.call_typed(EchoArgs.new("hello")).should eq("runtime:utility:hello")
    tool.context["category"].as_s.should eq("utility")
    tool.embedding_docs.should eq(["runtime:utility"])
  end

  it "returns documents for all tools" do
    toolset = Crig::ToolSet.from_tools([EchoTool.new, Crig::ThinkTool.new])
    documents = toolset.documents

    documents.size.should eq(2)
    documents.map(&.id).should contain("echo")
    documents.map(&.id).should contain("think")
    documents.each do |doc|
      doc.text.should contain("Tool: #{doc.id}")
      doc.text.should contain("Definition:")
    end
  end
end

describe Crig::ToolSetBuilder do
  it "builds static and dynamic tools into a toolset" do
    toolset = Crig::ToolSet.builder
      .static_tool(EchoTool.new)
      .dynamic_tool(EmbeddedEchoTool.new)
      .build

    toolset.contains("echo").should be_true
    toolset.contains("embedded-echo").should be_true
  end
end

describe Crig::ToolType do
  it "returns the wrapped tool name for embedding tools" do
    Crig::ToolType.embedding(EmbeddedEchoTool.new).name.should eq("embedded-echo")
  end
end

describe Crig::ToolServer do
  it "handles append_toolset requests through the server handle" do
    handle = Crig::ToolServer.new.run
    handle.append_toolset(Crig::ToolSet.from_tools([EchoTool.new]))

    handle.call_tool("echo", %({"value":"hello"})).should eq(%("hello"))
    handle.get_tool_defs(nil).should eq([] of Crig::Completion::ToolDefinition)
  end

  it "adds tools, returns definitions, calls them, and removes them through the handle" do
    server = Crig::ToolServer.new
    handle = server.run

    handle.add_tool(EchoTool.new)
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.call_tool("echo", %({"value":"hello"})).should eq(%("hello"))

    handle.remove_tool("echo")
    handle.get_tool_defs(nil).should eq([] of Crig::Completion::ToolDefinition)
  end

  it "returns static and dynamic tool definitions for prompted lookup" do
    dynamic_toolset = Crig::ToolSet.from_tools([DefaultNamedTool.new])
    server = Crig::ToolServer.new
      .tool(EchoTool.new)
      .dynamic_tools(1, MockToolIndex.new(["default-named"]), dynamic_toolset)
    handle = server.run

    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.get_tool_defs("find extra").map(&.name).sort.should eq(["default-named", "echo"])
  end

  it "ignores missing dynamic tool implementations when building tool definitions" do
    server = Crig::ToolServer.new
      .tool(EchoTool.new)
      .dynamic_tools(1, MockToolIndex.new(["missing-tool"]), Crig::ToolSet.new)
    handle = server.run

    handle.get_tool_defs("find extra").map(&.name).should eq(["echo"])
  end

  it "wraps toolset call errors as tool server errors" do
    server = Crig::ToolServer.new.tool(FailingEchoTool.new)
    handle = server.run

    expect_raises(Crig::ToolServerError, "ToolsetError: ToolCallError: boom") do
      handle.call_tool("echo", %({"value":"hello"}))
    end
  end

  it "raises a tool server send error when a detached handle is used" do
    handle = Crig::ToolServerHandle.new("detached")

    expect_raises(Crig::ToolServerError, "SendError: Tool server handle 'detached' is not attached to a server") do
      handle.get_tool_defs(nil)
    end
  end

  it "raises a tool server send error when a resolver-backed handle has no resolver" do
    handle = Crig::ToolServerHandle.new("missing-resolver")

    expect_raises(Crig::ToolServerError, "SendError: Tool server handle 'missing-resolver' has no resolver") do
      handle.call_tool("echo", "{}")
    end
  end

  it "supports Rust-style builder helpers for static names, toolsets, and dynamic tools" do
    dynamic = {
      1_i32,
      ->(request : Crig::VectorSearchRequest) {
        request.query.should eq("find extra")
        [{1.0, "default-named"}]
      },
    }

    server = Crig::ToolServer.new
      .static_tool_names(["echo"])
      .add_tools(Crig::ToolSet.from_tools([EchoTool.new, DefaultNamedTool.new]))
      .add_dynamic_tools([dynamic])

    handle = server.run
    handle.get_tool_defs(nil).map(&.name).should eq(["echo"])
    handle.get_tool_defs("find extra").map(&.name).sort.should eq(["default-named", "echo"])
  end

  it "handles request callbacks and returns tagged responses" do
    callback_response = nil.as(Crig::ToolServerResponse?)
    server = Crig::ToolServer.new.tool(EchoTool.new)

    response = server.handle_message(
      Crig::ToolServerRequest.new(
        Crig::ToolServerRequestMessageKind.get_tool_defs(nil),
        nil,
        ->(result : Crig::ToolServerResponse) {
          callback_response = result
          nil
        }
      )
    )

    response.kind.tool_definitions?.should be_true
    response.tool_definitions.not_nil!.map(&.name).should eq(["echo"])
    callback_response.should eq(response)
  end

  it "exposes parity-style tool server error helpers" do
    Crig::ToolServerError.canceled.message.should eq("Canceled")
    Crig::ToolServerError.invalid_message(
      Crig::ToolServerResponse.tool_added
    ).message.should eq("InvalidMessage: ToolAdded")
  end

  it "executes tool calls concurrently through the running server handle" do
    sleep_ms = 100
    num_calls = 3
    handle = Crig::ToolServer.new.tool(SleeperTool.new(sleep_ms)).run
    results = Channel(String).new(num_calls)

    started_at = Time.instant

    num_calls.times do
      spawn do
        results.send(handle.call_tool("sleeper", "{}"))
      end
    end

    collected = Array(String).new(num_calls) { results.receive }
    elapsed = Time.instant - started_at

    collected.should eq([sleep_ms.to_s] * num_calls)
    elapsed.should be < (sleep_ms * 2).milliseconds
  end
end

describe Crig::McpTool do
  it "converts MCP tool definitions into completion tool definitions" do
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x"]
      )
    )

    converted = Crig::McpTool.to_tool_definition(definition)

    converted.name.should eq("sum")
    converted.description.should eq("Add numbers")
    converted.parameters["properties"].as_h["x"].as_h["type"].as_s.should eq("number")
  end

  it "builds tool definitions from MCP tools and calls text tools through an MCP client" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    tool.definition("unused").name.should eq("sum")
    tool.call(%({"x":2,"y":5})).should eq("7")
  end

  it "stringifies image and resource content blocks like the Rust MCP adapter" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "render",
      description: "Render content",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("render", "Render content", definition.input_schema) do |_request|
      blocks = [
        MCP::Protocol::TextContentBlock.new("prefix "),
        MCP::Protocol::ImageContentBlock.new("abc123", "image/png"),
        MCP::Protocol::EmbeddedResourceBlock.new(MCP::Protocol::TextResourceContents.new("file:///memo", "body", "text/plain")),
      ] of MCP::Protocol::ContentBlock
      MCP::Protocol::CallToolResult.new(blocks)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)
    tool.call("{}").should eq("prefix data:image/png;base64,abc123data:text/plain;file:///memo:body")
  end

  it "wraps MCP error results as tool call errors" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "fail",
      description: "Fail tool",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("fail", "Fail tool", definition.input_schema) do |_request|
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new("boom")] of MCP::Protocol::ContentBlock, is_error: true)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    expect_raises(Crig::ToolError, "ToolCallError: MCP tool error: boom") do
      tool.call("{}")
    end
  end

  it "raises on unsupported audio MCP content" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "audio",
      description: "Audio tool",
      input_schema: MCP::Protocol::Tool::Input.new
    )

    server.add_tool("audio", "Audio tool", definition.input_schema) do |_request|
      MCP::Protocol::CallToolResult.new([
        MCP::Protocol::AudioContentBlock.new("abc123", "audio/wav"),
      ] of MCP::Protocol::ContentBlock)
    end

    tool = Crig::McpTool.from_mcp_server(definition, client)

    expect_raises(Crig::ToolError, "ToolCallError: MCP tool error: Tool returned an error: Support for audio results from an MCP tool is currently unimplemented. Come back later!") do
      tool.call("{}")
    end
  end

  it "registers MCP tools through ToolServer#rmcp_tool" do
    client, server = build_mcp_test_client_and_server
    definition = MCP::Protocol::Tool.new(
      name: "sum",
      description: "Add numbers",
      input_schema: MCP::Protocol::Tool::Input.new(
        properties: {"x" => JSON::Any.new({"type" => JSON::Any.new("number")}), "y" => JSON::Any.new({"type" => JSON::Any.new("number")})},
        required: ["x", "y"]
      )
    )

    server.add_tool("sum", "Add numbers", definition.input_schema) do |request|
      x = request.arguments.not_nil!["x"].as_i
      y = request.arguments.not_nil!["y"].as_i
      MCP::Protocol::CallToolResult.new([MCP::Protocol::TextContentBlock.new((x + y).to_s)] of MCP::Protocol::ContentBlock)
    end

    handle = Crig::ToolServer.new.rmcp_tool(definition, client).run

    handle.get_tool_defs(nil).map(&.name).should eq(["sum"])
    handle.call_tool("sum", %({"x":3,"y":4})).should eq("7")
  end
end

describe Crig::Providers::OpenAI do
  it "adds additionalProperties false to object schemas" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "name":{"type":"string"}
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["additionalProperties"].as_bool.should be_false
  end

  it "marks all object properties as required" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "a":{"type":"string"},
        "b":{"type":"number"}
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["required"].as_a.map(&.as_s).sort.should eq(["a", "b"])
  end

  it "sanitizes refs, required properties, and additionalProperties like upstream" do
    schema = JSON.parse(%({
      "type": "object",
      "properties": {
        "location": {
          "$ref": "#/$defs/Location",
          "description": "The user's location"
        }
      },
      "$defs": {
        "Location": {
          "type": "object",
          "properties": {
            "city": { "type": "string" },
            "state": { "type": "string" }
          }
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["properties"]["location"].to_json.should eq(%({"$ref":"#/$defs/Location"}))
    sanitized["$defs"]["Location"]["additionalProperties"].should eq(JSON::Any.new(false))
    sanitized["$defs"]["Location"]["required"].as_a.map(&.as_s).should eq(["city", "state"])
  end

  it "converts oneOf to anyOf recursively" do
    schema = JSON.parse(%({
      "type": "object",
      "properties": {
        "value": {
          "oneOf": [
            {"type":"string"},
            {"type":"number"}
          ]
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["properties"]["value"]["oneOf"]?.should be_nil
    sanitized["properties"]["value"]["anyOf"].as_a.size.should eq(2)
  end

  it "recurses into nested object schemas" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "inner":{
          "type":"object",
          "properties":{
            "value":{"type":"string"}
          }
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    inner = sanitized["properties"]["inner"]
    inner["additionalProperties"].as_bool.should be_false
    inner["required"].as_a.map(&.as_s).should eq(["value"])
  end
end

describe Crig::Providers::OpenAI::Client do
  it "builds from env and preserves base_url when converting to completions_api" do
    previous_key = ENV["OPENAI_API_KEY"]?
    previous_base = ENV["OPENAI_BASE_URL"]?

    ENV["OPENAI_API_KEY"] = "env-key"
    ENV["OPENAI_BASE_URL"] = "http://127.0.0.1:9999/v1"

    client = Crig::Providers::OpenAI::Client.from_env
    completions = client.completions_api

    client.api_key.token.should eq("env-key")
    client.base_url.should eq("http://127.0.0.1:9999/v1")
    completions.api_key.token.should eq("env-key")
    completions.base_url.should eq("http://127.0.0.1:9999/v1")
  ensure
    if previous_key
      ENV["OPENAI_API_KEY"] = previous_key
    else
      ENV.delete("OPENAI_API_KEY")
    end

    if previous_base
      ENV["OPENAI_BASE_URL"] = previous_base
    else
      ENV.delete("OPENAI_BASE_URL")
    end
  end

  it "posts Responses API requests through the default completion model" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_1",
          "object":"response",
          "created_at":1,
          "status":"completed",
          "model":"gpt-4o",
          "usage":{
            "input_tokens":2,
            "input_tokens_details":{"cached_tokens":0},
            "output_tokens":1,
            "output_tokens_details":{"reasoning_tokens":0},
            "total_tokens":3
          },
          "output":[
            {
              "type":"message",
              "id":"msg_1",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"default client answer"}]
            }
          ],
          "tools":[]
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build
    )

    response.choice.first.text.not_nil!.text.should eq("default client answer")
    server.requests.first["input"].as_a.first["type"].as_s.should eq("message")

    http_server.close
  end

  it "parses Responses API streaming chunks into reasoning, tool call deltas, and final usage" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"type":"response.output_item.added","item_id":"fc_1","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"sum","arguments":{},"status":"in_progress"},"sequence_number":1}

data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"content_index":0,"sequence_number":2,"delta":"{\\"a\\":2"}

data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"content_index":0,"sequence_number":3,"delta":",\\"b\\":5}"}

data: {"type":"response.reasoning_summary_text.delta","output_index":1,"summary_index":0,"sequence_number":4,"delta":"thinking"}

data: {"type":"response.output_item.done","item_id":"rs_1","output_index":1,"item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"step 1"}],"encrypted_content":"enc_blob","status":"completed"},"sequence_number":5}

data: {"type":"response.output_item.done","item_id":"fc_1","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"sum","arguments":{"a":2,"b":5},"status":"completed"},"sequence_number":6}

data: {"type":"response.output_text.delta","output_index":2,"content_index":0,"sequence_number":7,"delta":"7"}

data: {"type":"response.completed","response":{"id":"resp_stream","object":"response","created_at":1,"status":"completed","model":"gpt-4o","usage":{"input_tokens":3,"input_tokens_details":{"cached_tokens":0},"output_tokens":4,"output_tokens_details":{"reasoning_tokens":1},"total_tokens":7},"output":[],"tools":[]},"sequence_number":8}

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+5?").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.count(&.kind.tool_call_delta?).should eq(3)
    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "thinking" }.should be_true
    items.any? { |item| item.kind.reasoning? && item.reasoning.not_nil!.content.first.summary == "step 1" }.should be_true
    items.any? { |item| item.kind.reasoning? && item.reasoning.not_nil!.encrypted_content == "enc_blob" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "sum" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "7" }.should be_true
    items.last.final.not_nil!.usage.total_tokens.should eq(7)

    http_server.close
  end

  it "auto-adds reasoning encrypted include when reasoning params are present" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_reasoning_include",
          "object":"response",
          "created_at":1,
          "status":"completed",
          "model":"gpt-4o",
          "usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2},
          "output":[
            {
              "type":"message",
              "id":"msg_reasoning_include",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"ok"}]
            }
          ],
          "tools":[]
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
      .additional_params(JSON.parse(%({"reasoning":{"effort":"low"}})))
      .build

    client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)

    request_body = server.requests.first
    request_body["include"].as_a.map(&.as_s).should contain("reasoning.encrypted_content")

    http_server.close
  end

  it "returns an error without panicking for invalid responses additional_params payloads" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
      .additional_params(JSON.parse("true"))
      .build

    expect_raises(Crig::Completion::CompletionError, /Invalid OpenAI Responses additional_params payload/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end

  it "returns an error without panicking when request reasoning content is missing an OpenAI id" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new("thought"),
        )
      ),
      "assistant_message_id",
    )
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
    )

    expect_raises(Crig::Completion::CompletionError, /OpenAI-generated ID is required/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end
end

describe Crig::Providers::OpenAI::ResponsesCompletionModel do
  it "supports the class-level with_model helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.with_model(client, "gpt-test")

    model.client.should eq(client)
    model.model.should eq("gpt-test")
  end

  it "emits summary then encrypted reasoning items from a completed reasoning output" do
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
      Crig::Providers::OpenAI::Client.new("test-key"),
      Crig::Providers::OpenAI::GPT_4O,
    )

    summary = [
      Crig::Providers::OpenAI::ReasoningSummary.new("step 1"),
      Crig::Providers::OpenAI::ReasoningSummary.new("step 2"),
    ]

    choices = model.reasoning_choices_from_done_item("rs_1", summary, "enc_blob")

    choices.size.should eq(3)
    choices[0].reasoning_id.should eq("rs_1")
    choices[0].reasoning_content.not_nil!.summary.should eq("step 1")
    choices[1].reasoning_content.not_nil!.summary.should eq("step 2")
    choices[2].reasoning_content.not_nil!.data.should eq("enc_blob")
  end

  it "emits summary-only reasoning items when encrypted content is absent" do
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
      Crig::Providers::OpenAI::Client.new("test-key"),
      Crig::Providers::OpenAI::GPT_4O,
    )

    summary = [Crig::Providers::OpenAI::ReasoningSummary.new("only summary")]
    choices = model.reasoning_choices_from_done_item("rs_2", summary, nil)

    choices.size.should eq(1)
    choices[0].reasoning_id.should eq("rs_2")
    choices[0].reasoning_content.not_nil!.summary.should eq("only summary")
  end

  it "deserializes response chunk kinds from wire values" do
    chunk = Crig::Providers::OpenAI::ResponseChunk.from_json(%({
      "type":"response.completed",
      "response":{
        "id":"resp_1",
        "object":"response",
        "created_at":1,
        "status":"completed",
        "model":"gpt-4o",
        "usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},
        "output":[],
        "tools":[]
      },
      "sequence_number":9
    }))

    chunk.kind.should eq(Crig::Providers::OpenAI::ResponseChunkKind::ResponseCompleted)
    chunk.response.id.should eq("resp_1")
    chunk.sequence_number.should eq(9)
  end

  it "deserializes output item chunks into typed payload wrappers" do
    chunk = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.output_item.done",
      "item_id":"fc_1",
      "output_index":0,
      "item":{
        "type":"function_call",
        "id":"fc_1",
        "call_id":"call_1",
        "name":"sum",
        "arguments":{"a":2,"b":5},
        "status":"completed"
      },
      "sequence_number":6
    }))

    chunk.item_id.should eq("fc_1")
    chunk.output_index.should eq(0)
    chunk.data.should be_a(Crig::Providers::OpenAI::OutputItemDone)
    output_item = chunk.data.as(Crig::Providers::OpenAI::OutputItemDone)
    output_item.message.item.kind.should eq(Crig::Providers::OpenAI::Output::Kind::FunctionCall)
    output_item.message.item.function_call.not_nil!.name.should eq("sum")
  end

  it "deserializes reasoning summary text deltas into typed chunks" do
    chunk = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.reasoning_summary_text.delta",
      "output_index":0,
      "summary_index":0,
      "sequence_number":4,
      "delta":"thinking"
    }))

    chunk.data.should be_a(Crig::Providers::OpenAI::ReasoningSummaryTextDelta)
    chunk.data.as(Crig::Providers::OpenAI::ReasoningSummaryTextDelta).chunk.delta.should eq("thinking")
  end

  it "deserializes content part chunks into typed part variants" do
    chunk = Crig::Providers::OpenAI::ContentPartChunk.from_json(%({
      "content_index":0,
      "sequence_number":3,
      "part":{"type":"output_text","text":"hello"}
    }))

    chunk.part.kind.should eq(Crig::Providers::OpenAI::ContentPartChunkPart::Kind::OutputText)
    chunk.part.text.should eq("hello")
  end

  it "deserializes summary part chunks into typed part variants" do
    chunk = Crig::Providers::OpenAI::SummaryPartChunk.from_json(%({
      "summary_index":1,
      "sequence_number":7,
      "part":{"type":"summary_text","text":"step 1"}
    }))

    chunk.part.kind.should eq(Crig::Providers::OpenAI::SummaryPartChunkPart::Kind::SummaryText)
    chunk.part.text.should eq("step 1")
  end
end

describe Crig::Providers::OpenAI::Reasoning do
  it "builds reasoning helper values like upstream" do
    reasoning = Crig::Providers::OpenAI::Reasoning.new
      .with_effort(Crig::Providers::OpenAI::ReasoningEffort::High)
      .with_summary_level(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)

    reasoning.effort.should eq(Crig::Providers::OpenAI::ReasoningEffort::High)
    reasoning.summary.should eq(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)
    reasoning.to_json_value["effort"].as_s.should eq("high")
    reasoning.to_json_value["summary"].as_s.should eq("detailed")
  end
end

describe Crig::Providers::OpenAI::AdditionalParameters do
  it "ensures reasoning requests include encrypted reasoning content" do
    params = Crig::Providers::OpenAI::AdditionalParameters.from_json_value(
      JSON.parse(%({
        "reasoning":{"effort":"high"}
      }))
    ).ensure_reasoning_include

    include_values = params.to_json_value["include"].as_a.map(&.as_s)
    include_values.should eq(["reasoning.encrypted_content"])
  end

  it "parses typed additional parameter enums from OpenAI wire values" do
    params = Crig::Providers::OpenAI::AdditionalParameters.from_json_value(
      JSON.parse(%({
        "truncation":"auto",
        "service_tier":"flex",
        "reasoning":{"effort":"high","summary":"detailed"}
      }))
    )

    params.truncation.should eq(Crig::Providers::OpenAI::TruncationStrategy::Auto)
    params.service_tier.should eq(Crig::Providers::OpenAI::OpenAIServiceTier::Flex)
    params.reasoning.not_nil!.effort.should eq(Crig::Providers::OpenAI::ReasoningEffort::High)
    params.reasoning.not_nil!.summary.should eq(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)
  end

  it "keeps structured outputs in typed text config" do
    params = Crig::Providers::OpenAI::AdditionalParameters.new.with_text(
      Crig::Providers::OpenAI::TextConfig.structured_output(
        "response_schema",
        JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
      )
    )

    text = params.to_json_value["text"]["format"]
    text["type"].as_s.should eq("json_schema")
    text["name"].as_s.should eq("response_schema")
  end
end

describe Crig::Providers::OpenAI::TextFormat do
  it "serializes the plain text format variant" do
    json = Crig::Providers::OpenAI::TextFormat.text.to_json_value

    json["type"].as_s.should eq("text")
  end

  it "serializes the json_schema format variant" do
    json = Crig::Providers::OpenAI::TextFormat.structured_output(
      "response_schema",
      JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
    ).to_json_value

    json["type"].as_s.should eq("json_schema")
    json["name"].as_s.should eq("response_schema")
    json["schema"]["properties"]["answer"]["type"].as_s.should eq("string")
  end
end

describe Crig::Providers::OpenAI::CompletionRequest do
  it "applies structured outputs and reasoning through typed helper methods" do
    request = Crig::Providers::OpenAI::CompletionRequest.new(
      input: Crig::OneOrMany(Crig::Providers::OpenAI::InputItem).one(
        Crig::Providers::OpenAI::InputItem.system_message("Be precise.")
      ),
      model: Crig::Providers::OpenAI::GPT_4O,
    )
      .with_structured_outputs(
        "response_schema",
        JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
      )
      .with_reasoning(
        Crig::Providers::OpenAI::Reasoning.new
          .with_effort(Crig::Providers::OpenAI::ReasoningEffort::High)
      )

    json = request.to_json_value
    json["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O)
    json["text"]["format"]["name"].as_s.should eq("response_schema")
    json["reasoning"]["effort"].as_s.should eq("high")
  end
end

describe Crig::Providers::OpenAI::Message do
  it "builds system messages with input_text content" do
    message = Crig::Providers::OpenAI::Message.system("Be precise.")
    json = message.to_json_value

    json["role"].as_s.should eq("system")
    json["content"].as_a.first["type"].as_s.should eq("input_text")
    json["content"].as_a.first["text"].as_s.should eq("Be precise.")
  end

  it "converts mixed user tool-result content into tool-result messages only" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool_result_id",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("done")
      ),
      call_id: "call_1",
    )
    contents = [
      Crig::Completion::UserContent.text("ignored"),
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::ToolResult,
        tool_result: tool_result,
      ),
    ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(contents)
    )

    converted = Crig::Providers::OpenAI::Message.from_core_message(message)

    converted.size.should eq(1)
    converted.first.kind.tool_result?.should be_true
    converted.first.to_json_value["type"].as_s.should eq("tool")
    converted.first.to_json_value["tool_call_id"].as_s.should eq("call_1")
    converted.first.to_json_value["output"].as_s.should eq("done")
  end

  it "converts assistant reasoning into an assistant message with reasoning content" do
    reasoning = Crig::Completion::Reasoning.new("thought").with_id("rs_1")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    converted = Crig::Providers::OpenAI::Message.from_core_message(message)

    converted.size.should eq(1)
    converted.first.kind.assistant?.should be_true
    converted.first.to_json_value["content"].as_a.first["type"].as_s.should eq("reasoning")
    converted.first.to_json_value["content"].as_a.first["id"].as_s.should eq("rs_1")
  end

  it "parses developer-role message JSON as a system message" do
    message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"developer",
        "content":[{"type":"input_text","text":"Be strict."}]
      }))
    )

    message.kind.system?.should be_true
    message.to_json_value["role"].as_s.should eq("system")
    message.to_json_value["content"].as_a.first["text"].as_s.should eq("Be strict.")
  end

  it "parses string content for system and user messages like upstream" do
    system_message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"system",
        "content":"Be strict."
      }))
    )
    user_message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"user",
        "content":"hello"
      }))
    )

    system_message.to_json_value["content"].as_a.first["text"].as_s.should eq("Be strict.")
    user_message.to_json_value["content"].as_a.first["text"].as_s.should eq("hello")
  end
end

describe Crig::Providers::OpenAI::SystemContent do
  it "builds input_text content from strings" do
    content = Crig::Providers::OpenAI::SystemContent.from_string("Be precise.")

    content.to_json_value["type"].as_s.should eq("input_text")
    content.to_json_value["text"].as_s.should eq("Be precise.")
  end
end

describe Crig::Providers::OpenAI::InputItem do
  it "serializes system_message with the merged role" do
    json = Crig::Providers::OpenAI::InputItem.system_message("Stay strict.").to_json_value

    json["role"].as_s.should eq("system")
    json["content"].as_a.first["text"].as_s.should eq("Stay strict.")
  end

  it "serializes a user message input item without duplicating the role field" do
    item = Crig::Providers::OpenAI::InputItem.new(
      Crig::Providers::OpenAI::InputContent.message(
        Crig::Providers::OpenAI::Message.user([
          Crig::Providers::OpenAI::UserContent.text("hello"),
        ])
      ),
      Crig::Providers::OpenAI::Role::User,
    )

    json = item.to_json_value.to_json
    json.scan(/"role"/).size.should eq(1)
  end

  it "does not duplicate the assistant role when converting typed assistant reasoning messages" do
    item = Crig::Providers::OpenAI::InputItem.from_message(
      Crig::Providers::OpenAI::Message.assistant([
        Crig::Providers::OpenAI::AssistantContentType.reasoning(
          Crig::Providers::OpenAI::OpenAIReasoning.new("rs_1", [] of Crig::Providers::OpenAI::ReasoningSummary)
        ),
      ], "assistant_message_id")
    )

    json = item.to_json_value
    json["type"].as_s.should eq("message")
    json["role"].as_s.should eq("assistant")
    json.to_json.scan(/"role"/).size.should eq(1)
    json["content"].as_a.first["type"].as_s.should eq("reasoning")
  end

  it "converts tool-result messages into function_call_output items without roles" do
    item = Crig::Providers::OpenAI::InputItem.from_message(
      Crig::Providers::OpenAI::Message.tool_result("call_1", "done")
    )

    json = item.to_json_value
    json["type"].as_s.should eq("function_call_output")
    json["call_id"].as_s.should eq("call_1")
    json["output"].as_s.should eq("done")
    json["role"]?.should be_nil
  end

  it "parses raw tool payloads through the message-to-input-item path" do
    item = Crig::Providers::OpenAI::InputItem.from_json_value(
      JSON.parse(%({
        "type":"tool",
        "tool_call_id":"call_2",
        "output":"ok"
      }))
    )

    json = item.to_json_value
    json["type"].as_s.should eq("function_call_output")
    json["call_id"].as_s.should eq("call_2")
    json["output"].as_s.should eq("ok")
  end

  it "errors when assistant reasoning is missing an OpenAI reasoning id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new("thought"),
        )
      ),
      "assistant_message_id",
    )

    expect_raises(Crig::Completion::CompletionError, /OpenAI-generated ID is required/) do
      Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    end
  end

  it "serializes encrypted-only reasoning content without adding summaries" do
    reasoning = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.encrypted("encrypted_blob")], "rs_1")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["type"].as_s.should eq("reasoning")
    json["id"].as_s.should eq("rs_1")
    json["encrypted_content"].as_s.should eq("encrypted_blob")
    json["summary"].as_a.size.should eq(0)
  end

  it "serializes mixed reasoning content using only text-like summaries and first opaque payload" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.text("step-1", "sig-1"),
      Crig::Completion::ReasoningContent.summary("summary-2"),
      Crig::Completion::ReasoningContent.encrypted("ciphertext"),
      Crig::Completion::ReasoningContent.redacted("redacted"),
    ], "rs_2")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["summary"].as_a.map { |entry| entry["text"].as_s }.should eq(["step-1", "summary-2"])
    json["encrypted_content"].as_s.should eq("ciphertext")
  end

  it "serializes redacted-only reasoning as encrypted content" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
    ], "rs_redacted")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value
    json["encrypted_content"].as_s.should eq("opaque-redacted")
    json["summary"].as_a.size.should eq(0)
  end

  it "requires tool result call ids when converting user tool results" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool_result_id",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("done")
      ),
    )
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: tool_result,
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, /Tool result `call_id` is required/) do
      Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    end
  end

  it "requires assistant tool call call ids when converting assistant tool calls" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.tool_call(
          "tool_1",
          "my_tool",
          JSON.parse(%({"arg":"value"}))
        )
      ),
      "assistant_message_id",
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant tool call `call_id` is required/) do
      Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    end
  end

  it "roundtrips empty reasoning content into a request item without dropping it" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_roundtrip_empty",
        "summary":[]
      }))
    )

    reasoning = output.to_assistant_content.first.reasoning.not_nil!
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["id"].as_s.should eq("rs_roundtrip_empty")
    json["summary"].as_a.size.should eq(0)
    json["encrypted_content"]?.should be_nil
  end
end

describe Crig::Providers::OpenAI::OpenAIReasoning do
  it "serializes reasoning summaries and encrypted content" do
    reasoning = Crig::Providers::OpenAI::OpenAIReasoning.new(
      "rs_1",
      [Crig::Providers::OpenAI::ReasoningSummary.new("step 1")],
      "enc_blob",
    )

    json = reasoning.to_json_value
    json["type"].as_s.should eq("reasoning")
    json["id"].as_s.should eq("rs_1")
    json["summary"].as_a.first["text"].as_s.should eq("step 1")
    json["encrypted_content"].as_s.should eq("enc_blob")
  end
end

describe Crig::Providers::OpenAI::AssistantContent do
  it "converts output_text and refusal into core assistant text content" do
    Crig::Providers::OpenAI::AssistantContent.output_text("hello").to_completion_content.text.not_nil!.text.should eq("hello")
    Crig::Providers::OpenAI::AssistantContent.refusal("no").to_completion_content.text.not_nil!.text.should eq("no")
  end
end

describe Crig::Providers::OpenAI::CompletionResponsePayload do
  it "parses typed response metadata and preserves additional parameters" do
    payload = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(%({
      "id":"resp_1",
      "object":"response",
      "created_at":1,
      "status":"completed",
      "model":"gpt-4o",
      "output":[],
      "tools":[],
      "usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},
      "service_tier":"flex"
    }))

    payload.object.should eq(Crig::Providers::OpenAI::ResponseObject::Response)
    payload.status.should eq(Crig::Providers::OpenAI::ResponseStatus::Completed)
    payload.usage.not_nil!.total_tokens.should eq(3)
    payload.additional_parameters["service_tier"].as_s.should eq("flex")
  end

  it "converts typed output into a core completion response" do
    payload = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(%({
      "id":"resp_2",
      "object":"response",
      "created_at":2,
      "status":"completed",
      "model":"gpt-4o",
      "output":[
        {
          "type":"message",
          "id":"msg_2",
          "role":"assistant",
          "status":"completed",
          "content":[{"type":"output_text","text":"hello"}]
        }
      ],
      "tools":[],
      "usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}
    }))

    response = payload.to_completion_response
    response.message_id.should eq("msg_2")
    response.choice.to_a.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(5)
  end
end

describe Crig::Providers::OpenAI::Output do
  it "converts typed message output into assistant text and preserves message id" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"message",
        "id":"msg_1",
        "role":"assistant",
        "status":"completed",
        "content":[{"type":"output_text","text":"hello"}]
      }))
    )

    output.message_id.should eq("msg_1")
    output.to_assistant_content.map(&.text.not_nil!.text).should eq(["hello"])
  end

  it "converts typed reasoning output into core reasoning content" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_1",
        "summary":[{"type":"summary_text","text":"step 1"}],
        "encrypted_content":"enc_blob"
      }))
    )

    reasoning = output.to_assistant_content.first.reasoning.not_nil!
    reasoning.id.should eq("rs_1")
    reasoning.content.first.summary.should eq("step 1")
    reasoning.content.last.data.should eq("enc_blob")
  end

  it "does not drop reasoning output when the summary is empty" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_empty",
        "summary":[]
      }))
    )

    content = output.to_assistant_content
    content.size.should eq(1)
    reasoning = content.first.reasoning.not_nil!
    reasoning.id.should eq("rs_empty")
    reasoning.content.should be_empty
  end
end

describe Crig::Providers::OpenAI::OutputReasoning do
  it "converts typed output reasoning into core reasoning content" do
    output = Crig::Providers::OpenAI::OutputReasoning.new(
      "rs_2",
      [Crig::Providers::OpenAI::ReasoningSummary.new("step 2")],
      "enc_2",
      Crig::Providers::OpenAI::ToolStatus::Completed,
    )

    reasoning = output.to_completion_content.reasoning.not_nil!
    reasoning.id.should eq("rs_2")
    reasoning.content.first.summary.should eq("step 2")
    reasoning.content.last.data.should eq("enc_2")
  end
end

describe Crig::Providers::OpenAI::ResponsesToolDefinition do
  it "sanitizes and serializes tool definitions through the typed wrapper" do
    tool = Crig::Completion::ToolDefinition.new(
      "lookup_weather",
      "Look up weather by city",
      JSON.parse(%({
        "type":"object",
        "properties":{"city":{"type":"string"}}
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    response_tool.kind.should eq("function")
    response_tool.strict?.should be_true
    response_tool.to_json_value["parameters"]["additionalProperties"].as_bool.should be_false
  end

  it "sanitizes nested object schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "first_name":{"type":"string"},
          "last_name":{"type":"string"},
          "job":{
            "type":"object",
            "properties":{
              "inner":{"type":"string"},
              "department":{
                "type":"object",
                "properties":{
                  "name":{"type":"string"}
                }
              }
            }
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end

  it "sanitizes array item object schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "employees":{
            "type":"array",
            "items":{
              "type":"object",
              "properties":{
                "name":{"type":"string"},
                "role":{"type":"string"}
              }
            }
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end

  it "sanitizes enum-like anyOf schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "name":{"type":"string"},
          "pricing":{
            "anyOf":[
              {
                "type":"object",
                "properties":{"fixed":{"type":"boolean"}}
              },
              {
                "type":"object",
                "properties":{"tiered":{"type":"boolean"}}
              }
            ]
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end
end

describe Crig::Providers::OpenAI::ToolStatus do
  it "serializes all currently tracked OpenAI tool statuses" do
    Crig::Providers::OpenAI::ToolStatus::InProgress.to_wire.should eq("in_progress")
    Crig::Providers::OpenAI::ToolStatus::Completed.to_wire.should eq("completed")
    Crig::Providers::OpenAI::ToolStatus::Incomplete.to_wire.should eq("incomplete")
  end
end

describe Crig::Providers::OpenAI::ToolResultContentType do
  it "exposes the text wire value" do
    Crig::Providers::OpenAI::ToolResultContentType::Text.to_wire.should eq("text")
  end
end

describe Crig::Providers::OpenAI::UserContent do
  it "serializes the tool result variant with the tool wire type" do
    json = Crig::Providers::OpenAI::UserContent.tool_result("call_1", "done").to_json_value

    json["type"].as_s.should eq("tool")
    json["tool_call_id"].as_s.should eq("call_1")
    json["output"].as_s.should eq("done")
  end
end

describe Crig::Providers::OpenAI::UserContent do
  it "serializes image and file payloads with OpenAI wire keys" do
    image = Crig::Providers::OpenAI::UserContent.image("https://example.com/cat.png", "high")
    file = Crig::Providers::OpenAI::UserContent.file(file_url: "https://example.com/doc.pdf", filename: "doc.pdf")

    image.to_json_value["type"].as_s.should eq("input_image")
    image.to_json_value["image_url"].as_s.should eq("https://example.com/cat.png")
    image.to_json_value["detail"].as_s.should eq("high")

    file.to_json_value["type"].as_s.should eq("input_file")
    file.to_json_value["file_url"].as_s.should eq("https://example.com/doc.pdf")
    file.to_json_value["filename"].as_s.should eq("doc.pdf")
  end
end

describe Crig::Providers::OpenAI::AssistantContentType do
  it "serializes text assistant content through the typed wrapper" do
    content = Crig::Providers::OpenAI::AssistantContentType.text(
      Crig::Providers::OpenAI::AssistantContent.output_text("done")
    )

    json = content.to_json_value
    json["type"].as_s.should eq("output_text")
    json["text"].as_s.should eq("done")
  end
end

describe Crig::Providers::OpenAI::CompletionsClient do
  it "supports the rust-shaped chat completion helper layer" do
    core_tool = Crig::Completion::ToolDefinition.new(
      "lookup",
      "Look up a value",
      JSON.parse(%({"type":"object","properties":{"query":{"type":"string"}}}))
    )
    request = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(
      Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(
        Crig::Providers::OpenAI::GPT_4O,
        Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
          .tool(core_tool)
          .build,
        strict_tools: true,
        tool_result_array_content: true,
      )
    )

    request.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    request.messages.first.kind.system?.should be_false
    request.messages.first.kind.user?.should be_true
    request.tools.first.function.strict?.should eq(true)
    request.tools.first.function.parameters["additionalProperties"].as_bool.should be_false
  end

  it "converts typed chat completion responses into core completion responses" do
    response = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"chatcmpl-typed",
      "object":"chat.completion",
      "created":1,
      "model":"gpt-4o",
      "choices":[
        {
          "index":0,
          "message":{
            "role":"assistant",
            "content":[{"type":"text","text":"typed answer"}],
            "tool_calls":[]
          },
          "logprobs":null,
          "finish_reason":"stop"
        }
      ],
      "usage":{"prompt_tokens":2,"total_tokens":5}
    })))

    converted = response.to_completion_response(JSON.parse(response.to_json))

    converted.choice.first.text.not_nil!.text.should eq("typed answer")
    converted.usage.total_tokens.should eq(5)
    converted.message_id.should eq("chatcmpl-typed")
  end

  it "supports completion model class and builder helpers" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    model = Crig::Providers::OpenAI::CompletionModel.with_model(client, Crig::Providers::OpenAI::GPT_4O)
      .with_tool_result_array_content
      .with_strict_tools

    model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    model.tool_result_array_content?.should be_true
    model.strict_tools?.should be_true
    model.into_agent_builder.build.should be_a(Crig::Agent(Crig::Providers::OpenAI::CompletionModel))
  end

  it "posts chat completions requests and respects request model overrides and max_tokens" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-final",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o-mini",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"final answer","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":2,"total_tokens":5}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::OpenAI::GPT_4O)
    request = model
      .completion_request("What is 2+5?")
      .model(Crig::Providers::OpenAI::GPT_4O_MINI)
      .preamble("system prompt")
      .max_tokens(42)
      .build

    response = model.completion(request)

    response.choice.first.text.not_nil!.text.should eq("final answer")
    response.usage.total_tokens.should eq(5)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O_MINI)
    posted["max_tokens"].as_i64.should eq(42)
    posted["messages"].as_a.first["role"].as_s.should eq("system")
    posted["messages"].as_a.last["content"].as_s.should eq("What is 2+5?")

    http_server.close
  end

  it "uses the model default when the request override is unset and omits max_tokens when none" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-default-model",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"ok","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":1,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::OpenAI::GPT_4O)
    request = model.completion_request("Hello").build

    model.completion(request)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O)
    posted["max_tokens"]?.should be_nil

    http_server.close
  end

  it "skips assistant reasoning while preserving assistant text and tool calls" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-reasoning-filter",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"ok","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":1,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    reasoning = Crig::Completion::Reasoning.new("think").with_id("rs_1")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        ),
        Crig::Completion::AssistantContent.text("visible text"),
        Crig::Completion::AssistantContent.tool_call("tool_1", "subtract", JSON.parse(%({"x":2,"y":5}))),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
      "assistant_message_id",
    )

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
      model: Crig::Providers::OpenAI::GPT_4O,
    )

    client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)

    posted = server.requests.first["messages"].as_a.first
    posted["role"].as_s.should eq("assistant")
    posted["content"].as_a.map { |entry| entry["text"].as_s }.should eq(["visible text"])
    posted["tool_calls"].as_a.size.should eq(1)
    posted["tool_calls"].as_a.first["function"]["name"].as_s.should eq("subtract")

    http_server.close
  end

  it "errors when all chat completion messages are filtered out during conversion" do
    reasoning = Crig::Completion::Reasoning.new("think").with_id("rs_1")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
      model: Crig::Providers::OpenAI::GPT_4O,
    )

    expect_raises(Crig::Completion::CompletionError, /no provider-compatible messages after conversion/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end

  it "parses streaming text and tool call deltas into the generic streaming response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"chatcmpl-stream","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"sum","arguments":"a"}}]}}]}

data: {"id":"chatcmpl-stream","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"b"}}]}}],"usage":{"prompt_tokens":3,"total_tokens":7}}

data: {"id":"chatcmpl-stream","choices":[{"delta":{"content":"7"}}]}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+5?").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    response.each_item { |item| items << item }

    items.select(&.kind.tool_call_delta?).size.should eq(3)
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "sum" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "7" }.should be_true
    items.last.kind.final?.should be_true
    response.message_id.should eq("chatcmpl-stream")

    http_server.close
  end
end

describe Crig::Providers::OpenAI::Client do
  it "deserializes typed openai chat messages" do
    assistant_message = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"\\n\\nHello there, how may I assist you today?"
    })))
    assistant_message2 = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":[{"type":"text","text":"\\n\\nHello there, how may I assist you today?"}],
      "tool_calls":null
    })))
    assistant_message3 = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "tool_calls":[{"id":"call_h89ipqYUjEpCPI6SxspMnoUU","type":"function","function":{"name":"subtract","arguments":"{\\"x\\": 2, \\"y\\": 5}"}}],
      "content":null,
      "refusal":null
    })))
    user_message = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":[
        {"type":"text","text":"What's in this image?"},
        {"type":"image_url","image_url":{"url":"https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"}},
        {"type":"input_audio","input_audio":{"data":"...","format":"mp3"}}
      ]
    })))

    assistant_message.assistant_content.first.text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.assistant_content.first.text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.tool_calls.should eq([] of Crig::Providers::OpenAI::Chat::ToolCall)
    assistant_message3.assistant_content.should eq([] of Crig::Providers::OpenAI::Chat::AssistantContent)
    assistant_message3.tool_calls.first.function.name.should eq("subtract")
    assistant_message3.tool_calls.first.function.arguments.should eq(JSON.parse(%({"x":2,"y":5})))
    user_message.user_content.not_nil!.first.text.should eq("What's in this image?")
    user_message.user_content.not_nil!.to_a[1].image_url.not_nil!.url.should contain("Gfp-wisconsin-madison")
  end

  it "round-trips between core messages and openai chat messages" do
    user_message = Crig::Completion::Message.user("Hello")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("Hi there!")
      )
    )

    converted_user_message = Crig::Providers::OpenAI::Chat::Message.from_core_message(user_message)
    converted_assistant_message = Crig::Providers::OpenAI::Chat::Message.from_core_message(assistant_message)

    converted_user_message.first.user_content.not_nil!.first.text.should eq("Hello")
    converted_assistant_message.first.assistant_content.first.text.should eq("Hi there!")

    converted_user_message.first.to_core_message.should eq(user_message)
    converted_assistant_message.first.to_core_message.should eq(assistant_message)
  end

  it "serializes single-text user messages as strings" do
    user_message = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).one(
        Crig::Providers::OpenAI::Chat::UserContent.text("Hello world")
      )
    )

    serialized = user_message.to_json_value

    serialized["role"].as_s.should eq("user")
    serialized["content"].as_s.should eq("Hello world")
  end

  it "serializes multi-part and single-image user messages as arrays" do
    multi_part = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).many([
        Crig::Providers::OpenAI::Chat::UserContent.text("What's in this image?"),
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/image.jpg"),
      ])
    )
    single_image = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).one(
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/image.jpg")
      )
    )

    multi_part.to_json_value["content"].as_a.size.should eq(2)
    single_image.to_json_value["content"].as_a.size.should eq(1)
  end

  it "supports openai client builders" do
    client = Crig::Providers::OpenAI::Client.builder
      .api_key("dummy-key")
      .base_url("https://example.com/v1")
      .build
    completions_client = Crig::Providers::OpenAI::CompletionsClient.builder
      .api_key("dummy-key")
      .base_url("https://example.com/v1")
      .build

    client.base_url.should eq("https://example.com/v1")
    completions_client.base_url.should eq("https://example.com/v1")
  end
end

describe Crig::Providers::OpenAI::EmbeddingModel do
  it "posts embedding requests and maps returned vectors back to documents" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[
            {"object":"embedding","embedding":[0.1,0.2],"index":0},
            {"object":"embedding","embedding":[0.3,0.4],"index":1}
          ],
          "model":"text-embedding-3-small",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::OpenAI::TEXT_EMBEDDING_3_SMALL)
    embeddings = model.embed_texts(["alpha", "beta"])

    embeddings.map(&.document).should eq(["alpha", "beta"])
    embeddings.map(&.vec).should eq([[0.1, 0.2], [0.3, 0.4]])
    model.ndims.should eq(1536)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::TEXT_EMBEDDING_3_SMALL)
    posted["input"].as_a.map(&.as_s).should eq(["alpha", "beta"])
    posted["dimensions"].as_i.should eq(1536)

    http_server.close
  end

  it "supports explicit ndims, encoding format, and user request fields" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[1.0],"index":0}],
          "model":"custom-embed",
          "usage":{"prompt_tokens":1,"total_tokens":1}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = Crig::Providers::OpenAI::EmbeddingModel
      .with_encoding_format(client, "custom-embed", 256, Crig::Providers::OpenAI::EncodingFormat::Base64)
      .user("user_123")

    model.embed_text("hello").vec.should eq([1.0])

    posted = server.requests.first
    posted["dimensions"].as_i.should eq(256)
    posted["encoding_format"].as_s.should eq("base64")
    posted["user"].as_s.should eq("user_123")

    http_server.close
  end

  it "omits dimensions for text-embedding-ada-002 and validates response length" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1],"index":0}],
          "model":"text-embedding-ada-002",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002)

    expect_raises(Crig::Embeddings::EmbeddingError, /does not match input length/) do
      model.embed_texts(["one", "two"])
    end

    posted = server.requests.first
    posted["dimensions"]?.should be_nil

    http_server.close
  end
end

describe Crig::Providers::OpenAI::ImageGenerationModel do
  it "posts image generation requests and decodes the returned base64 image" do
    encoded = Base64.strict_encode("png-bytes")
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.image_generation_model(Crig::Providers::OpenAI::DALL_E_3)
      .image_generation(Crig::ImageGenerationRequest.new("A cat", 1024, 1024))

    String.new(response.image).should eq("png-bytes")
    response.response.created.should eq(1)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::DALL_E_3)
    posted["prompt"].as_s.should eq("A cat")
    posted["size"].as_s.should eq("1024x1024")
    posted["response_format"].as_s.should eq("b64_json")

    http_server.close
  end

  it "omits response_format for gpt-image-1 and merges additional params" do
    encoded = Base64.strict_encode("img")
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = client.image_generation_model(Crig::Providers::OpenAI::GPT_IMAGE_1)
      .image_generation_request
      .prompt("A tree")
      .width(512)
      .height(768)
      .additional_params(JSON.parse(%({"quality":"high"})))
      .build

    client.image_generation_model(Crig::Providers::OpenAI::GPT_IMAGE_1).image_generation(request)

    posted = server.requests.first
    posted["response_format"]?.should be_nil
    posted["quality"].as_s.should eq("high")
    posted["size"].as_s.should eq("512x768")

    http_server.close
  end

  it "surfaces provider errors for non-success responses" do
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         "invalid request",
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::ImageGenerationError, /BAD_REQUEST: invalid request/) do
      client.image_generation_model(Crig::Providers::OpenAI::DALL_E_2)
        .image_generation(Crig::ImageGenerationRequest.new("A dog", 256, 256))
    end

    http_server.close
  end
end

describe Crig::Providers::OpenAI::TranscriptionModel do
  it "posts multipart transcription requests and parses the returned text" do
    server = FakeOpenAITranscriptionServer.new do |_parts|
      {
        content_type: "application/json",
        body:         %({"text":"hello world"}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.transcription_model(Crig::Providers::OpenAI::WHISPER_1)
      .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.wav", "en", "hint", 0.2))

    response.text.should eq("hello world")
    model_part = server.parts.find { |part| part[:name] == "model" }.not_nil!
    file_part = server.parts.find { |part| part[:name] == "file" }.not_nil!
    language_part = server.parts.find { |part| part[:name] == "language" }.not_nil!
    prompt_part = server.parts.find { |part| part[:name] == "prompt" }.not_nil!
    temperature_part = server.parts.find { |part| part[:name] == "temperature" }.not_nil!

    model_part[:body].should eq(Crig::Providers::OpenAI::WHISPER_1)
    file_part[:body].should eq("abc")
    file_part[:filename].should eq("speech.wav")
    language_part[:body].should eq("en")
    prompt_part[:body].should eq("hint")
    temperature_part[:body].should eq("0.2")

    http_server.close
  end

  it "forwards additional transcription params and surfaces provider errors" do
    server = FakeOpenAITranscriptionServer.new do |_parts|
      {
        content_type: "application/json",
        body:         %({"error":{"message":"bad transcription"}}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::TranscriptionError, /bad transcription/) do
      client.transcription_model(Crig::Providers::OpenAI::WHISPER_1)
        .transcription(
          Crig::TranscriptionRequest.new(
            "abc".to_slice,
            "speech.wav",
            additional_params: JSON.parse(%({"temperature_fallback":"0.4"}))
          )
        )
    end

    additional_part = server.parts.find { |part| part[:name] == "temperature_fallback" }.not_nil!
    additional_part[:body].should eq("0.4")

    http_server.close
  end
end

describe Crig::Providers::OpenAI::AudioGenerationModel do
  it "posts audio generation requests and returns binary audio bytes" do
    server = FakeOpenAIAudioGenerationServer.new do |_request|
      {
        content_type: "application/octet-stream",
        body:         "audio-bytes",
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.audio_generation_model(Crig::Providers::OpenAI::TTS_1)
      .audio_generation(Crig::AudioGenerationRequest.new("hello", "alloy", 1.25_f32))

    String.new(response.audio).should eq("audio-bytes")
    String.new(response.response).should eq("audio-bytes")

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::TTS_1)
    posted["input"].as_s.should eq("hello")
    posted["voice"].as_s.should eq("alloy")
    posted["speed"].as_f.should eq(1.25)

    http_server.close
  end

  it "merges additional audio-generation params and surfaces provider errors" do
    server = FakeOpenAIAudioGenerationServer.new do |_request|
      {
        content_type: "text/plain",
        body:         "audio failed",
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::AudioGenerationError, /BAD_REQUEST: audio failed/) do
      client.audio_generation_model(Crig::Providers::OpenAI::TTS_1_HD)
        .audio_generation(
          Crig::AudioGenerationRequest.new(
            "hello",
            "alloy",
            1.0_f32,
            JSON.parse(%({"format":"wav"}))
          )
        )
    end

    posted = server.requests.first
    posted["format"].as_s.should eq("wav")

    http_server.close
  end
end

describe Crig::Providers::Azure::Client do
  it "supports azure client builders and token default auth" do
    client = Crig::Providers::Azure::Client.builder
      .api_key("token-value")
      .azure_endpoint("https://example.openai.azure.com")
      .api_version("2024-10-01-preview")
      .build

    client.endpoint.should eq("https://example.openai.azure.com")
    client.api_version.should eq("2024-10-01-preview")
    client.auth.kind.should eq(Crig::Providers::Azure::AzureOpenAIAuth::Kind::Token)
  end

  it "posts azure embedding requests against deployment endpoints" do
    path = "/openai/deployments/#{Crig::Providers::Azure::TEXT_EMBEDDING_3_SMALL}/embeddings?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],
          "model":"text-embedding-3-small",
          "usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}
        }),
        status_code: nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    model = client.embedding_model(Crig::Providers::Azure::TEXT_EMBEDDING_3_SMALL)
    embeddings = model.embed_texts(["alpha"])

    embeddings.first.document.should eq("alpha")
    embeddings.first.vec.should eq([0.1, 0.2])
    server.requests.first["dimensions"].as_i.should eq(1536)
    server.headers.first["api-key"].should eq("azure-key")

    http_server.close
  end

  it "posts azure chat completion requests and parses the returned response" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/chat/completions?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-azure",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"azure answer"},
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
        status_code: nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.completion_model(Crig::Providers::Azure::GPT_4O)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("azure answer")
    server.requests.first["model"].as_s.should eq(Crig::Providers::Azure::GPT_4O)

    http_server.close
  end

  it "posts azure transcription multipart requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/audio/translations?api-version=2024-10-21"
    server = FakeAzureMultipartServer.new(path) do |_parts|
      {
        content_type: "application/json",
        body:         %({"text":"azure transcript"}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.token("azure-token"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.transcription_model(Crig::Providers::Azure::GPT_4O)
      .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.wav", prompt: "hint", temperature: 0.2))

    response.text.should eq("azure transcript")
    file_part = server.parts.find { |part| part[:name] == "file" }.not_nil!
    prompt_part = server.parts.find { |part| part[:name] == "prompt" }.not_nil!
    temperature_part = server.parts.find { |part| part[:name] == "temperature" }.not_nil!
    file_part[:filename].should eq("speech.wav")
    prompt_part[:body].should eq("hint")
    temperature_part[:body].should eq("0.2")
    server.headers.first["Authorization"].should eq("Bearer azure-token")

    http_server.close
  end

  it "posts azure image generation requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/images/generations?api-version=2024-10-21"
    encoded = Base64.strict_encode("azure-image")
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.image_generation_model(Crig::Providers::Azure::GPT_4O)
      .image_generation(Crig::ImageGenerationRequest.new("A cat", 512, 512))

    String.new(response.image).should eq("azure-image")
    server.requests.first["response_format"].as_s.should eq("b64_json")

    http_server.close
  end

  it "posts azure audio generation requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/audio/speech?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/octet-stream",
        body:         "azure-audio",
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.audio_generation_model(Crig::Providers::Azure::GPT_4O)
      .audio_generation(Crig::AudioGenerationRequest.new("hello", "alloy", 1.0_f32))

    String.new(response.audio).should eq("azure-audio")
    server.requests.first["voice"].as_s.should eq("alloy")

    http_server.close
  end
end

describe Crig::Providers::XAI::Message do
  it "serializes redacted reasoning as encrypted content without leaking it into summary text" do
    reasoning = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("explain"),
        Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
      ],
      "rs_2"
    )
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
      "assistant_2"
    )

    items = Crig::Providers::XAI::Message.from_completion_message(message)
    items.size.should eq(1)
    item = items.first
    item.kind.should eq(Crig::Providers::XAI::Message::Kind::Reasoning)
    item.summary.not_nil!.map(&.text).should eq(["explain"])
    item.encrypted_content.should eq("opaque-redacted")
  end

  it "roundtrips empty reasoning content without error" do
    reasoning = Crig::Completion::Reasoning.new([] of Crig::Completion::ReasoningContent, "rs_empty")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
      "assistant_2b"
    )

    items = Crig::Providers::XAI::Message.from_completion_message(message)
    items.size.should eq(1)
    items.first.id.should eq("rs_empty")
    items.first.summary.not_nil!.should be_empty
    items.first.encrypted_content.should be_nil
  end

  it "returns an error when assistant reasoning has no id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("thinking")
      ),
      "assistant_no_reasoning_id"
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant reasoning `id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end

  it "uses snake_case message type tags" do
    function_call = Crig::Providers::XAI::Message.function_call("call_1", "tool_name", %({"arg":1}))
    user_message = Crig::Providers::XAI::Message.user("hello")

    function_call.to_json_value["type"].as_s.should eq("function_call")
    user_message.to_json_value["type"].as_s.should eq("message")
  end

  it "returns an error when user tool results omit call_id" do
    message = Crig::Completion::Message.tool_result("tool_1", "result payload")

    expect_raises(Crig::Completion::CompletionError, /Tool result `call_id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end

  it "returns an error when assistant tool calls omit call_id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.tool_call("tool_1", "my_tool", JSON.parse(%({"arg":"value"})))
      ),
      "assistant_3"
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant tool call `call_id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end
end

describe Crig::Providers::XAI::ApiResponse do
  it "wraps success and error payloads with the typed helper" do
    ok = Crig::Providers::XAI::ApiResponse(String).from_json_value(JSON.parse(%({"value":"ok"}))) do |value|
      value["value"].as_s
    end
    err = Crig::Providers::XAI::ApiResponse(String).from_json_value(
      JSON.parse(%({"error":"bad request","code":"invalid_request"}))
    ) do |_value|
      raise "should not be called"
    end

    ok.ok.should eq("ok")
    ok.error.should be_nil
    err.ok.should be_nil
    err.error.not_nil!.message.should eq("Code `invalid_request`: bad request")
  end
end

describe Crig::Providers::XAI::ContentItem do
  it "serializes text, image, and file payloads" do
    text = Crig::Providers::XAI::ContentItem.text("hello").to_json_value
    image = Crig::Providers::XAI::ContentItem.image("https://example.com/cat.png", "high").to_json_value
    file = Crig::Providers::XAI::ContentItem.file(file_url: "https://example.com/doc.pdf").to_json_value

    text["type"].as_s.should eq("input_text")
    text["text"].as_s.should eq("hello")
    image["type"].as_s.should eq("input_image")
    image["image_url"].as_s.should eq("https://example.com/cat.png")
    image["detail"].as_s.should eq("high")
    file["type"].as_s.should eq("input_file")
    file["file_url"].as_s.should eq("https://example.com/doc.pdf")
  end
end

describe Crig::Providers::XAI::Content do
  it "serializes text and array multimodal content" do
    text = Crig::Providers::XAI::Content.text("hello").to_json_value
    array = Crig::Providers::XAI::Content.array([
      Crig::Providers::XAI::ContentItem.text("hello"),
      Crig::Providers::XAI::ContentItem.image("https://example.com/cat.png"),
    ]).to_json_value

    text.as_s.should eq("hello")
    array.as_a.map { |entry| entry["type"].as_s }.should eq(["input_text", "input_image"])
  end
end

describe Crig::Providers::XAI::Client do
  it "supports xai client initialization from the builder" do
    client = Crig::Providers::XAI::Client.builder
      .api_key("dummy-key")
      .build

    client.base_url.should eq(Crig::Providers::XAI::XAI_BASE_URL)
  end

  it "posts xai responses requests and parses the returned response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_xai",
          "model":"grok-3",
          "output":[
            {
              "type":"message",
              "id":"msg_xai",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"xai answer"}]
            }
          ],
          "usage":{"input_tokens":2,"output_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::XAI::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::XAI::GROK_3)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("xai answer")
    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::XAI::GROK_3)
    posted["input"].as_a.first["type"].as_s.should eq("message")

    http_server.close
  end
end

describe Crig::Providers::OpenRouter::Client do
  it "supports rust-shaped client initialization" do
    client = Crig::Providers::OpenRouter::Client.new("dummy-key")
    builder_client = Crig::Providers::OpenRouter::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
  end
end

describe Crig::Providers::OpenRouter::ProviderPreferences do
  it "matches the routing builder helpers and provider wrapper payload" do
    prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order(["anthropic", "openai"])
      .only(["anthropic", "openai", "google"])
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
      .data_collection(Crig::Providers::OpenRouter::DataCollection::Deny)
      .zdr(true)
      .quantizations([
        Crig::Providers::OpenRouter::Quantization::Int8,
      ])
      .allow_fallbacks(false)

    provider = prefs.to_json_value["provider"]
    provider["order"].as_a.map(&.as_s).should eq(["anthropic", "openai"])
    provider["only"].as_a.map(&.as_s).should eq(["anthropic", "openai", "google"])
    provider["sort"].as_s.should eq("throughput")
    provider["data_collection"].as_s.should eq("deny")
    provider["zdr"].as_bool.should be_true
    provider["quantizations"].as_a.map(&.as_s).should eq(["int8"])
    provider["allow_fallbacks"].as_bool.should be_false
  end

  it "supports convenience methods and percentile thresholds" do
    prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
      .zero_data_retention
      .fastest
      .preferred_min_throughput(
        Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
          Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
        )
      )

    prefs.zdr.should eq(true)
    prefs.sort.not_nil!.kind.simple?.should be_true
    prefs.sort.not_nil!.strategy.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    prefs.to_json_value["provider"]["preferred_min_throughput"]["p90"].as_f.should eq(50.0)
  end

  it "matches the rust serialization and deserialization helper coverage" do
    Crig::Providers::OpenRouter::DataCollection::Allow.to_wire.should eq("allow")
    Crig::Providers::OpenRouter::DataCollection::Deny.to_wire.should eq("deny")
    Crig::Providers::OpenRouter::DataCollection.default.should eq(Crig::Providers::OpenRouter::DataCollection::Allow)

    Crig::Providers::OpenRouter::Quantization::Int4.to_wire.should eq("int4")
    Crig::Providers::OpenRouter::Quantization::Int8.to_wire.should eq("int8")
    Crig::Providers::OpenRouter::Quantization::Fp16.to_wire.should eq("fp16")
    Crig::Providers::OpenRouter::Quantization::Bf16.to_wire.should eq("bf16")
    Crig::Providers::OpenRouter::Quantization::Fp32.to_wire.should eq("fp32")
    Crig::Providers::OpenRouter::Quantization::Fp8.to_wire.should eq("fp8")
    Crig::Providers::OpenRouter::Quantization::Unknown.to_wire.should eq("unknown")

    Crig::Providers::OpenRouter::ProviderSortStrategy::Price.to_wire.should eq("price")
    Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput.to_wire.should eq("throughput")
    Crig::Providers::OpenRouter::ProviderSortStrategy::Latency.to_wire.should eq("latency")
    Crig::Providers::OpenRouter::SortPartition::Model.to_wire.should eq("model")
    Crig::Providers::OpenRouter::SortPartition::None.to_wire.should eq("none")

    simple_sort = Crig::Providers::OpenRouter::ProviderSort.simple(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
    simple_sort.to_json_value.as_s.should eq("latency")

    complex_sort = Crig::Providers::OpenRouter::ProviderSort.complex(
      Crig::Providers::OpenRouter::ProviderSortConfig.new(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
        .partition(Crig::Providers::OpenRouter::SortPartition::None)
    )
    complex_sort.to_json_value["by"].as_s.should eq("price")
    complex_sort.to_json_value["partition"].as_s.should eq("none")

    partitionless = Crig::Providers::OpenRouter::ProviderSort.complex(
      Crig::Providers::OpenRouter::ProviderSortConfig.new(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    )
    partitionless.to_json_value["by"].as_s.should eq("throughput")
    partitionless.to_json_value["partition"]?.should be_nil

    thresholds = Crig::Providers::OpenRouter::PercentileThresholds.new
      .p50(10.0)
      .p75(25.0)
      .p90(50.0)
      .p99(100.0)
    thresholds.p50.should eq(10.0)
    thresholds.p75.should eq(25.0)
    thresholds.p90.should eq(50.0)
    thresholds.p99.should eq(100.0)
    Crig::Providers::OpenRouter::PercentileThresholds.new.p50.should be_nil

    throughput_simple = Crig::Providers::OpenRouter::ThroughputThreshold.simple(50.0)
    throughput_simple.to_json_value.as_f.should eq(50.0)
    throughput_percentile = Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
      Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
    )
    throughput_percentile.to_json_value["p90"].as_f.should eq(50.0)

    latency_simple = Crig::Providers::OpenRouter::LatencyThreshold.simple(0.5)
    latency_simple.to_json_value.as_f.should eq(0.5)
    latency_percentile = Crig::Providers::OpenRouter::LatencyThreshold.percentile(
      Crig::Providers::OpenRouter::PercentileThresholds.new.p50(0.1).p99(1.0)
    )
    latency_percentile.to_json_value["p50"].as_f.should eq(0.1)
    latency_percentile.to_json_value["p99"].as_f.should eq(1.0)

    price = Crig::Providers::OpenRouter::MaxPrice.new.prompt(0.001).completion(0.002)
    price.prompt.should eq(0.001)
    price.completion.should eq(0.002)
    price.request.should be_nil
    price.image.should be_nil
    full_price = price.request(0.01).image(0.05).to_json_value
    full_price["prompt"].as_f.should eq(0.001)
    full_price["completion"].as_f.should eq(0.002)
    full_price["request"].as_f.should eq(0.01)
    full_price["image"].as_f.should eq(0.05)
    Crig::Providers::OpenRouter::MaxPrice.new.prompt.should be_nil

    order_with_fallbacks = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order(["anthropic", "openai"])
      .allow_fallbacks(true)
      .to_json_value["provider"]
    order_with_fallbacks["order"].as_a.map(&.as_s).should eq(["anthropic", "openai"])
    order_with_fallbacks["allow_fallbacks"].as_bool.should be_true

    allowlist = Crig::Providers::OpenRouter::ProviderPreferences.new
      .only(["azure", "together"])
      .allow_fallbacks(false)
      .to_json_value["provider"]
    allowlist["only"].as_a.map(&.as_s).should eq(["azure", "together"])
    allowlist["allow_fallbacks"].as_bool.should be_false

    ignored = Crig::Providers::OpenRouter::ProviderPreferences.new.ignore(["deepinfra"]).to_json_value["provider"]
    ignored["ignore"].as_a.map(&.as_s).should eq(["deepinfra"])

    sorted_latency = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
      .to_json_value["provider"]
    sorted_latency["sort"].as_s.should eq("latency")

    sorted_price = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
      .preferred_min_throughput(
        Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
          Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
        )
      )
      .to_json_value["provider"]
    sorted_price["sort"].as_s.should eq("price")
    sorted_price["preferred_min_throughput"]["p90"].as_f.should eq(50.0)

    require_params = Crig::Providers::OpenRouter::ProviderPreferences.new
      .require_parameters(true)
      .to_json_value["provider"]
    require_params["require_parameters"].as_bool.should be_true

    policy = Crig::Providers::OpenRouter::ProviderPreferences.new
      .data_collection(Crig::Providers::OpenRouter::DataCollection::Deny)
      .zdr(true)
      .to_json_value["provider"]
    policy["data_collection"].as_s.should eq("deny")
    policy["zdr"].as_bool.should be_true

    quantized = Crig::Providers::OpenRouter::ProviderPreferences.new
      .quantizations([Crig::Providers::OpenRouter::Quantization::Int8, Crig::Providers::OpenRouter::Quantization::Fp16])
      .to_json_value["provider"]
    quantized["quantizations"].as_a.map(&.as_s).should eq(["int8", "fp16"])

    default_prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
    default_prefs.order.should be_nil
    default_prefs.only.should be_nil
    default_prefs.ignore.should be_nil
    default_prefs.allow_fallbacks.should be_nil
    default_prefs.require_parameters.should be_nil
    default_prefs.data_collection.should be_nil
    default_prefs.zdr.should be_nil
    default_prefs.sort.should be_nil
    default_prefs.preferred_min_throughput.should be_nil
    default_prefs.preferred_max_latency.should be_nil
    default_prefs.max_price.should be_nil
    default_prefs.quantizations.should be_nil

    serialized = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
      .to_json_value["provider"]
    serialized["sort"].as_s.should eq("price")
    serialized["order"]?.should be_nil
    serialized["only"]?.should be_nil
    serialized["ignore"]?.should be_nil
    serialized["zdr"]?.should be_nil

    deserialized = Crig::Providers::OpenRouter::ProviderPreferences.from_json(%({
      "order":["anthropic","openai"],
      "sort":"throughput",
      "data_collection":"deny",
      "zdr":true,
      "quantizations":["int8","fp16"]
    }))
    deserialized.order.should eq(["anthropic", "openai"])
    deserialized.sort.not_nil!.kind.simple?.should be_true
    deserialized.sort.not_nil!.strategy.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    deserialized.data_collection.should eq(Crig::Providers::OpenRouter::DataCollection::Deny)
    deserialized.zdr.should eq(true)
    deserialized.quantizations.should eq([
      Crig::Providers::OpenRouter::Quantization::Int8,
      Crig::Providers::OpenRouter::Quantization::Fp16,
    ])

    complex_deserialized = Crig::Providers::OpenRouter::ProviderPreferences.from_json(%({
      "sort":{"by":"latency","partition":"model"}
    }))
    complex_deserialized.sort.not_nil!.kind.complex?.should be_true
    complex_deserialized.sort.not_nil!.config.not_nil!.by.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
    complex_deserialized.sort.not_nil!.config.not_nil!.partition.should eq(Crig::Providers::OpenRouter::SortPartition::Model)

    max_price = Crig::Providers::OpenRouter::ProviderPreferences.new
      .max_price(Crig::Providers::OpenRouter::MaxPrice.new.prompt(0.001).completion(0.002))
      .to_json_value["provider"]
    max_price["max_price"]["prompt"].as_f.should eq(0.001)
    max_price["max_price"]["completion"].as_f.should eq(0.002)

    max_latency = Crig::Providers::OpenRouter::ProviderPreferences.new
      .preferred_max_latency(Crig::Providers::OpenRouter::LatencyThreshold.simple(0.5))
      .to_json_value["provider"]
    max_latency["preferred_max_latency"].as_f.should eq(0.5)

    empty_arrays = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order([] of String)
      .quantizations([] of Crig::Providers::OpenRouter::Quantization)
      .to_json_value["provider"]
    empty_arrays["order"].as_a.should eq([] of JSON::Any)
    empty_arrays["quantizations"].as_a.should eq([] of JSON::Any)
  end
end

describe Crig::Providers::OpenRouter::UserContent do
  it "serializes and deserializes text, file, audio, and video payloads" do
    text = Crig::Providers::OpenRouter::UserContent.text("Hello, world!").to_json_value
    text["type"].as_s.should eq("text")
    text["text"].as_s.should eq("Hello, world!")

    file = Crig::Providers::OpenRouter::UserContent.file_base64("JVBERi0xLjQ=", "application/pdf", "report.pdf").to_json_value
    file["type"].as_s.should eq("file")
    file["file"]["file_data"].as_s.should eq("data:application/pdf;base64,JVBERi0xLjQ=")
    file["file"]["filename"].as_s.should eq("report.pdf")

    audio = Crig::Providers::OpenRouter::UserContent.audio_base64("SGVsbG8=", Crig::Completion::AudioMediaType::WAV).to_json_value
    audio["type"].as_s.should eq("input_audio")
    audio["input_audio"]["format"].as_s.should eq("wav")

    video = Crig::Providers::OpenRouter::UserContent.video_base64("SGVsbG8=", Crig::Completion::VideoMediaType::MP4).to_json_value
    video["type"].as_s.should eq("video_url")
    video["video_url"]["url"].as_s.should eq("data:video/mp4;base64,SGVsbG8=")

    parsed = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"image_url",
      "image_url":{"url":"https://example.com/image.png","detail":"high"}
    })))

    parsed.kind.image_url?.should be_true
    parsed.image_url.not_nil!.url.should eq("https://example.com/image.png")
    parsed.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::High)
  end

  it "converts core rig content and preserves provider-specific errors" do
    image = Crig::Completion::UserContent.image_base64("SGVsbG8=", Crig::Completion::ImageMediaType::JPEG, Crig::Completion::ImageDetail::Low)
    converted = Crig::Providers::OpenRouter::UserContent.from_core(image)
    converted.kind.image_url?.should be_true
    converted.image_url.not_nil!.url.should eq("data:image/jpeg;base64,SGVsbG8=")
    converted.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Low)

    audio = Crig::Completion::UserContent.audio_url("https://example.com/audio.wav", Crig::Completion::AudioMediaType::WAV)
    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(audio)
    end
  end

  it "matches the rust file and conversion coverage" do
    image_url = Crig::Providers::OpenRouter::UserContent.image_url("https://example.com/image.png").to_json_value
    image_url["type"].as_s.should eq("image_url")
    image_url["image_url"]["url"].as_s.should eq("https://example.com/image.png")
    image_url["image_url"]["detail"]?.should be_nil

    image_detail = Crig::Providers::OpenRouter::UserContent
      .image_url_with_detail("https://example.com/image.png", Crig::Completion::ImageDetail::High)
      .to_json_value
    image_detail["image_url"]["detail"].as_s.should eq("high")

    image_base64 = Crig::Providers::OpenRouter::UserContent
      .image_base64("SGVsbG8=", "image/png", Crig::Completion::ImageDetail::Low)
      .to_json_value
    image_base64["image_url"]["url"].as_s.should eq("data:image/png;base64,SGVsbG8=")
    image_base64["image_url"]["detail"].as_s.should eq("low")

    file_url = Crig::Providers::OpenRouter::UserContent
      .file_url("https://example.com/doc.pdf", "document.pdf")
      .to_json_value
    file_url["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")
    file_url["file"]["filename"].as_s.should eq("document.pdf")

    parsed_text = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({"type":"text","text":"Hello!"})))
    parsed_text.kind.text?.should be_true
    parsed_text.text.should eq("Hello!")

    parsed_file = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"file",
      "file":{"filename":"doc.pdf","file_data":"https://example.com/doc.pdf"}
    })))
    parsed_file.kind.file?.should be_true
    parsed_file.file.not_nil!.filename.should eq("doc.pdf")
    parsed_file.file.not_nil!.file_data.should eq("https://example.com/doc.pdf")

    parsed_video = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"video_url",
      "video_url":{"url":"https://example.com/video.mp4"}
    })))
    parsed_video.kind.video_url?.should be_true
    parsed_video.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    from_text = Crig::Providers::OpenRouter::UserContent.from_string("Hello")
    from_text.kind.text?.should be_true
    from_text.text.should eq("Hello")

    Crig::Providers::OpenRouter::UserContent
      .from_core(Crig::Completion::UserContent.text("Hello"))
      .text.should eq("Hello")

    image = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.image_url("https://example.com/img.png", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::High)
    )
    image.kind.image_url?.should be_true
    image.image_url.not_nil!.url.should eq("https://example.com/img.png")
    image.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::High)

    image_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.image_base64("SGVsbG8=", Crig::Completion::ImageMediaType::JPEG, Crig::Completion::ImageDetail::Low)
    )
    image_b64.image_url.not_nil!.url.should eq("data:image/jpeg;base64,SGVsbG8=")
    image_b64.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Low)

    document_url = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.document_url("https://example.com/doc.pdf", Crig::Completion::DocumentMediaType::PDF)
    )
    document_url.kind.file?.should be_true
    document_url.file.not_nil!.file_data.should eq("https://example.com/doc.pdf")
    document_url.file.not_nil!.filename.should eq("document.pdf")

    document_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Document,
        document: Crig::Completion::Document.new(
          Crig::Completion::DocumentSourceKind.base64("JVBERi0xLjQ="),
          Crig::Completion::DocumentMediaType::PDF,
        ),
      )
    )
    document_b64.file.not_nil!.file_data.should eq("data:application/pdf;base64,JVBERi0xLjQ=")
    document_b64.file.not_nil!.filename.should eq("document.pdf")

    document_text = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.document("Plain text document content", Crig::Completion::DocumentMediaType::TXT)
    )
    document_text.kind.text?.should be_true
    document_text.text.should eq("Plain text document content")

    video_url = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          Crig::Completion::VideoMediaType::MP4,
        ),
      )
    )
    video_url.kind.video_url?.should be_true
    video_url.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    video_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
          Crig::Completion::VideoMediaType::MP4,
        ),
      )
    )
    video_b64.video_url.not_nil!.url.should eq("data:video/mp4;base64,SGVsbG8=")

    audio_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.audio("audiodata", Crig::Completion::AudioMediaType::MP3)
    )
    audio_b64.kind.input_audio?.should be_true
    audio_b64.input_audio.not_nil!.data.should eq("audiodata")
    audio_b64.input_audio.not_nil!.format.should eq("mp3")

    video_url_without_type = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          nil,
        ),
      )
    )
    video_url_without_type.kind.video_url?.should be_true
    video_url_without_type.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    openai_text = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.text("Hello")
    )
    openai_text.kind.text?.should be_true
    openai_text.text.should eq("Hello")

    openai_image = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/img.png", "auto")
    )
    openai_image.kind.image_url?.should be_true
    openai_image.image_url.not_nil!.url.should eq("https://example.com/img.png")
    openai_image.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Auto)

    openai_audio = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.audio("audiodata", "flac")
    )
    openai_audio.kind.input_audio?.should be_true
    openai_audio.input_audio.not_nil!.data.should eq("audiodata")
    openai_audio.input_audio.not_nil!.format.should eq("flac")

    expect_raises(Crig::Completion::CompletionError, /media type required/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Image,
          image: Crig::Completion::Image.new(
            Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
            nil,
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Image,
          image: Crig::Completion::Image.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::ImageMediaType::PNG,
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /media type/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Video,
          video: Crig::Completion::Video.new(
            Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Video,
          video: Crig::Completion::Video.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::VideoMediaType::MP4,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /media type required/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Audio,
          audio: Crig::Completion::Audio.new(
            Crig::Completion::DocumentSourceKind.base64("audiodata"),
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Audio,
          audio: Crig::Completion::Audio.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::AudioMediaType::MP3,
          ),
        )
      )
    end
  end
end

describe Crig::Providers::OpenRouter::Message do
  it "serializes single-text user content as a plain string and mixed content as an array" do
    single = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).one(
        Crig::Providers::OpenRouter::UserContent.text("Hello")
      )
    ).to_json_value
    single["role"].as_s.should eq("user")
    single["content"].as_s.should eq("Hello")

    mixed = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).many([
        Crig::Providers::OpenRouter::UserContent.text("Check this image:"),
        Crig::Providers::OpenRouter::UserContent.image_url("https://example.com/img.png"),
      ])
    ).to_json_value
    mixed["content"].as_a.size.should eq(2)
    mixed["content"].as_a.first["type"].as_s.should eq("text")
    mixed["content"].as_a.last["type"].as_s.should eq("image_url")
  end

  it "emits reasoning details from assistant reasoning content" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.text("step", "sig_step"),
      Crig::Completion::ReasoningContent.summary("summary"),
      Crig::Completion::ReasoningContent.encrypted("enc_blob"),
    ], "rs_2")

    messages = Crig::Providers::OpenRouter::Message.from_core_message(
      Crig::Completion::Message.new(
        Crig::Completion::Message::Role::Assistant,
        Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
          Crig::Completion::AssistantContent.new(
            Crig::Completion::AssistantContent::Kind::Reasoning,
            reasoning: reasoning,
          )
        ),
      )
    )

    assistant = messages.first
    assistant.kind.assistant?.should be_true
    assistant.reasoning.should be_nil
    assistant.reasoning_details.size.should eq(3)
    assistant.reasoning_details.first.kind.text?.should be_true
    assistant.reasoning_details.first.id.should eq("rs_2")
  end

  it "matches the rust message conversion coverage for files and assistant defaults" do
    file_message = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).many([
        Crig::Providers::OpenRouter::UserContent.text("Analyze this PDF:"),
        Crig::Providers::OpenRouter::UserContent.file_url("https://example.com/doc.pdf", "document.pdf"),
      ])
    ).to_json_value
    file_message["role"].as_s.should eq("user")
    file_message["content"].as_a.size.should eq(2)
    file_message["content"][1]["type"].as_s.should eq("file")
    file_message["content"][1]["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")

    assistant = Crig::Providers::OpenRouter::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"Hello world",
      "refusal":null,
      "reasoning":null
    })))
    assistant.kind.assistant?.should be_true
    assistant.assistant_content.size.should eq(1)
    assistant.reasoning_details.should eq([] of Crig::Providers::OpenRouter::ReasoningDetails)

    pdf_message = Crig::Providers::OpenRouter::Message.from_core_message(
      Crig::Completion::Message.new(
        Crig::Completion::Message::Role::User,
        Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
          Crig::Completion::UserContent.text("Analyze this PDF:"),
          Crig::Completion::UserContent.document_url("https://example.com/doc.pdf", Crig::Completion::DocumentMediaType::PDF),
        ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
      )
    ).first
    pdf_json = pdf_message.to_json_value
    pdf_json["content"].as_a[1]["type"].as_s.should eq("file")
    pdf_json["content"].as_a[1]["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")

    openai_user = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).many([
        Crig::Providers::OpenAI::Chat::UserContent.text("Hello"),
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/img.png"),
      ])
    )
    converted_user = Crig::Providers::OpenRouter::Message.from_openai(openai_user)
    converted_user.kind.user?.should be_true
    converted_user.user_content.not_nil!.size.should eq(2)
  end
end

describe Crig::Providers::OpenRouter::CompletionResponse do
  it "maps reasoning details back into typed core reasoning content with index ordering" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_ordering",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_order","index":1,"summary":"second"},
            {"type":"reasoning.summary","id":"rs_order","index":0,"summary":"first"}
          ]
        }
      }]
    }))

    converted = response.to_completion_response
    reasoning = converted.choice.to_a.find(&.kind.reasoning?).not_nil!.reasoning.not_nil!
    reasoning.id.should eq("rs_order")
    reasoning.content.map(&.summary).compact.should eq(["first", "second"])
  end

  it "deserializes gemini flash responses" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"gen-AAAAAAAAAA-AAAAAAAAAAAAAAAAAAAA",
      "provider":"Google",
      "model":"google/gemini-2.5-flash",
      "object":"chat.completion",
      "created":1765971703,
      "choices":[{
        "finish_reason":"stop",
        "native_finish_reason":"STOP",
        "index":0,
        "message":{"role":"assistant","content":"CONTENT","refusal":null,"reasoning":null}
      }],
      "usage":{"prompt_tokens":669,"completion_tokens":5,"total_tokens":674}
    }))

    response.id.should eq("gen-AAAAAAAAAA-AAAAAAAAAAAAAAAAAAAA")
    response.model.should eq("google/gemini-2.5-flash")
    response.choices.size.should eq(1)
    response.choices.first.finish_reason.should eq("stop")
  end

  it "matches the rust reasoning detail conversion coverage" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_123",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_1","summary":"s1"},
            {"type":"reasoning.text","id":"rs_1","text":"t1","signature":"sig_1"},
            {"type":"reasoning.encrypted","id":"rs_1","data":"enc_1"}
          ]
        }
      }]
    }))
    converted = response.to_completion_response
    reasoning = converted.choice.to_a.find(&.kind.reasoning?).not_nil!.reasoning.not_nil!
    reasoning.id.should eq("rs_1")
    reasoning.content.size.should eq(3)

    multi = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_multi",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_1","summary":"one"},
            {"type":"reasoning.summary","id":"rs_2","summary":"two"}
          ]
        }
      }]
    })).to_completion_response
    reasoning_items = multi.choice.to_a.select(&.kind.reasoning?).map(&.reasoning.not_nil!)
    reasoning_items.map(&.id).should eq(["rs_1", "rs_2"])
    reasoning_items.map { |item| item.content.first.summary.not_nil! }.should eq(["one", "two"])
  end
end

describe Crig::Providers::OpenRouter::CompletionModel do
  it "uses the request model override when present and the default model when absent" do
    override_request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
      model: "google/gemini-2.5-flash",
    )
    default_request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
    )

    override_payload = Crig::Providers::OpenRouter::CompletionModel.build_request("openai/gpt-4o-mini", override_request, false).to_json_value
    default_payload = Crig::Providers::OpenRouter::CompletionModel.build_request("openai/gpt-4o-mini", default_request, false).to_json_value

    override_payload["model"].as_s.should eq("google/gemini-2.5-flash")
    default_payload["model"].as_s.should eq("openai/gpt-4o-mini")
  end

  it "serializes named tool-choice functions using the openrouter wire shape" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .tool_choice(Crig::Completion::ToolChoice.specific(["lookup_weather", "lookup_time"]))
      .build

    payload = Crig::Providers::OpenRouter::CompletionModel
      .build_request("openai/gpt-4o-mini", request, false)
      .to_json_value

    tool_choice = payload["tool_choice"].as_a
    tool_choice.size.should eq(2)
    tool_choice[0]["type"].as_s.should eq("function")
    tool_choice[0]["function"]["name"].as_s.should eq("lookup_weather")
    tool_choice[1]["function"]["name"].as_s.should eq("lookup_time")
  end

  it "posts chat completions requests and returns converted assistant content" do
    server = FakeOpenRouterChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_123",
          "object":"chat.completion",
          "created":1,
          "model":"openrouter/test-model",
          "choices":[{
            "index":0,
            "finish_reason":"stop",
            "message":{"role":"assistant","content":"hello","reasoning":null}
          }],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = client.completion_model(Crig::Providers::OpenRouter::CLAUDE_3_7_SONNET)
    response = model.completion(
      model.completion_request("Hello").build
    )

    response.choice.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(3)
    server.requests.first["model"].as_s.should eq(Crig::Providers::OpenRouter::CLAUDE_3_7_SONNET)

    http_server.close
  end

  it "parses streaming text, reasoning, and tool call deltas" do
    server = FakeOpenRouterChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"gen-1","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"search","arguments":""}}]}}]}

data: {"id":"gen-2","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}],"reasoning":"step"}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}

data: {"id":"gen-3","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"Rust\\"}"}}],"content":"done"},"finish_reason":"tool_calls"}]}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    response = client.completion_model(Crig::Providers::OpenRouter::QWEN_QWQ_32B).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Search").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::OpenRouter::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "step" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "done" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "search" }.should be_true
    items.last.kind.final?.should be_true
    response.message_id.should eq("gen-1")

    http_server.close
  end
end

describe Crig::Providers::OpenRouter::EmbeddingModel do
  it "posts embeddings requests with dimensions, encoding format, and user" do
    server = FakeOpenRouterEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],
          "model":"openrouter/embed",
          "usage":{"prompt_tokens":2,"completion_tokens":0,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = Crig::Providers::OpenRouter::EmbeddingModel
      .with_encoding_format(client, "openrouter/embed", 2, Crig::Providers::OpenRouter::EncodingFormat::Base64)
      .user("user-1")

    embeddings = model.embed_texts(["hello"])

    embeddings.first.document.should eq("hello")
    embeddings.first.vec.should eq([0.1, 0.2])
    posted = server.requests.first
    posted["model"].as_s.should eq("openrouter/embed")
    posted["dimensions"].as_i.should eq(2)
    posted["encoding_format"].as_s.should eq("base64")
    posted["user"].as_s.should eq("user-1")

    http_server.close
  end
end

describe Crig::Providers::OpenRouter::StreamingCompletionChunk do
  it "deserializes streaming chunks, tool call deltas, and usage" do
    chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-abc123",
      "choices":[{
        "index":0,
        "delta":{
          "role":"assistant",
          "tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":"{\\"location\\":"}}]
        }
      }],
      "model":"gpt-4",
      "usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}
    })))

    chunk.id.should eq("gen-abc123")
    chunk.choices.first.delta.tool_calls.first.id.should eq("call_abc")
    chunk.usage.not_nil!.total_tokens.should eq(150)
    Crig::Providers::OpenRouter::FinishReason.from_string("tool_calls").tool_calls?.should be_true
  end

  it "matches the rust multiple tool-call delta and error parsing coverage" do
    start_chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-1",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"search","arguments":""}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))
    delta1 = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-2",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))
    delta2 = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-3",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"Rust programming\\"}"}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))

    start_chunk.choices.first.delta.tool_calls.first.id.should eq("call_123")
    delta1.choices.first.delta.tool_calls.first.function.arguments.should eq(%({"query":))
    delta2.choices.first.delta.tool_calls.first.function.arguments.should eq(%("Rust programming"}))

    error_chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"cmpl-abc123",
      "object":"chat.completion.chunk",
      "created":1234567890,
      "model":"gpt-3.5-turbo",
      "provider":"openai",
      "error":{"code":500,"message":"Provider disconnected"},
      "choices":[{"index":0,"delta":{"content":""},"finish_reason":"error"}]
    })))
    error_chunk.error.not_nil!.code.should eq(500)
    error_chunk.error.not_nil!.message.should eq("Provider disconnected")
  end
end

describe Crig::Providers::Perplexity::Message do
  it "deserializes and serializes typed perplexity messages" do
    message = Crig::Providers::Perplexity::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":"Hello, how can I help you?"
    })))

    message.role.should eq(Crig::Providers::Perplexity::Role::User)
    message.content.should eq("Hello, how can I help you?")

    serialized = Crig::Providers::Perplexity::Message.new(
      Crig::Providers::Perplexity::Role::Assistant,
      "I am here to assist you."
    ).to_json_value
    serialized["role"].as_s.should eq("assistant")
    serialized["content"].as_s.should eq("I am here to assist you.")
  end

  it "round-trips between core text-only messages and perplexity messages" do
    user_message = Crig::Completion::Message.user("User message")
    assistant_message = Crig::Completion::Message.assistant("Assistant message")

    converted_user_message = Crig::Providers::Perplexity::Message.from_core_message(user_message)
    converted_assistant_message = Crig::Providers::Perplexity::Message.from_core_message(assistant_message)

    converted_user_message.role.should eq(Crig::Providers::Perplexity::Role::User)
    converted_user_message.content.should eq("User message")
    converted_assistant_message.role.should eq(Crig::Providers::Perplexity::Role::Assistant)
    converted_assistant_message.content.should eq("Assistant message")

    converted_user_message.to_core_message.should eq(user_message)
    converted_assistant_message.to_core_message.should eq(assistant_message)
  end
end

describe Crig::Providers::Perplexity::Client do
  it "supports rust-shaped client initialization" do
    client = Crig::Providers::Perplexity::Client.new("dummy-key")
    builder_client = Crig::Providers::Perplexity::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
  end

  it "posts perplexity chat completions requests and parses the returned response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"pplx_1",
          "model":"sonar",
          "object":"chat.completion",
          "created":1,
          "choices":[{
            "index":0,
            "finish_reason":"stop",
            "message":{"role":"assistant","content":"perplexity answer"},
            "delta":{"role":"assistant","content":"perplexity answer"}
          }],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Perplexity::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Perplexity::SONAR)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("perplexity answer")
    response.usage.total_tokens.should eq(3)
    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::Perplexity::SONAR)
    posted["messages"].as_a.first["role"].as_s.should eq("user")
    posted["stream"].as_bool.should be_false

    http_server.close
  end

  it "parses perplexity streaming text deltas" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"pplx-stream","model":"sonar","choices":[{"index":0,"delta":{"role":"assistant","content":"hello "}}]}

data: {"id":"pplx-stream","model":"sonar","choices":[{"index":0,"delta":{"role":"assistant","content":"world"}}],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4}}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Perplexity::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Perplexity::SONAR_PRO)
      .stream(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    response.each_item { |item| items << item }

    items.select(&.kind.text?).map { |item| item.text.not_nil!.text }.should eq(["hello ", "world"])
    items.last.kind.final?.should be_true
    response.message_id.should eq("pplx-stream")

    http_server.close
  end
end

describe Crig::Providers::Anthropic::Client do
  it "supports anthropic client initialization and builder overrides" do
    client = Crig::Providers::Anthropic::Client.new("dummy-key")
    builder_client = Crig::Providers::Anthropic::Client.builder
      .api_key("dummy-key")
      .anthropic_version("2023-01-01")
      .anthropic_beta("prompt-caching-2024-07-31")
      .anthropic_beta("tools-2024-05-16")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
    builder_client.anthropic_version.should eq("2023-01-01")
    builder_client.anthropic_betas.should eq(["prompt-caching-2024-07-31", "tools-2024-05-16"])
  end

  it "ports ensures_client_builder_no_annotation" do
    http_client = HTTP::Client.new(URI.parse("http://127.0.0.1"))
    client = Crig::Providers::Anthropic::Client.builder
      .http_client(http_client)
      .api_key("Foo")
      .build

    client.http_client.should be(http_client)
    client.api_key.token.should eq("Foo")
  end

  it "emits anthropic auth and version headers from the built client" do
    client = Crig::Providers::Anthropic::Client.builder
      .api_key("dummy-key")
      .anthropic_version("2023-01-01")
      .anthropic_betas(["prompt-caching-2024-07-31", "tools-2024-05-16"])
      .build

    headers = client.default_headers
    headers["x-api-key"].should eq("dummy-key")
    headers["anthropic-version"].should eq("2023-01-01")
    headers["anthropic-beta"].should eq("prompt-caching-2024-07-31,tools-2024-05-16")
  end
end

describe Crig::Providers::Anthropic::Message do
  it "deserializes anthropic assistant and user messages" do
    assistant_message = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"\\n\\nHello there, how may I assist you today?"
    })))
    assistant_message2 = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":[
        {"type":"text","text":"\\n\\nHello there, how may I assist you today?"},
        {"type":"tool_use","id":"toolu_01A09q90qw90lq917835lq9","name":"get_weather","input":{"location":"San Francisco, CA"}}
      ]
    })))
    user_message = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":[
        {"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"/9j/4AAQSkZJRg..."}},
        {"type":"text","text":"What is in this image?"},
        {"type":"tool_result","tool_use_id":"toolu_01A09q90qw90lq917835lq9","content":"15 degrees"}
      ]
    })))

    assistant_message.role.should eq(Crig::Providers::Anthropic::Role::Assistant)
    assistant_message.content.first.kind.text?.should be_true
    assistant_message.content.first.text.should eq("\n\nHello there, how may I assist you today?")

    assistant_message2.content.size.should eq(2)
    assistant_message2.content.first.kind.text?.should be_true
    assistant_message2.content.last.kind.tool_use?.should be_true
    assistant_message2.content.last.id.should eq("toolu_01A09q90qw90lq917835lq9")
    assistant_message2.content.last.name.should eq("get_weather")

    user_message.role.should eq(Crig::Providers::Anthropic::Role::User)
    user_message.content.size.should eq(3)
    user_message.content.first.kind.image?.should be_true
    user_message.content.to_a[1].kind.text?.should be_true
    user_message.content.last.kind.tool_result?.should be_true
  end

  it "round-trips between core messages and anthropic messages for supported content" do
    user_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::UserContent.text("hello"),
        Crig::Completion::UserContent.document("plain text document", Crig::Completion::DocumentMediaType::TXT),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
    )
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.text("Hi there!"),
        Crig::Completion::AssistantContent.tool_call("tool_1", "lookup", JSON.parse(%({"city":"Paris"}))),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
    )

    converted_user = Crig::Providers::Anthropic::Message.from_core_message(user_message)
    converted_assistant = Crig::Providers::Anthropic::Message.from_core_message(assistant_message)

    converted_user.role.should eq(Crig::Providers::Anthropic::Role::User)
    converted_user.content.size.should eq(2)
    converted_user.to_core_message.should eq(user_message)

    converted_assistant.role.should eq(Crig::Providers::Anthropic::Role::Assistant)
    converted_assistant.content.size.should eq(2)
    converted_assistant.to_core_message.should eq(assistant_message)
  end

  it "ports reasoning and document/cache-control helpers" do
    reasoning = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("step", "sig_step"),
        Crig::Completion::ReasoningContent.summary("summary"),
        Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
      ],
      "rs_1"
    )
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
    )

    anthropic_reasoning = Crig::Providers::Anthropic::Message.from_core_message(assistant_message)
    anthropic_reasoning.content.size.should eq(3)
    anthropic_reasoning.content.first.kind.thinking?.should be_true
    anthropic_reasoning.content.last.kind.redacted_thinking?.should be_true
    roundtripped_reasoning = anthropic_reasoning.to_core_message.content.to_a.map(&.as(Crig::Completion::AssistantContent))
    roundtripped_reasoning.size.should eq(3)
    roundtripped_reasoning[0].reasoning.not_nil!.content.size.should eq(1)
    roundtripped_reasoning[1].reasoning.not_nil!.content.first.text.should eq("summary")
    roundtripped_reasoning[2].reasoning.not_nil!.content.first.data.should eq("opaque-redacted")

    pdf = Crig::Providers::Anthropic::Content.document(
      Crig::Providers::Anthropic::DocumentSource.base64("JVBERi0xLjQ=", Crig::Providers::Anthropic::DocumentFormat::PDF)
    )
    pdf_json = Crig::Providers::OpenAI.build_json_any { |json| pdf.to_json(json) }
    pdf_json["source"]["media_type"].as_s.should eq("application/pdf")

    text_doc = Crig::Providers::Anthropic::Content.document(
      Crig::Providers::Anthropic::DocumentSource.text("hello world")
    )
    text_doc_json = Crig::Providers::OpenAI.build_json_any { |json| text_doc.to_json(json) }
    text_doc_json["source"]["media_type"].as_s.should eq("text/plain")

    system = [Crig::Providers::Anthropic::SystemContent.text("system prompt")]
    messages = [
      Crig::Providers::Anthropic::Message.new(
        Crig::Providers::Anthropic::Role::User,
        Crig::OneOrMany(Crig::Providers::Anthropic::Content).one(
          Crig::Providers::Anthropic::Content.text("hello")
        ),
      ),
    ]
    Crig::Providers::Anthropic.apply_cache_control(system, messages)
    system.last.cache_control.should eq(Crig::Providers::Anthropic::CacheControl::Ephemeral)
    messages.last.content.last.cache_control.should eq(Crig::Providers::Anthropic::CacheControl::Ephemeral)
  end
end

describe Crig::Providers::Anthropic::CompletionModel do
  it "ports tool choice and max token helpers" do
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.auto).kind.auto?.should be_true
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.none).kind.none?.should be_true
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.required).kind.any?.should be_true
    specific = Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.specific(["lookup_weather"]))
    specific.kind.tool?.should be_true
    specific.name.should eq("lookup_weather")

    expect_raises(Crig::Completion::CompletionError, "Only one tool may be specified to be used by Claude") do
      Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.specific(["a", "b"]))
    end

    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_4_SONNET).should eq(64_000_i64)
    Crig::Providers::Anthropic.calculate_max_tokens("claude-3-opus-20240229").should eq(4_096_i64)
    Crig::Providers::Anthropic.calculate_max_tokens("unknown-model").should be_nil
    Crig::Providers::Anthropic.calculate_max_tokens_custom("unknown-model").should eq(2_048_i64)

    client = Crig::Providers::Anthropic::Client.new("test-key")
    builder = Crig::Providers::Anthropic::CompletionModel.make(client, Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .completion_request("hello")
    builder.build.max_tokens.should eq(8_192_i64)

    explicit = Crig::Providers::Anthropic::CompletionModel.with_model(client, "custom-model")
      .completion_request("hello")
    explicit.build.max_tokens.should eq(2_048_i64)
  end

  it "sanitizes schemas and builds anthropic request payloads" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+2?")
      .preamble("You are precise.")
      .max_tokens(64_i64)
      .tool(Crig::Completion::ToolDefinition.new("lookup_weather", "Find the weather", JSON.parse(%({"type":"object","properties":{"city":{"type":"string"}}}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .output_schema(JSON.parse(%({
        "title":"math_response",
        "type":"object",
        "properties":{
          "value":{"type":"integer","minimum":1},
          "nested":{"type":"object","properties":{"name":{"type":"string"}}}
        }
      })))
      .additional_params(JSON.parse(%({"metadata":{"user_id":"user-123"}})))
      .build

    payload = Crig::Providers::Anthropic::AnthropicCompletionRequest.from_params(
      Crig::Providers::Anthropic::AnthropicRequestParams.new(
        Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
        request,
        true,
      ),
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    payload["max_tokens"].as_i64.should eq(64_i64)
    payload["system"].as_a.last["cache_control"]["type"].as_s.should eq("ephemeral")
    payload["messages"].as_a.last["content"].as_a.last["text"].as_s.should eq("What is 2+2?")
    payload["messages"].as_a.last["content"].as_a.last["cache_control"]["type"].as_s.should eq("ephemeral")
    payload["tool_choice"]["type"].as_s.should eq("any")
    payload["tools"].as_a.first["name"].as_s.should eq("lookup_weather")
    payload["tools"].as_a.first["input_schema"]["properties"]["city"]["type"].as_s.should eq("string")
    payload["output_config"]["format"]["schema"]["additionalProperties"].as_bool.should be_false
    payload["output_config"]["format"]["schema"]["required"].as_a.map(&.as_s).sort.should eq(["nested", "value"])
    payload["output_config"]["format"]["schema"]["properties"]["value"]["minimum"]?.should be_nil
    payload["output_config"]["format"]["schema"]["properties"]["nested"]["additionalProperties"].as_bool.should be_false
    payload["metadata"]["user_id"].as_s.should eq("user-123")
  end

  it "posts anthropic completion requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"msg_123",
        "type":"message",
        "role":"assistant",
        "model":"claude-3-5-sonnet-latest",
        "content":[{"type":"text","text":"Anthropic answer"}],
        "stop_reason":"end_turn",
        "stop_sequence":null,
        "usage":{"input_tokens":10,"output_tokens":4}
      }))
    end
    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Anthropic::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("Anthropic answer")
    response.usage.input_tokens.should eq(10_i64)
    response.usage.output_tokens.should eq(4_i64)
    response.raw_response.as(Crig::Providers::Anthropic::CompletionResponse).id.should eq("msg_123")
    requests.first["messages"].as_a.first["content"].as_s.should eq("hello")
    requests.first["max_tokens"].as_i64.should eq(8_192_i64)

    http_server.close
  end
end

describe Crig::Providers::Anthropic::Decoders::LineDecoder do
  it "ports the rust line decoder tests" do
    decode_chunks = ->(chunks : Array(String), flush : Bool) do
      Crig::Providers::Anthropic::Decoders::LineDecoder.decode_chunks(chunks, flush)
    end

    decode_chunks.call(["foo", " bar\nbaz"], false).should eq(["foo bar"])
    decode_chunks.call(["foo", " bar\r\nbaz"], false).should eq(["foo bar"])
    decode_chunks.call(["foo", " bar\r\nbaz"], true).should eq(["foo bar", "baz"])
    decode_chunks.call(["foo", " bar", "baz\n", "thing\n"], false).should eq(["foo barbaz", "thing"])
    decode_chunks.call(["foo", " bar", "baz\r\n", "thing\r\n"], false).should eq(["foo barbaz", "thing"])
    decode_chunks.call(["foo", " bar\\nbaz\n"], false).should eq(["foo bar\\nbaz"])
    decode_chunks.call(["foo", " bar\\r\\nbaz\n"], false).should eq(["foo bar\\r\\nbaz"])
    decode_chunks.call(["foo\r", "\n", "bar"], true).should eq(["foo", "bar"])
    decode_chunks.call(["foo\r", "bar"], true).should eq(["foo", "bar"])
    decode_chunks.call(["foo\r", "bar\r"], true).should eq(["foo", "bar"])
    decode_chunks.call(["foo\r", "\r", "bar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call(["foo\r", "\r", "bar"], false).should eq(["foo"])
    decode_chunks.call(["foo\r", "\r", "\r", "\n", "bar", "\n"], false).should eq(["foo", "", "", "bar"])
    decode_chunks.call(["foo\n", "\n", "\n", "bar", "\n"], false).should eq(["foo", "", "", "bar"])
    decode_chunks.call(["foo\n\nbar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call(["foo", "\n", "\nbar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call(["foo\n", "\n", "bar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call(["foo", "\n", "\n", "bar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call(["foo\n", "\nbar"], true).should eq(["foo", "", "bar"])
    decode_chunks.call([] of String, true).should eq([] of String)
  end

  it "ports multi-byte splitting and double-newline detection" do
    decoder = Crig::Providers::Anthropic::Decoders::LineDecoder.new
    decoder.decode(Bytes[0xd0_u8]).should eq([] of String)
    decoder.decode(Bytes[0xb8_u8, 0xd0_u8, 0xb7_u8, 0xd0_u8]).should eq([] of String)
    decoder.decode(Bytes[0xb2_u8, 0xd0_u8, 0xb5_u8, 0xd1_u8, 0x81_u8, 0xd1_u8, 0x82_u8, 0xd0_u8, 0xbd_u8, 0xd0_u8, 0xb8_u8]).should eq([] of String)
    decoder.decode(Bytes[0x0a_u8]).should eq(["известни"])

    find = ->(buffer : String) { Crig::Providers::Anthropic::Decoders::LineDecoder.find_double_newline_index(buffer.to_slice) }
    find.call("foo\n\nbar").should eq(5)
    find.call("\n\nbar").should eq(2)
    find.call("foo\n\n").should eq(5)
    find.call("\n\n").should eq(2)
    find.call("foo\r\rbar").should eq(5)
    find.call("\r\rbar").should eq(2)
    find.call("foo\r\r").should eq(5)
    find.call("\r\r").should eq(2)
    find.call("foo\r\n\r\nbar").should eq(7)
    find.call("\r\n\r\nbar").should eq(4)
    find.call("foo\r\n\r\n").should eq(7)
    find.call("\r\n\r\n").should eq(4)
    find.call("foo\nbar").should eq(-1)
    find.call("foo\rbar").should eq(-1)
    find.call("foo\r\nbar").should eq(-1)
    find.call("").should eq(-1)
    find.call("foo\r\n\r").should eq(-1)
    find.call("foo\r\n").should eq(-1)
  end
end

describe Crig::Providers::Anthropic::Decoders::SSEDecoder do
  it "decodes event lines and flushes complete server-sent events" do
    decoder = Crig::Providers::Anthropic::Decoders::SSEDecoder.new

    decoder.decode("event: message").should be_nil
    decoder.decode("data: first").should be_nil
    decoder.decode("data: second").should be_nil
    event = decoder.decode("")

    event.not_nil!.event.should eq("message")
    event.not_nil!.data.should eq("first\nsecond")
    event.not_nil!.raw.should eq(["event: message", "data: first", "data: second"])
  end

  it "ports sse chunk extraction and message iteration" do
    extract = Crig::Providers::Anthropic::Decoders::SSEDecoder.extract_sse_chunk("data: one\n\ndata: two\n\nrest".to_slice)
    extract.should_not be_nil
    extract.not_nil![0].should eq("data: one\n\n".to_slice)
    extract.not_nil![1].should eq("data: two\n\nrest".to_slice)

    events = Crig::Providers::Anthropic::Decoders::SSEDecoder.iter_sse_messages([
      "event: message\ndata: hello\n\n".to_slice,
      ":comment\ndata: world\n\n".to_slice,
      "data: [DONE]\n\n".to_slice,
    ])

    events.size.should eq(3)
    events[0].event.should eq("message")
    events[0].data.should eq("hello")
    events[1].event.should be_nil
    events[1].data.should eq("world")
    events[2].data.should eq("[DONE]")
  end
end

describe Crig::Providers::Anthropic::StreamingEvent do
  it "ports anthropic streaming delta deserialization tests" do
    thinking_delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(
      JSON.parse(%({"type":"thinking_delta","thinking":"Let me think about this..."}))
    )
    thinking_delta.kind.thinking_delta?.should be_true
    thinking_delta.thinking.should eq("Let me think about this...")

    signature_delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(
      JSON.parse(%({"type":"signature_delta","signature":"abc123def456"}))
    )
    signature_delta.kind.signature_delta?.should be_true
    signature_delta.signature.should eq("abc123def456")

    thinking_event = Crig::Providers::Anthropic::StreamingEvent.from_json_value(
      JSON.parse(%({
        "type":"content_block_delta",
        "index":0,
        "delta":{"type":"thinking_delta","thinking":"First, I need to understand the problem."}
      }))
    )
    thinking_event.kind.content_block_delta?.should be_true
    thinking_event.index.should eq(0)
    thinking_event.delta.not_nil!.kind.thinking_delta?.should be_true

    signature_event = Crig::Providers::Anthropic::StreamingEvent.from_json_value(
      JSON.parse(%({
        "type":"content_block_delta",
        "index":0,
        "delta":{"type":"signature_delta","signature":"ErUBCkYICBgCIkCaGbqC85F4"}
      }))
    )
    signature_event.kind.content_block_delta?.should be_true
    signature_event.delta.not_nil!.kind.signature_delta?.should be_true
    signature_event.delta.not_nil!.signature.should eq("ErUBCkYICBgCIkCaGbqC85F4")
  end
end

describe Crig::Providers::Anthropic do
  it "ports anthropic streaming event handling tests" do
    tool_call_state = nil.as(Crig::Providers::Anthropic::ToolCallState?)
    thinking_state = nil.as(Crig::Providers::Anthropic::ThinkingState?)

    event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::ThinkingDelta,
        thinking: "Analyzing the request..."
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
    choice.not_nil!.kind.reasoning_delta?.should be_true
    choice.not_nil!.reasoning_delta.should eq("Analyzing the request...")
    thinking_state.not_nil!.thinking.should eq("Analyzing the request...")

    event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::SignatureDelta,
        signature: "test_signature"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
    choice.should be_nil
    thinking_state.not_nil!.signature.should eq("test_signature")

    redacted_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockStart,
      index: 0,
      content_block: Crig::Providers::Anthropic::Content.redacted_thinking("redacted_blob"),
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(redacted_event, tool_call_state, thinking_state)
    choice.not_nil!.kind.reasoning?.should be_true
    choice.not_nil!.reasoning_content.not_nil!.data.should eq("redacted_blob")

    text_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::TextDelta,
        text: "Hello, world!"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(text_event, nil, nil)
    choice.not_nil!.kind.message?.should be_true
    choice.not_nil!.message.should eq("Hello, world!")

    active_tool = Crig::Providers::Anthropic::ToolCallState.new("test_tool", "tool_123", "internal_123", "")
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, active_tool, nil)
    choice.should be_nil
    thinking_state.not_nil!.signature.should eq("test_signature")
    tool_call_state.not_nil!.id.should eq("tool_123")

    json_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::InputJsonDelta,
        partial_json: "{\"arg\":\"value"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(json_event, active_tool, nil)
    choice.not_nil!.kind.tool_call_delta?.should be_true
    choice.not_nil!.id.should eq("tool_123")
    choice.not_nil!.content.not_nil!.kind.delta?.should be_true
    choice.not_nil!.content.not_nil!.value.should eq("{\"arg\":\"value")
    tool_call_state.not_nil!.input_json.should eq("{\"arg\":\"value")

    tool_call_state = Crig::Providers::Anthropic::ToolCallState.new("test_tool", "tool_123", "internal_123", "")
    [
      "{\"location\":",
      "\"Paris\",",
      "\"temp\":\"20C\"}",
    ].each do |delta|
      event = Crig::Providers::Anthropic::StreamingEvent.new(
        Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
        delta: Crig::Providers::Anthropic::ContentDelta.new(
          Crig::Providers::Anthropic::ContentDeltaKind::InputJsonDelta,
          partial_json: delta
        ),
        index: 0,
      )
      choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
      choice.should_not be_nil
    end
    tool_call_state.not_nil!.input_json.should eq("{\"location\":\"Paris\",\"temp\":\"20C\"}")

    stop_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockStop,
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(stop_event, tool_call_state, thinking_state)
    choice.not_nil!.kind.tool_call?.should be_true
    choice.not_nil!.tool_call.not_nil!.id.should eq("tool_123")
    choice.not_nil!.tool_call.not_nil!.name.should eq("test_tool")
    choice.not_nil!.tool_call.not_nil!.arguments["location"].as_s.should eq("Paris")
    choice.not_nil!.tool_call.not_nil!.arguments["temp"].as_s.should eq("20C")
    tool_call_state.should be_nil
  end

  it "parses anthropic streaming responses with reasoning and tool calls" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"type":"message_start","message":{"id":"msg_stream_1","role":"assistant","content":[],"model":"claude-3-5-sonnet-latest","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":7,"output_tokens":0}}}

data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":null}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Analyzing..."}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}

data: {"type":"content_block_stop","index":0}

data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_123","name":"lookup_weather","input":{}}}

data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":\\"Paris\\"}"}}

data: {"type":"content_block_stop","index":1}

data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Final answer"}}

data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

data: {"type":"message_stop"}

SSE
    end

    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Anthropic::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .stream(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::Anthropic::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items[0].kind.reasoning_delta?.should be_true
    items[0].reasoning_delta.should eq("Analyzing...")
    items[1].kind.reasoning?.should be_true
    items[1].reasoning.not_nil!.content.first.signature.should eq("sig123")
    items[2].kind.tool_call_delta?.should be_true
    items[2].content.not_nil!.kind.name?.should be_true
    items[3].kind.tool_call_delta?.should be_true
    items[3].content.not_nil!.kind.delta?.should be_true
    items[4].kind.tool_call?.should be_true
    items[4].tool_call.not_nil!.function.arguments["city"].as_s.should eq("Paris")
    items[5].kind.text?.should be_true
    items[5].text.not_nil!.text.should eq("Final answer")
    items.last.kind.final?.should be_true
    items.last.final.not_nil!.usage.output_tokens.should eq(5_i64)
    response.message_id.should eq("msg_stream_1")
    requests.first["stream"].as_bool.should be_true

    http_server.close
  end
end

describe Crig::Providers::Cohere::Client do
  it "ports the cohere client initialization and embedding helpers" do
    client = Crig::Providers::Cohere::Client.new("dummy-key")
    builder_client = Crig::Providers::Cohere::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.should eq("dummy-key")
    builder_client.api_key.should eq("dummy-key")
    client.default_headers["authorization"].should eq("Bearer dummy-key")

    english = client.embedding_model(Crig::Providers::Cohere::EMBED_ENGLISH_V3, "search_document")
    english.model.should eq(Crig::Providers::Cohere::EMBED_ENGLISH_V3)
    english.ndims.should eq(1024)
    english.input_type.should eq("search_document")

    custom = client.embedding_model_with_ndims("custom", "search_query", 777)
    custom.ndims.should eq(777)
    custom.input_type.should eq("search_query")
  end

  it "posts cohere embedding requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"embed_123",
        "response_type":"embeddings_floats",
        "embeddings":[[0.1,0.2],[0.3,0.4]],
        "texts":["alpha","beta"],
        "meta":{
          "api_version":{"version":"1"},
          "billed_units":{"input_tokens":4,"output_tokens":0,"search_units":1,"classifications":0},
          "warnings":[]
        }
      }))
    end

    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Cohere::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.embedding_model(Crig::Providers::Cohere::EMBED_ENGLISH_V3, "search_document")
    embeddings = model.embed_texts(["alpha", "beta"])

    embeddings.size.should eq(2)
    embeddings[0].document.should eq("alpha")
    embeddings[0].vec.should eq([0.1, 0.2])
    embeddings[1].document.should eq("beta")
    embeddings[1].vec.should eq([0.3, 0.4])
    requests.first["model"].as_s.should eq(Crig::Providers::Cohere::EMBED_ENGLISH_V3)
    requests.first["input_type"].as_s.should eq("search_document")
    requests.first["texts"].as_a.map(&.as_s).should eq(["alpha", "beta"])

    http_server.close
  end
end

describe Crig::Providers::Cohere::CompletionResponse do
  it "deserializes the Rust cohere completion response shape" do
    response = Crig::Providers::Cohere::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"abc123",
      "message":{
        "role":"assistant",
        "tool_plan":"I will use the subtract tool to find the difference between 2 and 5.",
        "tool_calls":[
          {
            "id":"subtract_sm6ps6fb6y9f",
            "type":"function",
            "function":{"name":"subtract","arguments":"{\\"x\\":5,\\"y\\":2}"}
          }
        ]
      },
      "finish_reason":"TOOL_CALL",
      "usage":{
        "billed_units":{"input_tokens":78,"output_tokens":27},
        "tokens":{"input_tokens":1028,"output_tokens":63}
      }
    })))

    content, citations, tool_calls = response.message
    response.id.should eq("abc123")
    response.finish_reason.tool_call?.should be_true
    response.usage.not_nil!.billed_units.not_nil!.input_tokens.should eq(78.0)
    response.usage.not_nil!.billed_units.not_nil!.output_tokens.should eq(27.0)
    response.usage.not_nil!.tokens.not_nil!.input_tokens.should eq(1028.0)
    response.usage.not_nil!.tokens.not_nil!.output_tokens.should eq(63.0)
    content.should eq([] of Crig::Providers::Cohere::AssistantContent)
    citations.should eq([] of Crig::Providers::Cohere::Citation)
    tool_calls.size.should eq(1)
    tool_calls.first.function.not_nil!.name.should eq("subtract")
    tool_calls.first.function.not_nil!.arguments["x"].as_i.should eq(5)
    tool_calls.first.function.not_nil!.arguments["y"].as_i.should eq(2)
  end
end

describe Crig::Providers::Cohere::Message do
  it "converts a core completion message to cohere messages and back" do
    completion_message = Crig::Completion::Message.user("Hello, world!")

    messages = Crig::Providers::Cohere::Message.from_core_message(completion_message)
    converted_back = messages.map(&.to_core_message)

    converted_back.size.should eq(1)
    converted_back.first.role.user?.should be_true
    converted_back.first.content.first.as(Crig::Completion::UserContent).text.not_nil!.text.should eq("Hello, world!")
  end

  it "converts a cohere message to a core completion message and back" do
    message = Crig::Providers::Cohere::Message.user(
      Crig::OneOrMany(Crig::Providers::Cohere::UserContent).one(
        Crig::Providers::Cohere::UserContent.text("Hello, world!")
      )
    )

    completion_message = message.to_core_message
    converted_back = Crig::Providers::Cohere::Message.from_core_message(completion_message)

    converted_back.size.should eq(1)
    converted_back.first.user_content.not_nil!.first.text.should eq("Hello, world!")
  end
end

describe Crig::Providers::Cohere::Citation do
  it "parses citation types and source variants" do
    citation = Crig::Providers::Cohere::Citation.from_json_value(JSON.parse(%({
      "start":1,
      "end":4,
      "text":"test",
      "type":"TEXT_CONTENT",
      "sources":[
        {"type":"document","id":"doc-1","document":{"title":"Doc"}},
        {"type":"tool","id":"call-1","tool_output":{"status":"ok"}}
      ]
    })))

    citation.citation_type.not_nil!.value.should eq("TEXT_CONTENT")
    citation.sources.map(&.kind).should eq([
      Crig::Providers::Cohere::Source::Kind::Document,
      Crig::Providers::Cohere::Source::Kind::Tool,
    ])

    roundtrip = JSON.parse(citation.to_json)
    roundtrip["type"].as_s.should eq("TEXT_CONTENT")
    roundtrip["sources"].as_a.size.should eq(2)
  end
end

describe Crig::Providers::Cohere::UserContent do
  it "parses image_url payloads and converts them back to core messages" do
    content = Crig::Providers::Cohere::UserContent.from_json_value(JSON.parse(%({
      "type":"image_url",
      "image_url":{"url":"https://example.com/cat.png"}
    })))

    content.kind.image_url?.should be_true
    content.image_url.not_nil!.url.should eq("https://example.com/cat.png")

    message = Crig::Providers::Cohere::Message.user(Crig::OneOrMany(Crig::Providers::Cohere::UserContent).one(content))
    core = message.to_core_message
    core_content = core.content.first.as(Crig::Completion::UserContent)
    core_content.image.not_nil!.try_into_url.should eq("https://example.com/cat.png")
  end
end

describe Crig::Providers::Cohere::ToolResultContent do
  it "parses document payloads and converts them back to core tool results" do
    content = Crig::Providers::Cohere::ToolResultContent.from_json_value(JSON.parse(%({
      "document":{"id":"doc-1","data":{"text":"hello"}}
    })))

    content.kind.document?.should be_true
    content.document.not_nil!.id.should eq("doc-1")

    message = Crig::Providers::Cohere::Message.tool(
      Crig::OneOrMany(Crig::Providers::Cohere::ToolResultContent).one(content),
      "call-1"
    )
    core = message.to_core_message
    tool_result = core.content.first.as(Crig::Completion::UserContent).tool_result.not_nil!
    tool_result.id.should eq("call-1")
    tool_result.content.first.text.not_nil!.text.should eq(%({"text":"hello"}))
  end
end

describe Crig::Providers::Cohere::CompletionModel do
  it "supports direct constructor parity" do
    client = Crig::Providers::Cohere::Client.new("dummy-key")
    model = Crig::Providers::Cohere::CompletionModel.new(client, Crig::Providers::Cohere::COMMAND_R)

    model.client.should eq(client)
    model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
  end

  it "posts cohere chat requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"cohere_chat_1",
        "message":{"role":"assistant","content":[{"type":"text","text":"Hello from Cohere"}],"citations":[],"tool_calls":[]},
        "finish_reason":"COMPLETE",
        "usage":{"tokens":{"input_tokens":12,"output_tokens":5}}
      }))
    end

    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Cohere::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model(Crig::Providers::Cohere::COMMAND_R)
    response = model.completion(
      model.completion_request("Hello Cohere")
        .tool(Crig::Completion::ToolDefinition.new("subtract", "Subtract numbers", JSON.parse(%({"type":"object"}))))
        .temperature(0.5)
        .build
    )

    response.choice.first.text.not_nil!.text.should eq("Hello from Cohere")
    response.usage.input_tokens.should eq(12_i64)
    response.usage.output_tokens.should eq(5_i64)
    requests.first["model"].as_s.should eq(Crig::Providers::Cohere::COMMAND_R)
    requests.first["messages"].as_a.size.should eq(1)
    requests.first["messages"].as_a.first["role"].as_s.should eq("user")
    requests.first["messages"].as_a.first["content"].as_a.first["text"].as_s.should eq("Hello Cohere")
    requests.first["tools"].as_a.first["function"]["name"].as_s.should eq("subtract")

    http_server.close
  end
end

describe Crig::Providers::Cohere::Streaming::StreamingEvent do
  it "deserializes a content delta event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"content-delta",
      "delta":{"message":{"content":{"text":"Hello world"}}}
    })))

    event.kind.content_delta?.should be_true
    event.delta.not_nil!.message.not_nil!.content.not_nil!.text.should eq("Hello world")
  end

  it "deserializes a tool call start event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"tool-call-start",
      "delta":{"message":{"tool_calls":{"id":"call_123","function":{"name":"get_weather","arguments":"{"}}}}
    })))

    event.kind.tool_call_start?.should be_true
    tool_call = event.delta.not_nil!.message.not_nil!.tool_calls.not_nil!
    tool_call.id.should eq("call_123")
    tool_call.function.not_nil!.name.should eq("get_weather")
  end

  it "deserializes a tool call delta event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"tool-call-delta",
      "delta":{"message":{"tool_calls":{"function":{"arguments":"\\"location\\""}}}}
    })))

    event.kind.tool_call_delta?.should be_true
    event.delta.not_nil!.message.not_nil!.tool_calls.not_nil!.function.not_nil!.arguments.should eq(%("location"))
  end

  it "deserializes a tool call end event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({"type":"tool-call-end"})))

    event.kind.tool_call_end?.should be_true
  end

  it "deserializes a message end event with usage" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"message-end",
      "delta":{"usage":{"tokens":{"input_tokens":100,"output_tokens":50}}}
    })))

    event.kind.message_end?.should be_true
    usage = event.message_end_delta.not_nil!.usage.not_nil!
    usage.tokens.not_nil!.input_tokens.should eq(100.0)
    usage.tokens.not_nil!.output_tokens.should eq(50.0)
  end

  it "deserializes the Rust streaming event order sequence" do
    events = [
      JSON.parse(%({"type":"message-start"})),
      JSON.parse(%({"type":"content-start"})),
      JSON.parse(%({"type":"content-delta","delta":{"message":{"content":{"text":"Sure, "}}}})),
      JSON.parse(%({"type":"content-delta","delta":{"message":{"content":{"text":"I can help with that."}}}})),
      JSON.parse(%({"type":"content-end"})),
      JSON.parse(%({"type":"tool-plan"})),
      JSON.parse(%({"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"call_abc","function":{"name":"search","arguments":""}}}}})),
      Crig::Providers::OpenAI.build_json_any do |json|
        json.object do
          json.field "type", "tool-call-delta"
          json.field "delta" do
            json.object do
              json.field "message" do
                json.object do
                  json.field "tool_calls" do
                    json.object do
                      json.field "function" do
                        json.object do
                          json.field "arguments", "{\"query\":"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end,
      Crig::Providers::OpenAI.build_json_any do |json|
        json.object do
          json.field "type", "tool-call-delta"
          json.field "delta" do
            json.object do
              json.field "message" do
                json.object do
                  json.field "tool_calls" do
                    json.object do
                      json.field "function" do
                        json.object do
                          json.field "arguments", "\"Rust\"}"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end,
      JSON.parse(%({"type":"tool-call-end"})),
      JSON.parse(%({"type":"message-end","delta":{"usage":{"tokens":{"input_tokens":50,"output_tokens":25}}}})),
    ]

    events.each_with_index do |event_json, index|
      begin
        event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(event_json)
        event.should be_a(Crig::Providers::Cohere::Streaming::StreamingEvent)
      rescue ex
        fail "Failed to deserialize event at index #{index}: #{ex.message}"
      end
    end
  end
end

describe Crig::Providers::DeepSeek::Message do
  it "deserializes vec choice assistant messages" do
    choices = JSON.parse(%([{
      "finish_reason":"stop",
      "index":0,
      "logprobs":null,
      "message":{"role":"assistant","content":"Hello, world!"}
    }])).as_a.map { |entry| Crig::Providers::DeepSeek::Choice.from_json_value(entry) }

    choices.size.should eq(1)
    choices.first.message.kind.assistant?.should be_true
    choices.first.message.content.should eq("Hello, world!")
  end

  it "merges multiple user text items into one deepseek user message" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::UserContent.text("first part").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::UserContent.text("second part").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    user_messages = messages.select(&.kind.user?)

    user_messages.size.should eq(1)
    user_messages.first.content.should eq("first part\nsecond part")
  end

  it "converts assistant messages with reasoning and tool calls" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("thinking about the problem").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("I'll call the tool").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "subtract", JSON.parse(%({"x":2,"y":5}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    messages.size.should eq(1)
    message = messages.first
    message.kind.assistant?.should be_true
    message.content.should eq("I'll call the tool")
    message.reasoning_content.should eq("thinking about the problem")
    message.tool_calls.size.should eq(1)
    message.tool_calls.first.function.name.should eq("subtract")
  end

  it "converts assistant messages without reasoning" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.text("calling tool").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "add", JSON.parse(%({"a":1,"b":2}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    messages.size.should eq(1)
    messages.first.reasoning_content.should be_nil
    messages.first.tool_calls.size.should eq(1)
  end
end

describe Crig::Providers::DeepSeek::Client do
  it "ports the deepseek client initialization" do
    client = Crig::Providers::DeepSeek::Client.new("dummy-key")
    builder_client = Crig::Providers::DeepSeek::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    builder_client.api_key.should eq("dummy-key")
    client.default_headers["Authorization"].should eq("Bearer dummy-key")
  end
end

describe Crig::Providers::DeepSeek::CompletionResponse do
  it "deserializes a deepseek response" do
    response = Crig::Providers::DeepSeek::CompletionResponse.from_json_value(JSON.parse(%({
      "choices":[{"finish_reason":"stop","index":0,"logprobs":null,"message":{"role":"assistant","content":"Hello, world!"}}],
      "usage":{"completion_tokens":0,"prompt_tokens":0,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":0,"total_tokens":0}
    })))

    response.choices.first.message.kind.assistant?.should be_true
    response.choices.first.message.content.should eq("Hello, world!")
  end

  it "deserializes the example response" do
    response = Crig::Providers::DeepSeek::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"e45f6c68-9d9e-43de-beb4-4f402b850feb",
      "object":"chat.completion",
      "created":0,
      "model":"deepseek-chat",
      "choices":[{"index":0,"message":{"role":"assistant","content":"Why don’t skeletons fight each other?  \\nBecause they don’t have the guts! 😄"},"logprobs":null,"finish_reason":"stop"}],
      "usage":{"prompt_tokens":13,"completion_tokens":32,"total_tokens":45,"prompt_tokens_details":{"cached_tokens":0},"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":13}
    })))

    response.choices.first.message.content.should eq("Why don’t skeletons fight each other?  \nBecause they don’t have the guts! 😄")
    response.usage.prompt_tokens.should eq(13)
    response.usage.completion_tokens.should eq(32)
  end

  it "serializes and deserializes tool call assistant choices" do
    choice = Crig::Providers::DeepSeek::Choice.from_json_value(JSON.parse(%({
      "finish_reason":"tool_calls",
      "index":0,
      "logprobs":null,
      "message":{
        "content":"",
        "role":"assistant",
        "tool_calls":[{"function":{"arguments":"{\\"x\\":2,\\"y\\":5}","name":"subtract"},"id":"call_0_2b4a85ee-b04a-40ad-a16b-a405caf6e65b","index":0,"type":"function"}]
      }
    })))

    choice.finish_reason.should eq("tool_calls")
    choice.message.tool_calls.first.id.should eq("call_0_2b4a85ee-b04a-40ad-a16b-a405caf6e65b")
    choice.message.tool_calls.first.function.arguments["x"].as_i.should eq(2)
  end
end

describe Crig::Providers::Gemini::Client do
  it "ports the gemini client initialization" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    builder_client = Crig::Providers::Gemini::Client.builder.api_key("dummy-key").build

    client.ext.api_key.should eq("dummy-key")
    builder_client.ext.api_key.should eq("dummy-key")
    client.build_uri("/v1beta/models").should eq("https://generativelanguage.googleapis.com/v1beta/models?key=dummy-key")
    client.build_uri("/v1beta/models", sse: true).should eq("https://generativelanguage.googleapis.com/v1beta/models?key=dummy-key&alt=sse")
  end

  it "converts between generate-content and interactions clients" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    interactions = client.interactions_api
    round_trip = interactions.generate_content_api

    interactions.ext.api_key.should eq("dummy-key")
    interactions.build_uri("/v1beta/interactions").should eq("https://generativelanguage.googleapis.com/v1beta/interactions")
    interactions.build_uri("/v1beta/interactions?foo=bar", sse: true).should eq("https://generativelanguage.googleapis.com/v1beta/interactions?foo=bar&alt=sse")
    round_trip.ext.api_key.should eq("dummy-key")
  end
end

describe Crig::Providers::Gemini do
  it "ports the gemini completion constants and endpoint helpers" do
    Crig::Providers::Gemini::GEMINI_2_5_FLASH.should eq("gemini-2.5-flash")
    Crig::Providers::Gemini.completion_endpoint("gemini-2.5-flash").should eq("/v1beta/models/gemini-2.5-flash:generateContent")
    Crig::Providers::Gemini.streaming_endpoint("gemini-2.5-flash").should eq("/v1beta/models/gemini-2.5-flash:streamGenerateContent")
  end

  it "resolves the request model override and default" do
    default_request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("hello")
      .build
    override_request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("hello")
      .model("google/gemini-2.5-flash")
      .build

    Crig::Providers::Gemini.resolve_request_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH, default_request).should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    Crig::Providers::Gemini.resolve_request_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH, override_request).should eq("google/gemini-2.5-flash")
  end
end

describe Crig::Providers::Gemini::AdditionalParameters do
  it "ports the additional-parameters helper methods" do
    config = Crig::Providers::Gemini::GenerationConfig.new
    params = Crig::Providers::Gemini::AdditionalParameters.new
      .with_config(config)
      .with_params(JSON.parse(%({"candidateCount":2})))

    params.generation_config.should eq(config)
    params.additional_params.not_nil!["candidateCount"].as_i.should eq(2)
  end

  it "round-trips the broader generation-config field set" do
    config = Crig::Providers::Gemini::GenerationConfig.from_json(%({
      "stopSequences":["DONE","STOP"],
      "responseMimeType":"application/json",
      "responseSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]},
      "_responseJsonSchema":{"type":"object","properties":{"age":{"type":"integer"}}},
      "responseJsonSchema":{"type":"object","properties":{"city":{"type":"string"}}},
      "candidateCount":1,
      "maxOutputTokens":64,
      "temperature":0.2,
      "topP":0.9,
      "topK":20,
      "presencePenalty":0.1,
      "frequencyPenalty":0.3,
      "responseLogprobs":true,
      "logprobs":5
    }))

    config.stop_sequences.should eq(["DONE", "STOP"])
    config.response_mime_type.should eq("application/json")
    config.response_schema.not_nil!.type.should eq("object")
    config.response_schema.not_nil!.properties.not_nil!["name"].type.should eq("string")
    config.internal_response_json_schema.not_nil!["properties"]["age"]["type"].as_s.should eq("integer")
    config.response_json_schema.not_nil!["properties"]["city"]["type"].as_s.should eq("string")
    config.candidate_count.should eq(1)
    config.max_output_tokens.should eq(64_i64)
    config.temperature.should eq(0.2)
    config.top_p.should eq(0.9)
    config.top_k.should eq(20)
    config.presence_penalty.should eq(0.1)
    config.frequency_penalty.should eq(0.3)
    config.response_logprobs.should be_true
    config.logprobs.should eq(5)
    config.empty?.should be_false

    roundtrip = JSON.parse(config.to_json)
    roundtrip["stopSequences"].as_a.map(&.as_s).should eq(["DONE", "STOP"])
    roundtrip["responseSchema"]["properties"]["name"]["type"].as_s.should eq("string")
    roundtrip["_responseJsonSchema"]["properties"]["age"]["type"].as_s.should eq("integer")
    roundtrip["responseJsonSchema"]["properties"]["city"]["type"].as_s.should eq("string")
    roundtrip["responseLogprobs"].as_bool.should be_true
    roundtrip["logprobs"].as_i.should eq(5)
  end
end

describe Crig::Providers::Gemini::CompletionModel do
  it "supports the class-level with_model helper" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    model = Crig::Providers::Gemini::CompletionModel.with_model(client, Crig::Providers::Gemini::GEMINI_2_0_FLASH)

    model.client.should eq(client)
    model.model.should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
  end
end

describe Crig::Providers::Gemini::Content do
  it "deserializes a user message" do
    content = Crig::Providers::Gemini::Content.from_json(%({
      "parts": [
        {"text": "Hello, world!"},
        {"inlineData": {"mimeType": "image/png", "data": "base64encodeddata"}},
        {"functionCall": {"name": "test_function", "args": {"arg1": "value1"}}},
        {"functionResponse": {"name": "test_function", "response": {"result": "success"}}},
        {"fileData": {"mimeType": "application/pdf", "fileUri": "http://example.com/file.pdf"}},
        {"executableCode": {"code": "print('Hello, world!')", "language": "PYTHON"}},
        {"codeExecutionResult": {"output": "Hello, world!", "outcome": "OUTCOME_OK"}}
      ],
      "role": "user"
    }))

    content.role.should eq(Crig::Providers::Gemini::Role::User)
    content.parts.size.should eq(7)
    content.parts[0].part.kind.text?.should be_true
    content.parts[0].part.text.should eq("Hello, world!")
    content.parts[1].part.kind.inline_data?.should be_true
    content.parts[1].part.inline_data.not_nil!.mime_type.should eq("image/png")
    content.parts[2].part.function_call.not_nil!.name.should eq("test_function")
    content.parts[2].part.function_call.not_nil!.args["arg1"].as_s.should eq("value1")
    content.parts[3].part.function_response.not_nil!.response.not_nil!["result"].as_s.should eq("success")
    content.parts[4].part.file_data.not_nil!.file_uri.should eq("http://example.com/file.pdf")
    content.parts[5].part.executable_code.not_nil!.code.should eq("print('Hello, world!')")
    content.parts[6].part.code_execution_result.not_nil!.output.should eq("Hello, world!")
  end

  it "deserializes a model message" do
    content = Crig::Providers::Gemini::Content.from_json(%({
      "parts": [{"text": "Hello, user!"}],
      "role": "model"
    }))

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    content.parts.first.part.text.should eq("Hello, user!")
  end

  it "emits the reasoning signature in a gemini part" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new_with_signature("structured thought", "reuse_sig_456"),
        ).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(message)
    first = content.parts.first

    first.thought.should be_true
    first.thought_signature.should eq("reuse_sig_456")
    first.part.kind.text?.should be_true
    first.part.text.should eq("structured thought")
  end

  it "converts a user message into gemini content" do
    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.user("Hello, world!"))

    content.role.should eq(Crig::Providers::Gemini::Role::User)
    content.parts.size.should eq(1)
    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("Hello, world!")
  end

  it "converts an assistant message into gemini content" do
    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.assistant("Hello, user!"))

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("Hello, user!")
  end

  it "converts an assistant tool call into a gemini function call part" do
    message = Crig::Completion::Message.from(
      Crig::Completion::ToolCall.new(
        "test_tool",
        Crig::Completion::ToolFunction.new("test_function", JSON.parse(%({"arg1":"value1"}))),
      )
    )

    content = Crig::Providers::Gemini::Content.from_message(message)

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    function_call = content.parts.first.part.function_call.not_nil!
    function_call.name.should eq("test_function")
    function_call.args["arg1"].as_s.should eq("value1")
  end

  it "converts txt documents into text parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.string("Note: test.md\nPath: /test.md\nContent: Hello World!"),
        Crig::Completion::DocumentMediaType::TXT,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.not_nil!.includes?("Note: test.md").should be_true
    content.parts.first.part.text.not_nil!.includes?("Hello World!").should be_true
  end

  it "converts markdown documents into text parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.string("# Heading\n\n* List item"),
        Crig::Completion::DocumentMediaType::MARKDOWN,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("# Heading\n\n* List item")
  end

  it "converts url-backed markdown documents into file data parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.url("https://generativelanguage.googleapis.com/v1beta/files/test-markdown"),
        Crig::Completion::DocumentMediaType::MARKDOWN,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    file_data = content.parts.first.part.file_data.not_nil!
    file_data.file_uri.should eq("https://generativelanguage.googleapis.com/v1beta/files/test-markdown")
    file_data.mime_type.should eq("text/markdown")
  end

  it "converts tool results with image content" do
    content = Crig::Providers::Gemini::Content.from_message(
      Crig::Completion::Message.from(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: Crig::Completion::ToolResult.new(
            "test_tool",
            Crig::OneOrMany(Crig::Completion::ToolResultContent).many([
              Crig::Completion::ToolResultContent.text(%({"status":"success"})),
              Crig::Completion::ToolResultContent.image_base64(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
                Crig::Completion::ImageMediaType::PNG,
              ),
            ])
          ),
        )
      )
    )

    function_response = content.parts.first.part.function_response.not_nil!
    function_response.name.should eq("test_tool")
    function_response.response.should_not be_nil
    function_response.response.not_nil!["result"]["status"].as_s.should eq("success")
    function_response.parts.should_not be_nil
    function_response.parts.not_nil!.size.should eq(1)
    function_response.parts.not_nil!.first.inline_data.not_nil!.mime_type.should eq("image/png")
  end

  it "converts tool results with url images into file data parts" do
    content = Crig::Providers::Gemini::Content.from_message(
      Crig::Completion::Message.from(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: Crig::Completion::ToolResult.new(
            "screenshot_tool",
            Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
              Crig::Completion::ToolResultContent.image_url(
                "https://example.com/image.png",
                Crig::Completion::ImageMediaType::PNG,
              )
            )
          ),
        )
      )
    )

    function_response = content.parts.first.part.function_response.not_nil!
    function_response.name.should eq("screenshot_tool")
    file_data = function_response.parts.not_nil!.first.file_data.not_nil!
    file_data.file_uri.should eq("https://example.com/image.png")
    file_data.mime_type.should eq("image/png")
  end
end

describe Crig::Providers::Gemini::Schema do
  it "ports the object schema conversion" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "object",
      "properties": {
        "name": {"type": "string"}
      }
    })))

    schema.type.should eq("object")
    schema.properties.should_not be_nil
    schema.properties.not_nil!.has_key?("name").should be_true
  end

  it "ports arrays with inline items" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }
    })))

    schema.type.should eq("array")
    schema.items.should_not be_nil
    schema.items.not_nil!.type.should eq("object")
    schema.items.not_nil!.properties.should_not be_nil
  end

  it "flattens referenced schemas" do
    flattened = Crig::Providers::Gemini.flatten_schema(JSON.parse(%({
      "type": "array",
      "items": {"$ref": "#/$defs/Person"},
      "$defs": {
        "Person": {
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }
      }
    })))

    schema = Crig::Providers::Gemini::Schema.try_from(flattened)
    schema.type.should eq("array")
    schema.items.should_not be_nil
    schema.items.not_nil!.type.should eq("object")
    schema.items.not_nil!.properties.should_not be_nil
  end

  it "adds default string items to arrays without items" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "object",
      "properties": {
        "service_ids": {
          "type": "array",
          "description": "A list of service IDs"
        }
      }
    })))

    service_ids = schema.properties.not_nil!["service_ids"]
    service_ids.type.should eq("array")
    service_ids.items.should_not be_nil
    service_ids.items.not_nil!.type.should eq("string")
  end
end

describe Crig::Providers::Gemini::GenerateContentResponse do
  it "preserves thought signatures from response reasoning parts" do
    response = Crig::Providers::Gemini::GenerateContentResponse.new(
      "resp_1",
      [
        Crig::Providers::Gemini::ContentCandidate.new(
          content: Crig::Providers::Gemini::Content.new(
            [
              Crig::Providers::Gemini::Part.new(
                Crig::Providers::Gemini::PartKind.text("thinking text"),
                thought: true,
                thought_signature: "thought_sig_123",
              ),
            ],
            role: Crig::Providers::Gemini::Role::Model,
          ),
          finish_reason: Crig::Providers::Gemini::FinishReason::Stop,
        ),
      ],
    )

    converted = response.to_completion_response
    reasoning = converted.choice.first.reasoning.not_nil!
    reasoning.first_text.should eq("thinking text")
    reasoning.first_signature.should eq("thought_sig_123")
  end

  it "deserializes prompt feedback, safety, citation, and logprob metadata" do
    response = Crig::Providers::Gemini::GenerateContentResponse.from_json(%({
      "responseId":"resp_meta",
      "promptFeedback":{
        "blockReason":"SAFETY",
        "safetyRatings":[
          {"category":"HARM_CATEGORY_HATE_SPEECH","probability":"HIGH"}
        ]
      },
      "candidates":[
        {
          "content":{"parts":[{"text":"hello"}],"role":"model"},
          "finishReason":"STOP",
          "safetyRatings":[
            {"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"LOW"}
          ],
          "citationMetadata":{
            "citationSources":[
              {"uri":"https://example.com","startIndex":0,"endIndex":5,"license":"CC-BY"}
            ]
          },
          "tokenCount":4,
          "avgLogprobs":-0.25,
          "logprobsResult":{
            "topCandidates":[
              {"candidates":[{"token":"hello","tokenId":"1","logProbability":-0.25}]}
            ],
            "chosenCandidates":[
              {"token":"hello","tokenId":"1","logProbability":-0.25}
            ]
          },
          "index":0,
          "finishMessage":"done"
        }
      ],
      "usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}
    }))

    response.prompt_feedback.not_nil!.block_reason.should eq(Crig::Providers::Gemini::BlockReason::Safety)
    response.prompt_feedback.not_nil!.safety_ratings.not_nil!.first.category.should eq(
      Crig::Providers::Gemini::HarmCategory::HarmCategoryHateSpeech
    )
    candidate = response.candidates.first
    candidate.safety_ratings.not_nil!.first.probability.should eq(Crig::Providers::Gemini::HarmProbability::Low)
    candidate.citation_metadata.not_nil!.citation_sources.first.uri.should eq("https://example.com")
    candidate.logprobs_result.not_nil!.chosen_candidates.first.token.should eq("hello")
    candidate.finish_message.should eq("done")
  end
end

describe Crig::Providers::Gemini::ExecutableCode do
  it "serializes execution language using the upstream wire values" do
    payload = JSON.parse(
      Crig::Providers::Gemini::ExecutableCode.new(
        Crig::Providers::Gemini::ExecutionLanguage::Python,
        "print('hi')"
      ).to_json
    )

    payload["language"].as_s.should eq("PYTHON")
    payload["code"].as_s.should eq("print('hi')")
  end
end

describe Crig::Providers::Gemini::CodeExecutionResult do
  it "deserializes code execution outcomes using the upstream wire values" do
    result = Crig::Providers::Gemini::CodeExecutionResult.from_json(%({
      "outcome":"OUTCOME_DEADLINE_EXCEEDED",
      "output":"partial output"
    }))

    result.outcome.should eq(Crig::Providers::Gemini::CodeExecutionOutcome::DeadlineExceeded)
    result.output.should eq("partial output")
  end
end

describe Crig::Providers::Gemini::TranscriptionModel do
  it "posts generateContent transcription requests and extracts the returned text" do
    server = FakeGeminiGenerateContentServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"responseId":"resp","candidates":[{"content":{"parts":[{"text":"hello world"}],"role":"model"}}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("gemini-key", "http://127.0.0.1:#{address.port}")
    response = client.transcription_model("gemini-2.0-flash")
      .transcription(
        Crig::TranscriptionRequest.new(
          "abc".to_slice,
          "speech.wav",
          temperature: 0.2,
          additional_params: JSON.parse(%({"maxOutputTokens":64}))
        )
      )

    response.text.should eq("hello world")
    request = server.requests.first
    request["generationConfig"]["temperature"].as_f.should eq(0.2)
    request["generationConfig"]["maxOutputTokens"].as_i.should eq(64)
    request["systemInstruction"]["parts"][0]["text"].as_s.should eq(
      "Translate the provided audio exactly. Do not add additional information."
    )
    blob = request["contents"][0]["parts"][0]["inlineData"]
    blob["mimeType"].as_s.should eq("audio/wav")
    Base64.decode_string(blob["data"].as_s).should eq("abc")

    http_server.close
  end

  it "surfaces provider errors from generateContent" do
    server = FakeGeminiGenerateContentServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"error":"bad transcription"}),
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("gemini-key", "http://127.0.0.1:#{address.port}")

    expect_raises(Crig::TranscriptionError, /bad transcription/) do
      client.transcription_model("gemini-2.0-flash")
        .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.unknown"))
    end

    http_server.close
  end
end

describe Crig::Providers::Gemini::StreamGenerateContentResponse do
  it "deserializes a stream response with single text part" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[{"text":"Hello, world!"}],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}
    }))

    response.candidates.size.should eq(1)
    response.candidates.first.content.not_nil!.parts.size.should eq(1)
    response.candidates.first.content.not_nil!.parts.first.part.text.should eq("Hello, world!")
  end

  it "deserializes a stream response with multiple text parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[{"text":"Hello, "},{"text":"world!"},{"text":" How are you?"}],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":8,"totalTokenCount":18}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts.map { |part| part.part.text }.should eq(["Hello, ", "world!", " How are you?"])
  end

  it "deserializes a stream response with multiple tool calls" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{
          "parts":[
            {"functionCall":{"name":"get_weather","args":{"city":"San Francisco"}}},
            {"functionCall":{"name":"get_temperature","args":{"location":"New York"}}}
          ],
          "role":"model"
        },
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":20,"totalTokenCount":70}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts[0].part.function_call.not_nil!.name.should eq("get_weather")
    parts[1].part.function_call.not_nil!.name.should eq("get_temperature")
  end

  it "deserializes a stream response with mixed parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{
          "parts":[
            {"text":"Let me think about this...","thought":true},
            {"text":"Here's my response: "},
            {"functionCall":{"name":"search","args":{"query":"rust async"}}},
            {"text":"I found the answer!"}
          ],
          "role":"model"
        },
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":50,"thoughtsTokenCount":15,"totalTokenCount":165}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts.size.should eq(4)
    parts[0].thought.should be_true
    parts[0].part.text.should eq("Let me think about this...")
    parts[1].part.text.should eq("Here's my response: ")
    parts[2].part.function_call.not_nil!.name.should eq("search")
    parts[3].part.text.should eq("I found the answer!")
  end

  it "deserializes a stream response with empty parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":0,"totalTokenCount":10}
    }))

    response.candidates.first.content.not_nil!.parts.should be_empty
  end
end

describe Crig::Providers::Gemini::PartialUsage do
  it "calculates token usage" do
    usage = Crig::Providers::Gemini::PartialUsage.new(
      total_token_count: 100,
      cached_content_token_count: 20,
      candidates_token_count: 30,
      thoughts_token_count: 10,
      prompt_token_count: 40,
    )

    token_usage = usage.token_usage
    token_usage.input_tokens.should eq(40)
    token_usage.output_tokens.should eq(60)
    token_usage.total_tokens.should eq(100)
  end

  it "calculates token usage with missing counts" do
    usage = Crig::Providers::Gemini::PartialUsage.new(
      total_token_count: 40,
      prompt_token_count: 40,
    )

    token_usage = usage.token_usage
    token_usage.input_tokens.should eq(40)
    token_usage.output_tokens.should eq(0)
    token_usage.total_tokens.should eq(40)
  end
end

describe Crig::Providers::Gemini::StreamingCompletionResponse do
  it "converts partial usage into token usage" do
    response = Crig::Providers::Gemini::StreamingCompletionResponse.new(
      Crig::Providers::Gemini::PartialUsage.new(
        total_token_count: 15,
        candidates_token_count: 5,
        prompt_token_count: 10,
      )
    )

    token_usage = response.token_usage
    token_usage.input_tokens.should eq(10)
    token_usage.output_tokens.should eq(5)
    token_usage.total_tokens.should eq(15)
  end
end

describe Crig::Providers::Together::ApiErrorResponse do
  it "formats provider errors with the upstream code prefix" do
    Crig::Providers::Together::ApiErrorResponse.new("bad request", "invalid_request_error").message
      .should eq("Code `invalid_request_error`: bad request")
  end
end

describe Crig::Providers::Together::Client do
  it "initializes directly and from the builder" do
    direct = Crig::Providers::Together::Client.new("dummy-key")
    built = Crig::Providers::Together::Client.builder.api_key("dummy-key").build

    direct.api_key.token.should eq("dummy-key")
    built.api_key.token.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::Together::TOGETHER_AI_BASE_URL)
  end
end

describe Crig::Providers::Together::ToolChoice do
  it "maps specific tool choices into together function lists" do
    choice = Crig::Providers::Together::ToolChoice.from_core(
      Crig::Completion::ToolChoice.specific(["search", "lookup"])
    )

    choice.kind.function?.should be_true
    choice.functions.map(&.name).should eq(["search", "lookup"])
    choice.to_json_value.to_json.should eq(%([{"type":"function","function":{"name":"search"}},{"type":"function","function":{"name":"lookup"}}]))
  end
end

describe Crig::Providers::Together::TogetherAICompletionRequest do
  it "errors when all converted messages are filtered out" do
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(
        Crig::Completion::Message.new(
          Crig::Completion::Message::Role::Assistant,
          Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
            Crig::Completion::AssistantContent.reasoning("hidden")
          )
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, "Together request has no provider-compatible messages after conversion") do
      Crig::Providers::Together::TogetherAICompletionRequest.from_request("meta-llama/test-model", request)
    end
  end
end

describe Crig::Providers::Gemini::EmbeddingModel do
  it "posts batch embed requests and returns embeddings" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print(%({
        "embeddings":[
          {"values":[0.1,0.2]},
          {"values":[0.3,0.4]}
        ]
      }))
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.embedding_model_with_ndims(Crig::Providers::Gemini::EMBEDDING_004, 2)
    embeddings = model.embed_texts(["hello", "world"])

    embeddings.map(&.document).should eq(["hello", "world"])
    embeddings[0].vec.should eq([0.1, 0.2])
    embeddings[1].vec.should eq([0.3, 0.4])

    payload = requests.first
    payload["requests"].as_a.size.should eq(2)
    payload["requests"].as_a.first["model"].as_s.should eq("models/#{Crig::Providers::Gemini::EMBEDDING_004}")
    payload["requests"].as_a.first["content"]["parts"].as_a.first["text"].as_s.should eq("hello")
    payload["requests"].as_a.first["outputDimensionality"].as_i.should eq(2)

    http_server.close
  end
end

describe Crig::Completion::ToolResultContent, tags: %w[completion content] do
  it "parses image json tool output" do
    result = Crig::Completion::ToolResultContent.from_tool_output(%({"type":"image","data":"base64data==","mimeType":"image/jpeg"}))

    result.len.should eq(1)
    item = result.first
    item.kind.image?.should be_true
    image = item.image.not_nil!
    image.data.kind.base64?.should be_true
    image.data.string_value.should eq("base64data==")
    image.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
  end

  it "parses hybrid response and image tool output" do
    result = Crig::Completion::ToolResultContent.from_tool_output(%({
      "response": {"status": "ok", "count": 42},
      "parts": [
        {"type": "image", "data": "imgdata1==", "mimeType": "image/png"},
        {"type": "image", "data": "https://example.com/img.jpg", "mimeType": "image/jpeg"}
      ]
    }))

    result.len.should eq(3)
    items = result.to_a
    items[0].kind.text?.should be_true
    items[0].text.not_nil!.text.includes?("status").should be_true
    items[1].kind.image?.should be_true
    items[1].image.not_nil!.data.kind.base64?.should be_true
    items[2].kind.image?.should be_true
    items[2].image.not_nil!.data.kind.url?.should be_true
  end
end

describe Crig::Providers::Gemini::CompletionModel do
  it "posts generate-content requests and returns converted assistant content" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print(%({
        "responseId":"resp_123",
        "candidates":[{
          "content":{"parts":[{"text":"hello"}],"role":"model"},
          "finishReason":"Stop"
        }],
        "usageMetadata":{
          "promptTokenCount":2,
          "candidatesTokenCount":1,
          "totalTokenCount":3
        }
      }))
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    response = model.completion(model.completion_request("Hello").build)

    response.choice.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(3)
    requests.first["contents"].as_a.first["parts"].as_a.first["text"].as_s.should eq("Hello")

    http_server.close
  end

  it "parses streaming text, reasoning, and tool call chunks" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"candidates":[{"content":{"parts":[{"text":"thinking","thought":true}],"role":"model"}}],"usageMetadata":{"promptTokenCount":3,"totalTokenCount":3}}

data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"search","args":{"query":"rust"}}}],"role":"model"}}],"usageMetadata":{"promptTokenCount":3,"totalTokenCount":3}}

data: {"candidates":[{"content":{"parts":[{"text":"done"}],"role":"model"},"finishReason":"Stop"}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2,"thoughtsTokenCount":1,"totalTokenCount":6}}

data: [DONE]

SSE
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Search").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::Gemini::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "thinking" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "done" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "search" }.should be_true
    items.last.kind.final?.should be_true
    response.response.not_nil!.usage_metadata.total_token_count.should eq(6)
    requests.first["contents"].as_a.first["parts"].as_a.first["text"].as_s.should eq("Search")

    http_server.close
  end

  it "creates a request body with documents" do
    model = Crig::Providers::Gemini::CompletionModel.new(Crig::Providers::Gemini::Client.new("dummy-key"), Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("What are my notes about?")
      .preamble("You are a helpful assistant")
      .document(Crig::Completion::Request::Document.new("doc1", "Note: first.md\nContent: First note"))
      .document(Crig::Completion::Request::Document.new("doc2", "Note: second.md\nContent: Second note"))
      .build

    body = model.create_request_body(request)

    body.contents.size.should eq(2)
    body.contents[0].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[0].parts.size.should eq(2)
    body.contents[0].parts.each do |part|
      part.part.kind.text?.should be_true
      part.part.text.not_nil!.includes?("Note:").should be_true
      part.part.text.not_nil!.includes?("Content:").should be_true
    end
    body.contents[1].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[1].parts.first.part.text.should eq("What are my notes about?")
    body.system_instruction.not_nil!.role.should eq(Crig::Providers::Gemini::Role::Model)
  end

  it "creates a request body without documents" do
    model = Crig::Providers::Gemini::CompletionModel.new(Crig::Providers::Gemini::Client.new("dummy-key"), Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("You are a helpful assistant")
      .build

    body = model.create_request_body(request)

    body.contents.size.should eq(1)
    body.contents[0].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[0].parts.first.part.text.should eq("Hello")
    body.system_instruction.not_nil!.parts.first.part.text.should eq("You are a helpful assistant")
  end
end

describe Crig::Providers::Gemini::Interactions do
  it "creates the simple interaction request body" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be precise.")
      .temperature(0.7)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    result = Crig::Providers::Gemini::Interactions.create_request_body(
      "gemini-2.5-flash",
      request,
      false
    )

    result.model.should eq("gemini-2.5-flash")
    result.agent.should be_nil
    result.stream.should eq(false)
    result.system_instruction.should eq("Be precise.")

    config = result.generation_config.not_nil!
    config.temperature.should eq(0.7)
    config.max_output_tokens.should eq(128)
    config.tool_choice.not_nil!.kind.type?.should be_true
    config.tool_choice.not_nil!.type.should eq(Crig::Providers::Gemini::Interactions::ToolChoiceType::Any)

    result.input.kind.turns?.should be_true
    turn = result.input.turns.not_nil!.first
    turn.role.should eq(Crig::Providers::Gemini::Interactions::Role::User)
    turn.content.kind.contents?.should be_true
    content = turn.content.contents.not_nil!.first
    content.kind.text?.should be_true
    content.text.not_nil!.text.should eq("Hello")
  end

  it "requires call_id for tool result content" do
    content = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::ToolResult,
      tool_result: Crig::Completion::ToolResult.new(
        "get_weather",
        Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
          Crig::Completion::ToolResultContent.text("ok")
        )
      )
    )

    expect_raises(Crig::Completion::MessageError, /call_id/) do
      Crig::Providers::Gemini::Interactions::Content.from_user_content(content)
    end
  end

  it "maps response function calls into completion tool calls" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "id":"interaction-1",
      "outputs":[{"type":"function_call","name":"get_weather","arguments":{"location":"Paris"},"id":"call-123"}],
      "usage":{"total_input_tokens":5,"total_output_tokens":7,"total_tokens":12}
    }))

    model = Crig::Providers::Gemini::Interactions::InteractionsCompletionModel.new(
      Crig::Providers::Gemini::InteractionsClient.new("dummy-key"),
      "gemini-2.5-flash"
    )
    response = model.interaction_to_completion_response(interaction)

    choice = response.choice.first
    choice.kind.tool_call?.should be_true
    choice.tool_call.not_nil!.function.name.should eq("get_weather")
    choice.tool_call.not_nil!.call_id.should eq("call-123")
    response.usage.input_tokens.should eq(5)
    response.usage.output_tokens.should eq(7)
    response.usage.total_tokens.should eq(12)
  end

  it "serializes google search, url context, and code execution tools" do
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.google_search.to_json)["type"].as_s.should eq("google_search")
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.url_context.to_json)["type"].as_s.should eq("url_context")
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.code_execution.to_json)["type"].as_s.should eq("code_execution")
  end

  it "groups google search helpers by call id" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"google_search_call","arguments":{"queries":["query-one","query-two"]},"id":"call-1"},
        {"type":"google_search_result","result":[{"url":"https://example.com","title":"Example One"}],"call_id":"call-1"},
        {"type":"google_search_call","arguments":{"queries":["query-three"]},"id":"call-2"},
        {"type":"google_search_result","result":[{"url":"https://example.org","title":"Example Two"}],"call_id":"call-2"}
      ]
    }))

    exchanges = interaction.google_search_exchanges
    exchanges.size.should eq(2)
    exchanges[0].call_id.should eq("call-1")
    exchanges[0].queries.should eq(["query-one", "query-two"])
    exchanges[0].result_items.first.title.should eq("Example One")
    interaction.google_search_queries.should eq(["query-one", "query-two", "query-three"])
    interaction.google_search_results.map(&.title).should eq(["Example One", "Example Two"])
  end

  it "groups url context and code execution helpers without call ids by recency" do
    url_interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"url_context_call","arguments":{"urls":["https://example.com"]}},
        {"type":"url_context_result","result":[{"url":"https://example.com","status":"success"}]},
        {"type":"url_context_call","arguments":{"urls":["https://example.org"]},"id":"call-2"},
        {"type":"url_context_result","result":[{"url":"https://example.org","status":"success"}]}
      ]
    }))
    url_interaction.url_context_exchanges.size.should eq(2)
    url_interaction.url_context_exchanges.find(&.call_id.nil?).not_nil!.results.size.should eq(1)
    url_interaction.url_context_exchanges.find { |exchange| exchange.call_id == "call-2" }.not_nil!.results.size.should eq(1)

    code_interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"code_execution_call","arguments":{"language":"python","code":"print(1)"}},
        {"type":"code_execution_result","result":"1"},
        {"type":"code_execution_call","arguments":{"language":"python","code":"print(2)"},"id":"call-2"},
        {"type":"code_execution_result","result":"2"}
      ]
    }))
    code_interaction.code_execution_exchanges.size.should eq(2)
    code_interaction.code_execution_exchanges.find(&.call_id.nil?).not_nil!.outputs.should eq(["1"])
    code_interaction.code_execution_exchanges.find { |exchange| exchange.call_id == "call-2" }.not_nil!.code_snippets.should eq(["print(2)"])
  end

  it "reports interaction terminal and completed helpers" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({"status":"completed","outputs":[]}))
    interaction.is_terminal.should be_true
    interaction.is_completed.should be_true

    failed = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({"status":"failed","outputs":[]}))
    failed.is_terminal.should be_true
    failed.is_completed.should be_false
  end

  it "builds the interaction stream path" do
    Crig::Providers::Gemini::Interactions.build_interaction_stream_path("interaction-123").should eq(
      "/v1beta/interactions/interaction-123?stream=true"
    )
    Crig::Providers::Gemini::Interactions.build_interaction_stream_path("interaction-123", "event-456").should eq(
      "/v1beta/interactions/interaction-123?stream=true&last_event_id=event-456"
    )
  end

  it "adds inline citations from annotations" do
    text_content = Crig::Providers::Gemini::Interactions::TextContent.new(
      "Hello world",
      [
        Crig::Providers::Gemini::Interactions::Annotation.new(start_index: 6, end_index: 11, source: "https://example.com"),
        Crig::Providers::Gemini::Interactions::Annotation.new(start_index: 0, end_index: 5, source: "https://hello.example"),
      ]
    )

    text_content.with_inline_citations.should eq("Hello[1](https://hello.example) world[2](https://example.com)")

    interaction = Crig::Providers::Gemini::Interactions::Interaction.new(
      outputs: [Crig::Providers::Gemini::Interactions::Content.text(text_content)]
    )
    interaction.text_with_inline_citations.should eq("Hello[1](https://hello.example) world[2](https://example.com)")
  end

  it "parses typed agent config and tool choice config from additional params" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .additional_params(
        JSON.parse(%({
          "agent_config":{"type":"deep-research","thinking_summaries":"auto"},
          "generation_config":{
            "tool_choice":{
              "allowed_tools":{
                "mode":"validated",
                "tools":["lookup"]
              }
            }
          }
        }))
      )
      .build

    result = Crig::Providers::Gemini::Interactions.create_request_body(
      "gemini-2.5-flash",
      request,
      false
    )

    result.agent_config.not_nil!.kind.deep_research?.should be_true
    result.agent_config.not_nil!.thinking_summaries.should eq(Crig::Providers::Gemini::Interactions::ThinkingSummaries::Auto)
    result.generation_config.not_nil!.tool_choice.not_nil!.kind.config?.should be_true
    result.generation_config.not_nil!.tool_choice.not_nil!.config.not_nil!.allowed_tools.mode.should eq(
      Crig::Providers::Gemini::Interactions::ToolChoiceType::Validated
    )
    result.generation_config.not_nil!.tool_choice.not_nil!.config.not_nil!.allowed_tools.tools.should eq(["lookup"])
  end

  it "serializes and deserializes extended interaction tool variants" do
    computer_use = Crig::Providers::Gemini::Interactions::Tool.computer_use(
      Crig::Providers::Gemini::Interactions::ComputerUseTool.new(
        environment: "browser",
        excluded_predefined_functions: ["shell"]
      )
    )
    mcp_server = Crig::Providers::Gemini::Interactions::Tool.mcp_server(
      Crig::Providers::Gemini::Interactions::McpServerTool.new(
        name: "github",
        url: "https://example.com/mcp",
        headers: JSON.parse(%({"Authorization":"Bearer token"})),
        allowed_tools: Crig::Providers::Gemini::Interactions::AllowedTools.new(
          mode: Crig::Providers::Gemini::Interactions::ToolChoiceType::Validated,
          tools: ["issues.list"]
        )
      )
    )
    file_search = Crig::Providers::Gemini::Interactions::Tool.file_search(
      Crig::Providers::Gemini::Interactions::FileSearchTool.new(
        file_search_store_names: ["kb"],
        top_k: 5_i64,
        metadata_filter: "kind = 'policy'"
      )
    )

    parsed_computer_use = Crig::Providers::Gemini::Interactions::Tool.from_json(computer_use.to_json)
    parsed_mcp_server = Crig::Providers::Gemini::Interactions::Tool.from_json(mcp_server.to_json)
    parsed_file_search = Crig::Providers::Gemini::Interactions::Tool.from_json(file_search.to_json)

    parsed_computer_use.kind.computer_use?.should be_true
    parsed_computer_use.computer_use.not_nil!.environment.should eq("browser")
    parsed_mcp_server.kind.mcp_server?.should be_true
    parsed_mcp_server.mcp_server.not_nil!.name.should eq("github")
    parsed_mcp_server.mcp_server.not_nil!.allowed_tools.not_nil!.tools.should eq(["issues.list"])
    parsed_file_search.kind.file_search?.should be_true
    parsed_file_search.file_search.not_nil!.file_search_store_names.should eq(["kb"])
    parsed_file_search.file_search.not_nil!.top_k.should eq(5_i64)
  end

  it "converts multimodal content and thought summary variants" do
    audio = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.audio("audiodata", Crig::Completion::AudioMediaType::MP3)
    )
    document = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.document("plain text document", Crig::Completion::DocumentMediaType::TXT)
    )
    video = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          Crig::Completion::VideoMediaType::MP4
        )
      )
    )
    thought_summary = Crig::Providers::Gemini::Interactions::ThoughtSummaryContent.from_json(%({
      "data":"SGVsbG8=",
      "mime_type":"image/png",
      "resolution":"high"
    }))

    audio.kind.audio?.should be_true
    audio.audio.not_nil!.mime_type.should eq("audio/mp3")
    document.kind.document?.should be_true
    document.document.not_nil!.data.should eq("plain text document")
    video.kind.video?.should be_true
    video.video.not_nil!.uri.should eq("https://example.com/video.mp4")
    thought_summary.kind.image?.should be_true
    thought_summary.image.not_nil!.mime_type.should eq("image/png")
    thought_summary.image.not_nil!.resolution.should eq(Crig::Providers::Gemini::Interactions::MediaResolution::High)
  end
end

describe Crig::Providers::Gemini::Interactions::Streaming do
  it "maps text content delta events" do
    event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.delta",
      "index":0,
      "delta":{"type":"text","text":"Hello"}
    }))

    event.kind.content_delta?.should be_true
    choice = Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(event.delta.not_nil!)
    choice.not_nil!.kind.message?.should be_true
    choice.not_nil!.message.should eq("Hello")
  end

  it "maps function call content delta events" do
    event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.delta",
      "index":0,
      "delta":{"type":"function_call","name":"get_weather","arguments":{"location":"Paris"},"id":"call-1"}
    }))

    choice = Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(event.delta.not_nil!)
    choice.not_nil!.kind.tool_call?.should be_true
    choice.not_nil!.tool_call.not_nil!.name.should eq("get_weather")
    choice.not_nil!.tool_call.not_nil!.call_id.should eq("call-1")
  end

  it "parses raw interaction event streams" do
    events = Crig::Providers::Gemini::Interactions::Streaming.parse_event_stream(<<-SSE)
data: {"event_type":"content.start","index":0,"content":{"type":"text","text":"Hello"}}

data: {"event_type":"content.delta","index":0,"delta":{"type":"text","text":" world"}}

data: {"event_type":"interaction.complete","interaction":{"id":"interaction-1","outputs":[{"type":"text","text":"Hello world"}],"usage":{"total_input_tokens":1,"total_output_tokens":2,"total_tokens":3}}}

data: [DONE]
SSE

    events.size.should eq(3)
    events[0].kind.content_start?.should be_true
    events[1].kind.content_delta?.should be_true
    events[2].kind.interaction_complete?.should be_true
    events[2].interaction.not_nil!.id.should eq("interaction-1")
  end

  it "parses broader interaction event and delta variants" do
    status_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"interaction.status_update",
      "interaction_id":"interaction-1",
      "status":"requires_action",
      "event_id":"event-1"
    }))
    stop_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.stop",
      "index":2,
      "event_id":"event-2"
    }))
    error_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"error",
      "error":{"code":"bad_request","message":"boom"},
      "event_id":"event-3"
    }))
    mcp_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"mcp_server_tool_call",
      "name":"issues.list",
      "server_name":"github",
      "arguments":{"repo":"crig"},
      "id":"call-7"
    }))
    file_search_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"file_search_result",
      "result":[{"title":"Policy","text":"Always test.","file_search_store":"kb"}]
    }))
    thought_summary_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"thought_summary",
      "content":{"data":"SGVsbG8=","mime_type":"image/png"}
    }))

    status_event.kind.interaction_status_update?.should be_true
    status_event.interaction_id.should eq("interaction-1")
    status_event.status.not_nil!.kind.requires_action?.should be_true
    status_event.event_id.should eq("event-1")
    stop_event.kind.content_stop?.should be_true
    stop_event.index.should eq(2)
    error_event.kind.error?.should be_true
    error_event.error.not_nil!.message.should eq("boom")
    mcp_delta.kind.mcp_server_tool_call?.should be_true
    mcp_delta.mcp_server_tool_call.not_nil!.server_name.should eq("github")
    file_search_delta.kind.file_search_result?.should be_true
    file_search_delta.file_search_result.not_nil!.result.not_nil!.first.title.should eq("Policy")
    thought_summary_delta.kind.thought_summary?.should be_true
    Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(thought_summary_delta).should be_nil
  end
end

describe Crig::Providers::Gemini::Interactions::InteractionsCompletionModel do
  it "creates and fetches interactions through the client" do
    requests = [] of {String, String}
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      requests << {context.request.path, body}
      context.response.status_code = 200
      context.response.content_type = "application/json"

      case context.request.path
      when "/v1beta/interactions"
        context.response.print(%({"id":"interaction-create","outputs":[{"type":"text","text":"created"}]}))
      when "/v1beta/interactions/interaction-create"
        context.response.print(%({"id":"interaction-create","status":"completed","outputs":[{"type":"text","text":"fetched"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"message":"not found"}))
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::InteractionsClient.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model("gemini-2.5-flash")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    created = model.create_interaction(request)
    fetched = model.get_interaction("interaction-create")

    created.id.should eq("interaction-create")
    fetched.is_completed.should be_true
    requests[0][0].should eq("/v1beta/interactions")
    requests[1][0].should eq("/v1beta/interactions/interaction-create")

    http_server.close
  end

  it "streams interaction events from request and by id" do
    seen_paths = [] of String
    http_server = HTTP::Server.new do |context|
      seen_paths << context.request.resource
      context.response.status_code = 200
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"event_type":"content.start","index":0,"content":{"type":"text","text":"Hello"}}

data: {"event_type":"content.delta","index":0,"delta":{"type":"function_call","name":"search","arguments":{"q":"rust"},"id":"call-1"}}

data: {"event_type":"interaction.complete","interaction":{"id":"interaction-1","outputs":[{"type":"text","text":"done"}],"usage":{"total_input_tokens":1,"total_output_tokens":2,"total_tokens":3}}}
SSE
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::InteractionsClient.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model("gemini-2.5-flash")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    request_events = model.stream_interaction_events(request)
    id_events = model.stream_interaction_events_by_id("interaction-1", "event-9")

    request_events.size.should eq(3)
    request_events[1].delta.not_nil!.kind.function_call?.should be_true
    id_events.last.interaction.not_nil!.id.should eq("interaction-1")
    seen_paths[0].should eq("/v1beta/interactions?alt=sse")
    seen_paths[1].should eq("/v1beta/interactions/interaction-1?stream=true&last_event_id=event-9&alt=sse")

    http_server.close
  end
end

describe Crig::Providers::Mira do
  it "deserializes raw messages into core messages" do
    assistant = Crig::Providers::Mira::RawMessage.from_json(%({"role":"assistant","content":"Hello there, how may I assist you today?"}))
    user = Crig::Providers::Mira::RawMessage.from_json(%({"role":"user","content":"What can you help me with?"}))

    assistant.to_core_message.should eq(Crig::Completion::Message.assistant("Hello there, how may I assist you today?"))
    user.to_core_message.should eq(Crig::Completion::Message.user("What can you help me with?"))
  end

  it "converts core message history into mira request messages" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .model("mira-default")
      .preamble("System as user")
      .build

    payload = Crig::Providers::Mira::MiraCompletionRequest.from_request("fallback-model", request).to_json_value

    payload["model"].as_s.should eq("mira-default")
    payload["messages"].as_a.map { |entry| {entry["role"].as_s, entry["content"].as_s} }.should eq(
      [{"user", "System as user"}, {"user", "Hello"}]
    )
  end

  it "converts structured completion responses into crig responses" do
    mira_response = Crig::Providers::Mira::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"resp_123",
      "object":"chat.completion",
      "created":1234567890,
      "model":"deepseek-r1",
      "choices":[{"message":{"role":"assistant","content":"Test response"},"finish_reason":"stop","index":0}],
      "usage":{"prompt_tokens":10,"total_tokens":20}
    })))

    completion_response = mira_response.to_crig_response
    completion_response.choice.first.should eq(Crig::Completion::AssistantContent.text("Test response"))
    completion_response.usage.input_tokens.should eq(10)
    completion_response.usage.output_tokens.should eq(10)
  end

  it "supports client initialization and builders" do
    client = Crig::Providers::Mira::Client.new("dummy-key")
    built = Crig::Providers::Mira::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    built.api_key.token.should eq("dummy-key")
  end

  it "executes sync and streaming mira completions" do
    seen = [] of {String, JSON::Any, String}
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      seen << {context.request.path, JSON.parse(body), context.request.headers["Accept"]? || ""}
      context.response.status_code = 200

      if context.request.headers["Accept"]? == "text/event-stream"
        context.response.content_type = "text/event-stream"
        context.response.print <<-SSE
data: {"id":"chatcmpl-stream","model":"mira-1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"}}]}

data: {"id":"chatcmpl-stream","model":"mira-1","choices":[{"index":0,"delta":{"content":" world"}}],"usage":{"prompt_tokens":4,"total_tokens":9}}

data: [DONE]
SSE
      else
        context.response.content_type = "application/json"
        context.response.print %({"id":"resp_1","object":"chat.completion","created":1,"model":"mira-1","choices":[{"message":{"role":"assistant","content":"Hello sync"},"finish_reason":"stop","index":0}],"usage":{"prompt_tokens":3,"total_tokens":7}})
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Mira::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model("mira-1")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    sync_response = model.completion(request)
    stream_response = model.stream(request)
    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    stream_response.each_item { |item| items << item }
    text_chunks = items.select(&.kind.text?).map { |item| item.text.not_nil!.text }

    sync_response.choice.first.should eq(Crig::Completion::AssistantContent.text("Hello sync"))
    text_chunks.should eq(["Hello", " world"])
    items.last.final.not_nil!.usage.not_nil!.output_tokens.should eq(5)
    seen[0][0].should eq("/v1/chat/completions")
    seen[0][1]["stream"].as_bool.should be_false
    seen[1][2].should eq("text/event-stream")
    seen[1][1]["stream"].as_bool.should be_true

    http_server.close
  end
end

describe Crig::Providers::Moonshot do
  it "supports client initialization and builders" do
    client = Crig::Providers::Moonshot::Client.new("dummy-key")
    built = Crig::Providers::Moonshot::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    built.api_key.token.should eq("dummy-key")
  end

  it "builds moonshot requests and rejects unsupported tool choice modes" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be concise")
      .tool(Crig::Completion::ToolDefinition.new("lookup", "Lookup", JSON.parse(%({"type":"object"}))))
      .tool_choice(Crig::Completion::ToolChoice.auto)
      .build

    payload = Crig::Providers::Moonshot::MoonshotCompletionRequest.from_request(
      Crig::Providers::Moonshot::KIMI_K2_5,
      request
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::Moonshot::KIMI_K2_5)
    payload["messages"].as_a.first["role"].as_s.should eq("system")
    payload["tools"].as_a.first["function"]["name"].as_s.should eq("lookup")
    payload["tool_choice"].as_s.should eq("auto")

    expect_raises(Crig::Completion::CompletionError, /Unsupported tool choice type/) do
      Crig::Providers::Moonshot::MoonshotCompletionRequest.from_request(
        Crig::Providers::Moonshot::KIMI_K2_5,
        Crig::Completion::Request::CompletionRequestBuilder
          .from_prompt("Hello")
          .tool_choice(Crig::Completion::ToolChoice.required)
          .build
      )
    end
  end

  it "executes sync and streaming moonshot completions" do
    seen = [] of {String, JSON::Any, String}
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      seen << {context.request.path, JSON.parse(body), context.request.headers["Accept"]? || ""}
      context.response.status_code = 200

      if context.request.headers["Accept"]? == "text/event-stream"
        context.response.content_type = "text/event-stream"
        context.response.print <<-SSE
data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1,"model":"kimi-k2.5","choices":[{"index":0,"delta":{"content":" moonshot"}}],"usage":{"prompt_tokens":3,"total_tokens":8}}

data: [DONE]
SSE
      else
        context.response.content_type = "application/json"
        context.response.print %({"id":"chatcmpl_1","object":"chat.completion","created":1,"model":"kimi-k2.5","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"Hello sync"}}],"usage":{"prompt_tokens":3,"total_tokens":7}})
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Moonshot::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::Moonshot::KIMI_K2_5)
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    sync_response = model.completion(request)
    stream_response = model.stream(request)
    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    stream_response.each_item { |item| items << item }

    sync_response.choice.first.should eq(Crig::Completion::AssistantContent.text("Hello sync"))
    items.select(&.kind.text?).map { |item| item.text.not_nil!.text }.should eq(["Hello", " moonshot"])
    items.last.final.not_nil!.usage.not_nil!.output_tokens.should eq(5)
    seen[0][0].should eq("/v1/chat/completions")
    seen[1][0].should eq("/v1/chat/completions")
    seen[1][1]["stream"].as_bool.should be_true
    seen[1][1]["stream_options"]["include_usage"].as_bool.should be_true

    http_server.close
  end
end

describe Crig::Providers::Xiaomi do
  it "supports client initialization and builders" do
    client = Crig::Providers::Xiaomi::Client.new("dummy-key")
    built = Crig::Providers::Xiaomi::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    built.api_key.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::Xiaomi::XIAOMI_MIMO_API_BASE_URL)
  end

  it "builds xiaomi requests and rejects specific tool choice mode" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be concise")
      .tool(Crig::Completion::ToolDefinition.new("lookup", "Lookup", JSON.parse(%({"type":"object"}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    payload = Crig::Providers::Xiaomi::XiaomiCompletionRequest.from_request(
      Crig::Providers::Xiaomi::MIMO_V2_PRO,
      request
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::Xiaomi::MIMO_V2_PRO)
    payload["messages"].as_a.first["role"].as_s.should eq("system")
    payload["tools"].as_a.first["function"]["name"].as_s.should eq("lookup")
    payload["tool_choice"].as_s.should eq("required")

    expect_raises(Crig::Completion::CompletionError, /Provider doesn't support only using specific tools/) do
      Crig::Providers::Xiaomi::XiaomiCompletionRequest.from_request(
        Crig::Providers::Xiaomi::MIMO_V2_PRO,
        Crig::Completion::Request::CompletionRequestBuilder
          .from_prompt("Hello")
          .tool_choice(Crig::Completion::ToolChoice.specific(["lookup"]))
          .build
      )
    end
  end

  it "executes sync and streaming xiaomi completions with api-key auth" do
    seen = [] of {String, JSON::Any, String, String?}
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      seen << {
        context.request.path,
        JSON.parse(body),
        context.request.headers["Accept"]? || "",
        context.request.headers["api-key"]?,
      }
      context.response.status_code = 200

      if context.request.headers["Accept"]? == "text/event-stream"
        context.response.content_type = "text/event-stream"
        context.response.print <<-SSE
data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1,"model":"mimo-v2-pro","choices":[{"index":0,"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1,"model":"mimo-v2-pro","choices":[{"index":0,"delta":{"content":" xiaomi"}}],"usage":{"prompt_tokens":3,"total_tokens":8}}

data: [DONE]
SSE
      else
        context.response.content_type = "application/json"
        context.response.print %({"id":"chatcmpl_1","object":"chat.completion","created":1,"model":"mimo-v2-pro","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"Hello sync"}}],"usage":{"prompt_tokens":3,"total_tokens":7}})
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Xiaomi::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::Xiaomi::MIMO_V2_PRO)
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    sync_response = model.completion(request)
    stream_response = model.stream(request)
    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    stream_response.each_item { |item| items << item }

    sync_response.choice.first.should eq(Crig::Completion::AssistantContent.text("Hello sync"))
    items.select(&.kind.text?).map { |item| item.text.not_nil!.text }.should eq(["Hello", " xiaomi"])
    items.last.final.not_nil!.usage.not_nil!.output_tokens.should eq(5)
    seen[0][0].should eq("/v1/chat/completions")
    seen[0][3].should eq("test-key")
    seen[1][0].should eq("/v1/chat/completions")
    seen[1][1]["stream"].as_bool.should be_true
    seen[1][1]["stream_options"]["include_usage"].as_bool.should be_true
    seen[1][3].should eq("test-key")

    http_server.close
  end
end

describe Crig::Providers::VoyageAI do
  it "supports client initialization and builders" do
    client = Crig::Providers::VoyageAI::Client.new("dummy-key")
    built = Crig::Providers::VoyageAI::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    built.api_key.token.should eq("dummy-key")
  end

  it "infers model dimensions" do
    Crig::Providers::VoyageAI.model_dimensions_from_identifier(Crig::Providers::VoyageAI::VOYAGE_CODE_2).should eq(1536)
    Crig::Providers::VoyageAI.model_dimensions_from_identifier(Crig::Providers::VoyageAI::VOYAGE_3_5).should eq(1024)
    Crig::Providers::VoyageAI.model_dimensions_from_identifier("unknown").should be_nil
  end

  it "executes voyage embeddings and validates response length" do
    seen = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      seen << JSON.parse(body)
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print %({
        "object":"list",
        "data":[
          {"object":"embedding","embedding":[0.1,0.2],"index":0},
          {"object":"embedding","embedding":[0.3,0.4],"index":1}
        ],
        "model":"voyage-3.5",
        "usage":{"prompt_tokens":4,"total_tokens":4}
      })
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::VoyageAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::VoyageAI::VOYAGE_3_5)
    embeddings = model.embed_texts(["alpha", "beta"])

    model.ndims.should eq(1024)
    embeddings.map(&.document).should eq(["alpha", "beta"])
    embeddings.map(&.vec).should eq([[0.1, 0.2], [0.3, 0.4]])
    seen.first["model"].as_s.should eq(Crig::Providers::VoyageAI::VOYAGE_3_5)
    seen.first["input"].as_a.map(&.as_s).should eq(["alpha", "beta"])

    http_server.close
  end
end

describe Crig::Providers::OpenAI::Chat::Streaming do
  it "deserializes a streaming function" do
    function = Crig::Providers::OpenAI::Chat::Streaming::Function.from_json(%({"name":"get_weather","arguments":"{\\"location\\":\\"Paris\\"}"}))

    function.name.should eq("get_weather")
    function.arguments.should eq(%({"location":"Paris"}))
  end

  it "deserializes a streaming tool call" do
    tool_call = Crig::Providers::OpenAI::Chat::Streaming::ToolCall.from_json(%({
      "index":0,
      "id":"call_abc123",
      "function":{"name":"get_weather","arguments":"{\\"city\\":\\"London\\"}"}
    }))

    tool_call.index.should eq(0)
    tool_call.id.should eq("call_abc123")
    tool_call.function.name.should eq("get_weather")
  end

  it "deserializes a partial streaming tool call" do
    tool_call = Crig::Providers::OpenAI::Chat::Streaming::ToolCall.from_json(%({
      "index":0,
      "id":null,
      "function":{"name":null,"arguments":"Paris"}
    }))

    tool_call.index.should eq(0)
    tool_call.id.should be_nil
    tool_call.function.name.should be_nil
    tool_call.function.arguments.should eq("Paris")
  end

  it "deserializes a streaming delta with tool calls" do
    delta = Crig::Providers::OpenAI::Chat::Streaming::Delta.from_json_value(JSON.parse(%({
      "content":null,
      "tool_calls":[{"index":0,"id":"call_xyz","function":{"name":"search","arguments":""}}]
    })))

    delta.content.should be_nil
    delta.tool_calls.size.should eq(1)
    delta.tool_calls.first.id.should eq("call_xyz")
  end

  it "deserializes a streaming chunk" do
    chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(JSON.parse(%({
      "choices":[{"delta":{"content":"Hello","tool_calls":[]}}],
      "usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}
    })))

    chunk.choices.size.should eq(1)
    chunk.choices.first.delta.content.should eq("Hello")
    chunk.usage.should_not be_nil
  end

  it "deserializes multiple tool call deltas across chunks" do
    start_chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(JSON.parse(%({
      "choices":[{"delta":{"content":null,"tool_calls":[{"index":0,"id":"call_123","function":{"name":"get_weather","arguments":""}}]}}],
      "usage":null
    })))
    chunk1 = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(JSON.parse(%({
      "choices":[{"delta":{"content":null,"tool_calls":[{"index":0,"id":null,"function":{"name":null,"arguments":"{\\"loc"}}]}}],
      "usage":null
    })))
    chunk2 = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(JSON.parse(%({
      "choices":[{"delta":{"content":null,"tool_calls":[{"index":0,"id":null,"function":{"name":null,"arguments":"ation\\":\\"NYC\\"}"}}]}}],
      "usage":null
    })))

    start_chunk.choices.first.delta.tool_calls.first.function.name.should eq("get_weather")
    chunk1.choices.first.delta.tool_calls.first.function.arguments.should eq("{\"loc")
    chunk2.choices.first.delta.tool_calls.first.function.arguments.should eq("ation\":\"NYC\"}")
  end

  it "parses finish reasons including unknown values" do
    Crig::Providers::OpenAI::Chat::Streaming::FinishReason.from_string("tool_calls").tool_calls?.should be_true
    other = Crig::Providers::OpenAI::Chat::Streaming::FinishReason.from_string("function_call")

    other.kind.other?.should be_true
    other.value.should eq("function_call")
  end
end

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

describe Crig::Loaders::FileLoader do
  it "loads files from a glob and reads their contents" do
    dir = File.join(Dir.tempdir, "crig-file-loader-#{Random::Secure.hex(8)}")
    Dir.mkdir(dir)

    begin
      File.write(File.join(dir, "foo.txt"), "foo")
      File.write(File.join(dir, "bar.txt"), "bar")

      glob = File.join(dir, "*.txt")
      loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_glob(glob)
      actual = loader
        .ignore_errors
        .read
        .ignore_errors
        .into_iter

      contents = [] of String
      while item = actual.next
        contents << item.as(String)
      end

      contents.sort!.should eq(["bar", "foo"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "loads text from in-memory bytes and read_with_path uses <memory>" do
    bytes = [
      "foo".bytes.to_a,
      "bar".bytes.to_a,
    ]
    loader = Crig::Loaders::FileLoader(Array(UInt8)).from_bytes_multi(bytes)

    contents = [] of String
    loader.read.ignore_errors.each do |item|
      contents << item.as(String)
    end

    with_path = Crig::Loaders::FileLoader(Array(UInt8)).from_bytes_multi(bytes)
      .read_with_path
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, String)))

    contents.sort!.should eq(["bar", "foo"])
    with_path.map(&.[0]).uniq.should eq(["<memory>"])
    with_path.map(&.[1]).sort!.should eq(["bar", "foo"])
  end

  it "loads only direct files from a directory" do
    dir = File.join(Dir.tempdir, "crig-file-loader-dir-#{Random::Secure.hex(8)}")
    Dir.mkdir(dir)

    begin
      File.write(File.join(dir, "alpha.txt"), "alpha")
      Dir.mkdir(File.join(dir, "nested"))
      File.write(File.join(dir, "nested", "beta.txt"), "beta")

      loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_dir(dir)
      paths = loader.ignore_errors.to_a.map(&.as(String))

      paths.size.should eq(1)
      File.basename(paths.first).should eq("alpha.txt")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe Crig::Loaders::Epub::RawTextProcessor do
  it "returns the input text unchanged" do
    Crig::Loaders::Epub::RawTextProcessor.process("hello <b>world</b>").should eq("hello <b>world</b>")
  end
end

describe Crig::Loaders::Epub::StripXmlProcessor do
  it "strips XML tags and joins adjacent text nodes with spaces" do
    xml = "<chapter><p>Hello</p><p>world</p><![CDATA[!]]></chapter>"

    Crig::Loaders::Epub::StripXmlProcessor.process(xml).should eq("Helloworld!")
  end

  it "raises a wrapped XML processing error for malformed XML" do
    expect_raises(Crig::Loaders::Epub::XmlProcessingError, /XML parsing error:/) do
      Crig::Loaders::Epub::StripXmlProcessor.process("<chapter><p>oops</chapter>")
    end
  end
end

describe Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor) do
  it "loads epub files by chapter with errors preserved" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/rig/rig-core/tests/data/*.epub")
    actual = loader
      .load_with_path
      .ignore_errors
      .by_chapter
      .to_a
      .map(&.as(Tuple(String, Array(String | Crig::Loaders::Epub::EpubLoaderError))))

    actual.size.should eq(1)
    path, chapters = actual.first
    path.should eq("vendor/rig/rig/rig-core/tests/data/dummy.epub")
    chapters.size.should eq(3)
    chapters.all? { |chapter| chapter.is_a?(String) }.should be_true
  end

  it "reads a single epub file into concatenated content" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/rig/rig-core/tests/data/*.epub")
    actual = loader
      .read
      .ignore_errors
      .to_a

    actual.size.should eq(1)
    actual.first.should be_a(String)
  end

  it "reads a single epub file with its path" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/rig/rig-core/tests/data/*.epub")
    actual = loader
      .read_with_path
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, String)))

    actual.size.should eq(1)
    actual.first[0].should eq("vendor/rig/rig/rig-core/tests/data/dummy.epub")
  end
end

describe Crig::Loaders::PdfFileLoader do
  it "loads pdf files by page with paths preserved" do
    loader = Crig::Loaders::PdfFileLoader(String | Crig::Loaders::PdfLoaderError)
      .with_glob("vendor/rig/rig/rig-core/tests/data/*.pdf")
    actual = loader
      .load_with_path
      .ignore_errors
      .by_page
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, Array(Tuple(Int32, String)))))

    actual.sort_by!(&.[0])
    actual.should eq([
      {
        "vendor/rig/rig/rig-core/tests/data/dummy.pdf",
        [{0, "Test\nPDF\nDocument\n"}],
      },
      {
        "vendor/rig/rig/rig-core/tests/data/pages.pdf",
        [
          {0, "Page\n1\n"},
          {1, "Page\n2\n"},
          {2, "Page\n3\n"},
        ],
      },
    ])
  end

  it "loads pdf content from in-memory bytes by page" do
    dummy_bytes = File.read("vendor/rig/rig/rig-core/tests/data/dummy.pdf").to_slice.to_a
    pages_bytes = File.read("vendor/rig/rig/rig-core/tests/data/pages.pdf").to_slice.to_a

    actual = Crig::Loaders::PdfFileLoader(Array(UInt8))
      .from_bytes_multi([dummy_bytes, pages_bytes])
      .load
      .ignore_errors
      .by_page
      .ignore_errors
      .to_a

    actual.should eq([
      "Test\nPDF\nDocument\n",
      "Page\n1\n",
      "Page\n2\n",
      "Page\n3\n",
    ])
  end
end

describe Crig::Examples::GeminiExtractor, tags: %w[examples gemini] do
  it "serializes the nested job wrapper and person payload" do
    person = Crig::Examples::GeminiExtractor::Person.new(
      "John",
      "Doe",
      Crig::Examples::GeminiExtractor::FooString.new("software engineer")
    )

    parsed = JSON.parse(person.to_json)
    parsed["first_name"].as_s.should eq("John")
    parsed["last_name"].as_s.should eq("Doe")
    parsed["job"]["string"].as_s.should eq("software engineer")
  end

  it "builds a gemini extractor with generation-config additional params" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"
      require "./examples/gemini_extractor"

      client = Crig::Providers::Gemini::Client.new("gemini-key", "https://example.test")
      builder = Crig::Examples::GeminiExtractor.build_extractor(
        client,
        generation_config: Crig::Providers::Gemini::GenerationConfig.new(max_output_tokens: 64_i64)
      )
      params = builder.agent_builder.additional_params_value || raise "missing params"

      puts(JSON.build do |json|
        json.object do
          json.field "model", builder.agent_builder.model.model
          json.field "max_output_tokens", params["generationConfig"]["maxOutputTokens"].as_i
        end
      end)
    CRYSTAL

    result["model"].as_s.should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    result["max_output_tokens"].as_i.should eq(64)
  end
end

describe Crig::Examples::MultiExtract, tags: %w[examples multi_extract] do
  it "serializes extracted names, topics, and sentiment payloads" do
    names = JSON.parse(Crig::Examples::MultiExtract::Names.new(["Alice", "Paris"]).to_json)
    topics = JSON.parse(Crig::Examples::MultiExtract::Topics.new(["travel", "planning"]).to_json)
    sentiment = JSON.parse(Crig::Examples::MultiExtract::Sentiment.new(0.75, 0.9).to_json)

    names["names"].as_a.map(&.as_s).should eq(["Alice", "Paris"])
    topics["topics"].as_a.map(&.as_s).should eq(["travel", "planning"])
    sentiment["sentiment"].as_f.should eq(0.75)
    sentiment["confidence"].as_f.should eq(0.9)
  end

  it "builds extractor helpers with the upstream example preambles" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"
      require "./examples/multi_extract"

      client = Crig::Providers::OpenAI::Client.new("openai-key", "https://example.test")

      names = Crig::Examples::MultiExtract.names_extractor(client)
      topics = Crig::Examples::MultiExtract.topics_extractor(client)
      sentiment = Crig::Examples::MultiExtract.sentiment_extractor(client)

      puts(JSON.build do |json|
        json.object do
          json.field "names_preamble", names.agent_builder.preamble_value
          json.field "topics_preamble", topics.agent_builder.preamble_value
          json.field "sentiment_preamble", sentiment.agent_builder.preamble_value
        end
      end)
    CRYSTAL

    result["names_preamble"].as_s.ends_with?(
      "=============== ADDITIONAL INSTRUCTIONS ===============\nExtract names (e.g.: of people, places) from the given text."
    ).should be_true
    result["topics_preamble"].as_s.ends_with?(
      "=============== ADDITIONAL INSTRUCTIONS ===============\nExtract topics from the given text."
    ).should be_true
    result["sentiment_preamble"].as_s.ends_with?(
      "=============== ADDITIONAL INSTRUCTIONS ===============\nExtract sentiment (and how confident you are of the sentiment) from the given text."
    ).should be_true
  end

  it "formats extracted analysis output like the upstream closure" do
    result = Crig::Examples::MultiExtract.format_analysis(
      Crig::Examples::MultiExtract::Names.new(["Putin"]),
      Crig::Examples::MultiExtract::Topics.new(["politics"]),
      Crig::Examples::MultiExtract::Sentiment.new(-1.0, 0.8)
    )

    result.should eq("Extracted names: Putin\nExtracted topics: politics\nExtracted sentiment: -1.0")
  end
end

describe Crig::Examples::SimpleModel, tags: %w[examples simple_model] do
  it "builds the upstream simple-model agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::SimpleModel.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4)
  end

  it "runs prompts through a provided agent" do
    response = Crig::Examples::SimpleModel.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build,
      "Who are you?"
    )

    response.should eq("completion:gpt-4o")
  end
end

describe Crig::Examples::Agent, tags: %w[examples agent] do
  it "builds the upstream comedian agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::Agent.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::Agent::COMEDIAN_PREAMBLE)
  end

  it "runs the agent example prompt through a provided agent" do
    response = Crig::Examples::Agent.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    )

    response.should eq("completion:gpt-4o")
  end
end

describe Crig::Examples::AgentWithContext, tags: %w[examples agent_with_context] do
  it "builds the upstream context-stacking agent helper" do
    client = Crig::Providers::Cohere::Client.new("test-key")
    agent = Crig::Examples::AgentWithContext.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
    agent.static_context.map(&.text).should eq(Crig::Examples::AgentWithContext::CONTEXTS)
  end

  it "runs prompts through a provided context agent" do
    response = Crig::Examples::AgentWithContext.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("command-r"))
        .context("Definition of a *glarb-glarb*: ...")
        .build
    )

    response.should eq("completion:command-r")
  end
end

describe Crig::Examples::AgentWithDefaultMaxTurns, tags: %w[examples agent_with_default_max_turns] do
  it "builds the upstream arithmetic tool agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AgentWithDefaultMaxTurns.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::AgentWithDefaultMaxTurns::PREAMBLE)
    agent.default_max_turns.should eq(20)
    agent.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "runs prompts through the provided arithmetic agent" do
    response = Crig::Examples::AgentWithDefaultMaxTurns.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-3-5-sonnet"))
        .default_max_turns(20)
        .build,
      "Calculate 5 - 2 = ?. Describe the result to me."
    )

    response.should eq("completion:claude-3-5-sonnet")
  end
end

describe Crig::Examples::AgentWithTools, tags: %w[examples agent_with_tools] do
  it "builds the upstream tools agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::AgentWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "runs prompts through the provided tools agent" do
    response = Crig::Examples::AgentWithTools.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o"))
        .tools(Crig::Examples::AgentWithTools.tools)
        .max_tokens(1024)
        .build
    )

    response.should eq("completion:gpt-4o")
  end
end

describe Crig::Examples::AgentWithAgentTool, tags: %w[examples agent_with_agent_tool] do
  it "builds the upstream nested calculator agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithAgentTool.build_calculator_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::AgentWithAgentTool::CALCULATOR_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "builds the upstream agent-using-agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithAgentTool.build_agent_using_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::AgentWithAgentTool::ASSISTANT_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq([Crig::AGENT_TOOL_NAME])
  end

  it "runs prompts through the provided agent-using-agent helper" do
    Crig::Examples::AgentWithAgentTool.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("outer-agent")).build
    ).should eq("completion:outer-agent")
  end
end

describe Crig::Examples::AgentWithGroq, tags: %w[examples agent_with_groq] do
  it "builds the upstream groq comedian agent helper" do
    client = Crig::Providers::Groq::Client.new("test-key")
    agent = Crig::Examples::AgentWithGroq.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Groq::DEEPSEEK_R1_DISTILL_LLAMA_70B)
    agent.preamble.should eq(Crig::Examples::AgentWithGroq::PREAMBLE)
  end

  it "runs the groq example prompt through a provided agent" do
    Crig::Examples::AgentWithGroq.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("groq-model")).build
    ).should eq("completion:groq-model")
  end
end

describe Crig::Examples::AgentWithHyperbolic, tags: %w[examples agent_with_hyperbolic] do
  it "builds the upstream hyperbolic comedian agent helper" do
    client = Crig::Providers::Hyperbolic::Client.new("test-key")
    agent = Crig::Examples::AgentWithHyperbolic.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Hyperbolic::DEEPSEEK_R1)
    agent.preamble.should eq(Crig::Examples::AgentWithHyperbolic::PREAMBLE)
  end

  it "runs the hyperbolic example prompt through a provided agent" do
    Crig::Examples::AgentWithHyperbolic.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("hyperbolic-model")).build
    ).should eq("completion:hyperbolic-model")
  end
end

describe Crig::Examples::AgentWithOpenRouter, tags: %w[examples agent_with_openrouter] do
  it "builds the upstream openrouter comedian agent helper" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    agent = Crig::Examples::AgentWithOpenRouter.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Gemini::GEMINI_2_5_PRO_EXP_03_25)
    agent.preamble.should eq(Crig::Examples::AgentWithOpenRouter::PREAMBLE)
  end

  it "runs the openrouter example prompt through a provided agent" do
    Crig::Examples::AgentWithOpenRouter.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("openrouter-model")).build
    ).should eq("completion:openrouter-model")
  end
end

describe Crig::Examples::AgentWithGaladriel, tags: %w[examples agent_with_galadriel] do
  it "builds the upstream galadriel comedian agent helper" do
    client = Crig::Providers::Galadriel::Client.new("test-key")
    agent = Crig::Examples::AgentWithGaladriel.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Galadriel::GPT_4O)
    agent.preamble.should eq(Crig::Examples::AgentWithGaladriel::PREAMBLE)
  end

  it "runs the galadriel example prompt through a provided agent" do
    Crig::Examples::AgentWithGaladriel.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("galadriel-model")).build
    ).should eq("completion:galadriel-model")
  end
end

describe Crig::Examples::AgentWithGrok, tags: %w[examples agent_with_grok] do
  it "builds the upstream grok basic agent helper" do
    client = Crig::Providers::XAI::Client.new("test-key")
    agent = Crig::Examples::AgentWithGrok.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::XAI::GROK_3_MINI)
    agent.preamble.should eq(Crig::Examples::AgentWithGrok::BASIC_PREAMBLE)
    agent.default_max_turns.should eq(32)
  end

  it "builds the upstream grok tools agent helper" do
    client = Crig::Providers::XAI::Client.new("test-key")
    agent = Crig::Examples::AgentWithGrok.build_tools_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithGrok::TOOLS_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.default_max_turns.should eq(32)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "builds the upstream grok loader-backed agent helper" do
    client = Crig::Providers::XAI::Client.new("test-key")
    agent = Crig::Examples::AgentWithGrok.build_loaders_agent(
      client,
      glob: "vendor/rig/rig/rig-core/examples/agent.rs"
    )

    agent.static_context.size.should eq(1)
    agent.static_context.first.text.includes?("Rust Example").should be_true
  end

  it "builds the upstream grok context agent helper" do
    client = Crig::Providers::XAI::Client.new("test-key")
    agent = Crig::Examples::AgentWithGrok.build_context_agent(client)

    agent.static_context.map(&.text).should eq(Crig::Examples::AgentWithContext::CONTEXTS)
    agent.default_max_turns.should eq(32)
  end
end

describe Crig::Examples::AgentWithMoonshot, tags: %w[examples agent_with_moonshot] do
  it "builds the upstream basic moonshot agent helper" do
    client = Crig::Providers::Moonshot::Client.new("test-key")
    agent = Crig::Examples::AgentWithMoonshot.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::Moonshot::MOONSHOT_CHAT)
    agent.preamble.should eq(Crig::Examples::AgentWithMoonshot::BASIC_PREAMBLE)
    agent.temperature.should eq(0.5)
    agent.max_tokens.should eq(1024_i64)
  end

  it "builds the upstream moonshot context agent helper" do
    client = Crig::Providers::Moonshot::Client.new("test-key")
    agent = Crig::Examples::AgentWithMoonshot.build_context_agent(client)

    agent.model.model.should eq(Crig::Providers::Moonshot::MOONSHOT_CHAT)
    agent.preamble.should eq(Crig::Examples::AgentWithMoonshot::CONTEXT_PREAMBLE)
  end

  it "runs the moonshot example prompt through a provided agent" do
    Crig::Examples::AgentWithMoonshot.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("moonshot-model")).build,
      "Entertain me!"
    ).should eq("completion:moonshot-model")
  end
end

describe Crig::Examples::AgentWithOllama, tags: %w[examples agent_with_ollama] do
  it "builds the upstream ollama client helper without an api key" do
    client = Crig::Examples::AgentWithOllama.build_client("http://127.0.0.1:11434")

    client.api_key.should eq(Crig::Nothing.new)
    client.base_url.should eq("http://127.0.0.1:11434")
  end

  it "builds the upstream ollama comedian agent helper" do
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new)
    agent = Crig::Examples::AgentWithOllama.build_agent(client)

    agent.model.model.should eq("qwen2.5:14b")
    agent.preamble.should eq(Crig::Examples::AgentWithOllama::PREAMBLE)
  end

  it "runs the ollama example prompt through a provided agent" do
    Crig::Examples::AgentWithOllama.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("qwen2.5:14b")).build
    ).should eq("completion:qwen2.5:14b")
  end
end

describe Crig::Examples::AgentStreamChat, tags: %w[examples agent_stream_chat] do
  it "builds the upstream streaming chat agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentStreamChat.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4)
    agent.preamble.should eq(Crig::Examples::AgentStreamChat::PREAMBLE)
  end

  it "streams chat with the upstream default history" do
    response = Crig::Examples::AgentStreamChat.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4")).build
    )
    final_response = response.response.not_nil!

    final_response.response.should eq("chunk:gpt-4")
    final_response.history.not_nil!.first.rag_text.should eq("Tell me a joke!")
  end
end

describe Crig::Examples::OpenAIStreaming, tags: %w[examples openai_streaming] do
  it "builds the upstream openai streaming agent helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::OpenAIStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams openai prompts through a provided agent" do
    model = FakeCompletionClientModel.new("gpt-4o-mini")
    response = Crig::Examples::OpenAIStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::OpenAIStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:gpt-4o-mini")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OpenAIStreaming::PROMPT)
  end
end

describe Crig::Examples::OllamaStreaming, tags: %w[examples ollama_streaming] do
  it "builds the upstream ollama streaming client and agent helpers" do
    client = Crig::Examples::OllamaStreaming.build_client("http://127.0.0.1:11434")
    agent = Crig::Examples::OllamaStreaming.build_agent(client)

    client.base_url.should eq("http://127.0.0.1:11434")
    agent.model.model.should eq(Crig::Examples::OllamaStreaming::MODEL)
    agent.preamble.should eq(Crig::Examples::OllamaStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams ollama prompts through a provided agent" do
    model = FakeCompletionClientModel.new("llama3.2")
    response = Crig::Examples::OllamaStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::OllamaStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:llama3.2")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OllamaStreaming::PROMPT)
  end
end

describe Crig::Examples::AgentWithDeepSeek, tags: %w[examples agent_with_deepseek] do
  it "builds the upstream deepseek basic agent helper" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    agent = Crig::Examples::AgentWithDeepSeek.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
    agent.preamble.should eq(Crig::Examples::AgentWithDeepSeek::BASIC_PREAMBLE)
  end

  it "builds the upstream deepseek calculator agent helper" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    agent = Crig::Examples::AgentWithDeepSeek.build_calculator_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithDeepSeek::CALCULATOR_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "runs the deepseek example prompt through a provided agent" do
    Crig::Examples::AgentWithDeepSeek.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("deepseek-chat")).build,
      "Tell me a joke"
    ).should eq("completion:deepseek-chat")
  end
end

describe Crig::Examples::AgentWithTogether, tags: %w[examples agent_with_together] do
  it "builds the upstream together basic agent helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    agent = Crig::Examples::AgentWithTogether.build_basic_agent(client)

    agent.model.model.should eq(Crig::Examples::AgentWithTogether.model_name)
    agent.preamble.should eq(Crig::Examples::AgentWithTogether::BASIC_PREAMBLE)
  end

  it "builds the upstream together tools agent helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    agent = Crig::Examples::AgentWithTogether.build_tools_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithTogether::TOOLS_PREAMBLE)
    agent.static_tools.map(&.name).should eq(["add"])
  end

  it "builds the upstream together context agent helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    agent = Crig::Examples::AgentWithTogether.build_context_agent(client)

    agent.static_context.map(&.text).should eq(Crig::Examples::AgentWithContext::CONTEXTS)
  end

  it "runs the together example prompt through a provided agent" do
    Crig::Examples::AgentWithTogether.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("together-model")).build,
      "Entertain me!"
    ).should eq("completion:together-model")
  end
end

describe Crig::Examples::AnthropicAgent, tags: %w[examples anthropic_agent] do
  it "builds the upstream anthropic agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicAgent.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::AnthropicAgent::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "runs the anthropic example prompt through a provided agent" do
    Crig::Examples::AnthropicAgent.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-model")).build
    ).should eq("completion:claude-model")
  end
end

describe Crig::Examples::AnthropicStreaming, tags: %w[examples anthropic_streaming] do
  it "builds the upstream anthropic streaming agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_4_SONNET)
    agent.preamble.should eq(Crig::Examples::AnthropicStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams anthropic prompts through a provided agent" do
    model = FakeCompletionClientModel.new("claude-stream")
    response = Crig::Examples::AnthropicStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::AnthropicStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:claude-stream")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::AnthropicStreaming::PROMPT)
  end
end

describe Crig::Examples::AnthropicStreamingWithTools, tags: %w[examples anthropic_streaming_with_tools] do
  it "builds the upstream anthropic streaming-with-tools agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_4_SONNET)
    agent.preamble.should eq(Crig::Examples::AnthropicStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams anthropic tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("claude-4-sonnet")
    response = Crig::Examples::AnthropicStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::AnthropicStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:claude-4-sonnet")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::AnthropicStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::CohereStreaming, tags: %w[examples cohere_streaming] do
  it "builds the upstream cohere streaming agent helper" do
    client = Crig::Providers::Cohere::Client.new("test-key")
    agent = Crig::Examples::CohereStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Cohere::COMMAND)
    agent.preamble.should eq(Crig::Examples::CohereStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams cohere prompts through a provided agent" do
    model = FakeCompletionClientModel.new("command")
    response = Crig::Examples::CohereStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::CohereStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:command")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::CohereStreaming::PROMPT)
  end
end

describe Crig::Examples::CohereStreamingWithTools, tags: %w[examples cohere_streaming_with_tools] do
  it "builds the upstream cohere streaming-with-tools agent helper" do
    client = Crig::Providers::Cohere::Client.new("test-key")
    agent = Crig::Examples::CohereStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
    agent.preamble.should eq(Crig::Examples::CohereStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams cohere tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("command-r")
    response = Crig::Examples::CohereStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::CohereStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:command-r")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::CohereStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::DeepSeekStreaming, tags: %w[examples deepseek_streaming] do
  it "builds the upstream deepseek streaming basic agent helper" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    agent = Crig::Examples::DeepSeekStreaming.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
    agent.preamble.should eq(Crig::Examples::DeepSeekStreaming::BASIC_PREAMBLE)
  end

  it "builds the upstream deepseek streaming calculator agent helper" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    agent = Crig::Examples::DeepSeekStreaming.build_calculator_agent(client)

    agent.preamble.should eq(Crig::Examples::DeepSeekStreaming::CALCULATOR_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams deepseek prompt requests through a provided agent" do
    model = FakeCompletionClientModel.new("deepseek-chat")
    response = Crig::Examples::DeepSeekStreaming.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::DeepSeekStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:deepseek-chat")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::DeepSeekStreaming::PROMPT)
  end

  it "streams deepseek chat requests through a provided calculator agent" do
    model = FakeCompletionClientModel.new("deepseek-chat")
    response = Crig::Examples::DeepSeekStreaming.run_chat(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::DeepSeekStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:deepseek-chat")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::DeepSeekStreaming::CALCULATOR_PROMPT)
  end
end

describe Crig::Examples::GeminiStreaming, tags: %w[examples gemini_streaming] do
  it "builds the upstream gemini streaming agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::GeminiStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    agent.preamble.should eq(Crig::Examples::GeminiStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
    params = agent.additional_params.not_nil!
    params["generationConfig"]["thinkingConfig"]["includeThoughts"].as_bool.should be_true
    params["generationConfig"]["thinkingConfig"]["thinkingBudget"].as_i.should eq(2048)
  end

  it "streams gemini prompts through a provided agent" do
    model = FakeCompletionClientModel.new("gemini-2.0-flash")
    response = Crig::Examples::GeminiStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::GeminiStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:gemini-2.0-flash")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::GeminiStreaming::PROMPT)
  end
end

describe Crig::Examples::GeminiStreamingWithTools, tags: %w[examples gemini_streaming_with_tools] do
  it "builds the upstream gemini streaming-with-tools agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::GeminiStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Gemini::GEMINI_2_5_FLASH)
    agent.preamble.should eq(Crig::Examples::GeminiStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
    agent.additional_params.not_nil!["generationConfig"].as_h.should eq({} of String => JSON::Any)
  end

  it "streams gemini tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("gemini-2.5-flash")
    response = Crig::Examples::GeminiStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::GeminiStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:gemini-2.5-flash")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::GeminiStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::GeminiAgent, tags: %w[examples gemini_agent] do
  it "builds the upstream gemini agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::GeminiAgent.build_agent(client)

    agent.model.model.should eq(Crig::Examples::GeminiAgent::MODEL)
    agent.preamble.should eq(Crig::Examples::GeminiAgent::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "runs the gemini example prompt through a provided agent" do
    Crig::Examples::GeminiAgent.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gemini-2.5-flash")).build
    ).should eq("completion:gemini-2.5-flash")
  end
end

describe Crig::Examples::GeminiStructuredOutput, tags: %w[examples gemini_structured_output] do
  it "builds the upstream gemini structured-output agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::GeminiStructuredOutput.build_agent(client)

    agent.model.model.should eq(Crig::Examples::GeminiStructuredOutput::MODEL)
    agent.preamble.should eq(Crig::Examples::GeminiStructuredOutput::PREAMBLE)
    agent.output_schema.not_nil!["title"].as_s.should eq("Crig::Examples::GeminiStructuredOutput::RecipeInfo")
  end

  it "parses structured gemini recipe json" do
    raw = %({"name":"Spaghetti Carbonara","cuisine":"Italian","timing":{"prep_minutes":10,"cook_minutes":15,"total_minutes":25},"ingredients":[{"name":"Spaghetti","quantity":"200g","optional":false}],"steps":[{"number":1,"instruction":"Boil pasta.","duration_minutes":10}],"nutrition":{"servings":2,"calories":650,"protein_g":24.5,"fat_g":22.0,"carbs_g":78.0},"difficulty":"Medium"})

    recipe = Crig::Examples::GeminiStructuredOutput.parse_recipe(raw)

    recipe.name.should eq("Spaghetti Carbonara")
    recipe.difficulty.should eq(Crig::Examples::GeminiStructuredOutput::Difficulty::Medium)
    recipe.ingredients.first.name.should eq("Spaghetti")
  end
end

describe Crig::Examples::GroqStreamingReasoning, tags: %w[examples groq_streaming_reasoning] do
  it "builds the upstream groq reasoning streaming agent helper" do
    client = Crig::Providers::Groq::Client.new("test-key")
    agent = Crig::Examples::GroqStreamingReasoning.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Groq::DEEPSEEK_R1_DISTILL_LLAMA_70B)
    agent.preamble.should eq(Crig::Examples::GroqStreamingReasoning::PREAMBLE)
    agent.additional_params.should eq(Crig::Examples::GroqStreamingReasoning.additional_params)
  end

  it "streams groq reasoning prompts through a provided agent" do
    model = FakeCompletionClientModel.new("deepseek-r1-distill")
    response = Crig::Examples::GroqStreamingReasoning.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::GroqStreamingReasoning.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:deepseek-r1-distill")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::GroqStreamingReasoning::PROMPT)
  end
end

describe Crig::Examples::HuggingFaceImageGeneration, tags: %w[examples huggingface_image_generation] do
  it "builds the upstream huggingface image generation model helper" do
    client = Crig::Providers::HuggingFace::Client.new("test-key")
    model = Crig::Examples::HuggingFaceImageGeneration.build_model(client)

    model.model.should eq(Crig::Examples::HuggingFaceImageGeneration::MODEL)
  end

  it "builds and sends the upstream huggingface image generation request helper" do
    model = FakeImageGenerationClientModel.new("stabilityai/stable-diffusion-3-medium-diffusers")
    response = Crig::Examples::HuggingFaceImageGeneration.generate(model)

    response.image.should eq(Bytes[9_u8, 10_u8])
    model.last_request.not_nil!.prompt.should eq(Crig::Examples::HuggingFaceImageGeneration::DEFAULT_PROMPT)
    model.last_request.not_nil!.width.should eq(1024)
    model.last_request.not_nil!.height.should eq(1024)
  end

  it "writes huggingface generated image bytes to an io" do
    io = IO::Memory.new
    response = Crig::ImageGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-image")

    Crig::Examples::HuggingFaceImageGeneration.write_image(response, io)

    io.to_slice.should eq(Bytes[1_u8, 2_u8, 3_u8])
  end
end

describe Crig::Examples::HuggingFaceStreaming, tags: %w[examples huggingface_streaming] do
  it "builds the upstream huggingface inference streaming agent helper" do
    client = Crig::Providers::HuggingFace::Client.new("test-key")
    agent = Crig::Examples::HuggingFaceStreaming.build_hf_agent(client)

    agent.model.model.should eq(Crig::Examples::HuggingFaceStreaming::HF_MODEL)
    agent.preamble.should eq(Crig::Examples::HuggingFaceStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "builds the upstream huggingface together client helper" do
    client = Crig::Examples::HuggingFaceStreaming.build_together_client("test-key")

    client.api_key.token.should eq("test-key")
    client.subprovider.kind.together?.should be_true
  end

  it "builds the upstream huggingface together streaming agent helper" do
    client = Crig::Providers::HuggingFace::Client.new("test-key", subprovider: Crig::Providers::HuggingFace::SubProvider.together)
    agent = Crig::Examples::HuggingFaceStreaming.build_together_agent(client)

    agent.model.model.should eq(Crig::Examples::HuggingFaceStreaming::TOGETHER_MODEL)
    agent.preamble.should eq(Crig::Examples::HuggingFaceStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams huggingface prompts through a provided agent" do
    model = FakeCompletionClientModel.new("llama-3.1")
    response = Crig::Examples::HuggingFaceStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::HuggingFaceStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.response.should eq("chunk:llama-3.1")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::HuggingFaceStreaming::PROMPT)
  end
end

describe Crig::Examples::GeminiEmbeddings, tags: %w[examples gemini_embeddings] do
  it "builds the upstream gemini embeddings builder helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    builder = Crig::Examples::GeminiEmbeddings.build_embeddings(client)

    builder.model.model.should eq(Crig::Examples::GeminiEmbeddings::MODEL)
    builder.documents.size.should eq(2)
    builder.documents.map { |entry| entry[0].message }.should eq(["Hello, world!", "Goodbye, world!"])
  end

  it "embeds the upstream gemini documents through a provided embeddings client" do
    builder = Crig::Examples::GeminiEmbeddings.build_embeddings(FakeEmbeddingsClient.new)
    results = builder.build

    results.map { |entry| entry[1].first.document }.should eq(
      [
        "gemini-embedding-001:Hello, world!",
        "gemini-embedding-001:Goodbye, world!",
      ]
    )
  end
end

describe Crig::Examples::AnthropicStructuredOutput, tags: %w[examples anthropic_structured_output] do
  it "builds the upstream anthropic structured-output agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicStructuredOutput.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_4_SONNET)
    agent.preamble.should eq(Crig::Examples::AnthropicStructuredOutput::PREAMBLE)
    agent.output_schema.not_nil!["title"].as_s.should eq("Crig::Examples::AnthropicStructuredOutput::BookReview")
  end

  it "parses structured anthropic review json" do
    raw = %({"title":"1984","author":{"name":"George Orwell","nationality":"British","other_works":["Animal Farm"]},"rating":5,"summary":"A classic dystopian novel.","themes":[{"name":"Surveillance","description":"Constant state observation."}],"recommendation":{"target_audience":"Dystopian readers","similar_books":[{"title":"Brave New World","author":"Aldous Huxley"}]}})

    review = Crig::Examples::AnthropicStructuredOutput.parse_review(raw)

    review.title.should eq("1984")
    review.recommendation.similar_books.first.title.should eq("Brave New World")
  end
end

describe Crig::Examples::AnthropicThinkTool, tags: %w[examples anthropic_think_tool] do
  it "builds the upstream anthropic think-tool agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicThinkTool.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_7_SONNET)
    agent.name.should eq(Crig::Examples::AnthropicThinkTool::NAME)
    agent.preamble.should eq(Crig::Examples::AnthropicThinkTool::PREAMBLE)
    agent.static_tools.map(&.name).should eq(["think"])
  end

  it "runs the anthropic think-tool prompt through a provided agent" do
    Crig::Examples::AnthropicThinkTool.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-3-7-sonnet")).build
    ).should eq("completion:claude-3-7-sonnet")
  end
end

describe Crig::Examples::AnthropicThinkToolWithOtherTools, tags: %w[examples anthropic_think_tool_with_other_tools] do
  it "builds the upstream anthropic beta client helper" do
    client = Crig::Examples::AnthropicThinkToolWithOtherTools.build_client("test-key")

    client.api_key.token.should eq("test-key")
    client.anthropic_betas.should eq([Crig::Examples::AnthropicThinkToolWithOtherTools::BETA])
  end

  it "builds the upstream anthropic think-tool-with-tools agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicThinkToolWithOtherTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_7_SONNET)
    agent.name.should eq(Crig::Examples::AnthropicThinkToolWithOtherTools::NAME)
    agent.preamble.should eq(Crig::Examples::AnthropicThinkToolWithOtherTools::PREAMBLE)
    agent.static_tools.map(&.name).should eq(%w[think calculator database_lookup])
  end

  it "evaluates calculator expressions with the example tool" do
    tool = Crig::Examples::AnthropicThinkToolWithOtherTools::Calculator.new
    args = Crig::Examples::AnthropicThinkToolWithOtherTools::CalculatorArgs.new("25 + (2 * 40)")

    tool.call_typed(args).should eq(105.0)
  end

  it "returns database lookup results with the example tool" do
    tool = Crig::Examples::AnthropicThinkToolWithOtherTools::DatabaseLookup.new
    args = Crig::Examples::AnthropicThinkToolWithOtherTools::DatabaseLookupArgs.new(
      Crig::Examples::AnthropicThinkToolWithOtherTools::Query::ShippingRates
    )

    tool.call_typed(args).should contain("Express shipping")
  end

  it "runs the anthropic think-tool-with-tools prompt through a provided agent" do
    Crig::Examples::AnthropicThinkToolWithOtherTools.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-3-7-sonnet"))
        .tools([
          Crig::ThinkTool.new.as(Crig::ToolDyn),
          Crig::Examples::AnthropicThinkToolWithOtherTools::Calculator.new.as(Crig::ToolDyn),
          Crig::Examples::AnthropicThinkToolWithOtherTools::DatabaseLookup.new.as(Crig::ToolDyn),
        ])
        .build
    ).should eq("completion:claude-3-7-sonnet")
  end
end

describe Crig::Examples::OpenAIAudioGeneration, tags: %w[examples openai_audio_generation] do
  it "builds the upstream openai audio generation model helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    model = Crig::Examples::OpenAIAudioGeneration.build_model(client)

    model.model.should eq(Crig::Providers::OpenAI::TTS_1)
  end

  it "builds and sends the upstream audio generation request helper" do
    model = FakeAudioGenerationClientModel.new("tts-1")
    response = Crig::Examples::OpenAIAudioGeneration.generate(model)

    response.audio.should eq(Bytes[7_u8, 8_u8])
    model.last_request.not_nil!.text.should eq(Crig::Examples::OpenAIAudioGeneration::DEFAULT_TEXT)
    model.last_request.not_nil!.voice.should eq(Crig::Examples::OpenAIAudioGeneration::DEFAULT_VOICE)
  end

  it "writes generated audio bytes to an io" do
    io = IO::Memory.new
    response = Crig::AudioGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-audio")

    Crig::Examples::OpenAIAudioGeneration.write_audio(response, io)

    io.to_slice.should eq(Bytes[1_u8, 2_u8, 3_u8])
  end
end

describe Crig::Examples::OpenAIImageGeneration, tags: %w[examples openai_image_generation] do
  it "builds the upstream openai image generation model helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    model = Crig::Examples::OpenAIImageGeneration.build_model(client)

    model.model.should eq(Crig::Providers::OpenAI::DALL_E_2)
  end

  it "builds and sends the upstream image generation request helper" do
    model = FakeImageGenerationClientModel.new("dall-e-2")
    response = Crig::Examples::OpenAIImageGeneration.generate(model)

    response.image.should eq(Bytes[9_u8, 10_u8])
    model.last_request.not_nil!.prompt.should eq(Crig::Examples::OpenAIImageGeneration::DEFAULT_PROMPT)
    model.last_request.not_nil!.width.should eq(1024)
    model.last_request.not_nil!.height.should eq(1024)
  end

  it "writes generated image bytes to an io" do
    io = IO::Memory.new
    response = Crig::ImageGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-image")

    Crig::Examples::OpenAIImageGeneration.write_image(response, io)

    io.to_slice.should eq(Bytes[1_u8, 2_u8, 3_u8])
  end
end

describe Crig::Examples::OpenAIStructuredOutput, tags: %w[examples openai_structured_output] do
  it "builds the upstream openai structured-output agent helpers" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIStructuredOutput.build_agent(client)
    schema_agent = Crig::Examples::OpenAIStructuredOutput.build_schema_agent(client)

    agent.preamble.should eq(Crig::Examples::OpenAIStructuredOutput::PREAMBLE)
    schema_agent.output_schema.not_nil!["title"].as_s.should eq("Crig::Examples::OpenAIStructuredOutput::WeatherForecast")
  end

  it "parses structured forecast json" do
    raw = %({"city":"New York","current":{"temperature_f":72.0,"humidity_pct":40,"description":"sunny","wind":{"speed_mph":5.5,"direction":"NW"}},"daily_forecast":[]})

    forecast = Crig::Examples::OpenAIStructuredOutput.parse_forecast(raw)

    forecast.city.should eq("New York")
    forecast.current.wind.direction.should eq("NW")
  end
end

describe Crig::Examples::OllamaStructuredOutput, tags: %w[examples ollama_structured_output] do
  it "builds the upstream ollama structured-output agent helper" do
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new)
    agent = Crig::Examples::OllamaStructuredOutput.build_agent(client)

    agent.model.model.should eq(Crig::Examples::OllamaStructuredOutput::MODEL)
    agent.preamble.should eq(Crig::Examples::OllamaStructuredOutput::PREAMBLE)
    agent.output_schema.not_nil!["title"].as_s.should eq("Crig::Examples::OllamaStructuredOutput::Character")
  end

  it "parses structured ollama character json" do
    raw = %({"name":"Mara Voss","age":34,"bio":"A geologist colonist on Mars.","traits":["curious","resilient"]})

    character = Crig::Examples::OllamaStructuredOutput.parse_character(raw)

    character.name.should eq("Mara Voss")
    character.traits.should eq(["curious", "resilient"])
  end
end

describe Crig::Examples::HyperbolicImageGeneration, tags: %w[examples hyperbolic_image_generation] do
  it "builds the upstream hyperbolic image generation model helper" do
    client = Crig::Providers::Hyperbolic::Client.new("test-key")
    model = Crig::Examples::HyperbolicImageGeneration.build_model(client)

    model.model.should eq(Crig::Providers::Hyperbolic::SDXL_TURBO)
  end

  it "builds and sends the upstream hyperbolic image generation request helper" do
    model = FakeImageGenerationClientModel.new("sdxl-turbo")
    response = Crig::Examples::HyperbolicImageGeneration.generate(model)

    response.image.should eq(Bytes[9_u8, 10_u8])
    model.last_request.not_nil!.prompt.should eq(Crig::Examples::HyperbolicImageGeneration::DEFAULT_PROMPT)
    model.last_request.not_nil!.width.should eq(1024)
    model.last_request.not_nil!.height.should eq(1024)
  end

  it "writes generated hyperbolic image bytes to an io" do
    io = IO::Memory.new
    response = Crig::ImageGenerationResponse(String).new(Bytes[3_u8, 2_u8, 1_u8], "raw-image")

    Crig::Examples::HyperbolicImageGeneration.write_image(response, io)

    io.to_slice.should eq(Bytes[3_u8, 2_u8, 1_u8])
  end
end

describe Crig::Examples::Image, tags: %w[examples image] do
  it "builds the upstream anthropic image agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::Image.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::Image::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "builds a jpeg image prompt from base64 data" do
    image = Crig::Examples::Image.image_from_base64("YW50")

    image.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
    image.data.kind.base64?.should be_true
    image.data.try_into_inner.should eq("YW50")
  end

  it "prompts a provided agent with image content" do
    model = FakeCompletionClientModel.new("claude-image")
    response = Crig::Examples::Image.prompt_image(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build,
      Crig::Examples::Image.image_from_base64("YW50")
    )

    response.should eq("completion:claude-image")
    content = model.last_request.not_nil!.chat_history.last.content.first
    content.as(Crig::Completion::UserContent).image.not_nil!.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
  end
end

describe Crig::Examples::AnthropicPlaintextDocument, tags: %w[examples anthropic_plaintext_document] do
  it "builds the upstream anthropic plaintext-document agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::AnthropicPlaintextDocument.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_4_SONNET)
    agent.preamble.should eq(Crig::Examples::AnthropicPlaintextDocument::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "builds the single-document prompt content" do
    document = Crig::Examples::AnthropicPlaintextDocument.document

    document.media_type.should eq(Crig::Completion::DocumentMediaType::TXT)
    document.data.kind.string?.should be_true
    document.data.try_into_inner.not_nil!.includes?("systems programming language").should be_true
  end

  it "builds the document-plus-instruction user message" do
    message = Crig::Examples::AnthropicPlaintextDocument.instruction_message

    message.role.user?.should be_true
    message.content.to_a.size.should eq(2)
    message.content.to_a.first.as(Crig::Completion::UserContent).document.not_nil!.media_type.should eq(Crig::Completion::DocumentMediaType::TXT)
    message.content.to_a.last.as(Crig::Completion::UserContent).text.not_nil!.text.should eq(Crig::Examples::AnthropicPlaintextDocument::PROMPT)
  end

  it "prompts a provided agent with document content" do
    model = FakeCompletionClientModel.new("claude-doc")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    Crig::Examples::AnthropicPlaintextDocument.document_prompt(agent).should eq("completion:claude-doc")
    Crig::Examples::AnthropicPlaintextDocument.instruction_prompt(agent).should eq("completion:claude-doc")
  end
end

describe Crig::Examples::Loaders, tags: %w[examples loaders] do
  it "reads files through the upstream file-loader helper" do
    results = Crig::Examples::Loaders.read_glob("shard.yml")

    results.size.should eq(1)
    results.first.as(String).includes?("name: crig").should be_true
  end
end

describe Crig::Examples::AgentWithCohere, tags: %w[examples agent_with_cohere] do
  it "builds the upstream cohere basic agent helper" do
    client = Crig::Providers::Cohere::Client.new("test-key")
    agent = Crig::Examples::AgentWithCohere.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
    agent.preamble.should eq(Crig::Examples::AgentWithCohere::BASIC_PREAMBLE)
  end

  it "builds the upstream cohere calculator agent helper" do
    client = Crig::Providers::Cohere::Client.new("test-key")
    agent = Crig::Examples::AgentWithCohere.build_calculator_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithCohere::CALCULATOR_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "runs the cohere example prompt through a provided agent" do
    Crig::Examples::AgentWithCohere.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("command-r")).build,
      "Tell me a joke"
    ).should eq("completion:command-r")
  end
end

describe Crig::Examples::MultiTurnAgent, tags: %w[examples multi_turn_agent] do
  it "builds the upstream anthropic multi-turn arithmetic agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::MultiTurnAgent.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::MultiTurnAgent::PREAMBLE)
    agent.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "runs multi-turn prompts through the provided arithmetic agent" do
    response = Crig::Examples::MultiTurnAgent.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-3-5-sonnet"))
        .tools(Crig::Examples::AgentWithDefaultMaxTurns::TOOLS.map(&.as(Crig::ToolDyn)))
        .build,
      "Calculate 5 - 2 = ?. Describe the result to me."
    )

    response.should eq("completion:claude-3-5-sonnet")
  end
end

describe Crig::Examples::MultiTurnAgentExtended, tags: %w[examples multi_turn_agent_extended] do
  it "builds the upstream extended-details arithmetic agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::MultiTurnAgentExtended.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::MultiTurnAgentExtended::PREAMBLE)
    agent.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "returns extended details for multi-turn prompts" do
    response = Crig::Examples::MultiTurnAgentExtended.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("claude-3-5-sonnet"))
        .tools(Crig::Examples::AgentWithDefaultMaxTurns::TOOLS.map(&.as(Crig::ToolDyn)))
        .build,
      "Calculate (3 + 5) / 9  = ?. Describe the result to me."
    )

    response.output.should eq("completion:claude-3-5-sonnet")
  end
end

describe Crig::Examples::AgentWithMira, tags: %w[examples agent_with_mira] do
  it "builds the upstream mira basic agent helper" do
    client = Crig::Providers::Mira::Client.new("test-key")
    agent = Crig::Examples::AgentWithMira.build_basic_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::AgentWithMira::BASIC_PREAMBLE)
    agent.temperature.should eq(0.7)
  end

  it "builds the upstream mira calculator agent helper" do
    client = Crig::Providers::Mira::Client.new("test-key")
    agent = Crig::Examples::AgentWithMira.build_calculator_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::AgentWithMira::CALCULATOR_PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "lists models through the mira client" do
    http_server = HTTP::Server.new do |context|
      if context.request.method == "GET" && context.request.path == "/v1/models"
        context.response.content_type = "application/json"
        context.response.print(%({"data":[{"id":"gpt-4o"},{"id":"claude-3-5-sonnet-latest"}]}))
      else
        context.response.status_code = HTTP::Status::NOT_FOUND.code
        context.response.print("Not Found")
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Mira::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    Crig::Examples::AgentWithMira.list_models(client).should eq(["gpt-4o", "claude-3-5-sonnet-latest"])

    http_server.close
  end
end

describe Crig::Examples::AgentWithLoaders, tags: %w[examples agent_with_loaders] do
  it "loads upstream rust example files through the file loader helper" do
    loaded = Crig::Examples::AgentWithLoaders.load_examples("vendor/rig/rig/rig-core/examples/agent.rs")
    entry = loaded.first.as(Tuple(String, String))

    loaded.size.should eq(1)
    entry[0].ends_with?("vendor/rig/rig/rig-core/examples/agent.rs").should be_true
    entry[1].includes?("comedian").should be_true
  end

  it "builds the upstream loader-backed context agent helper" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithLoaders.build_agent(
      client,
      glob: "vendor/rig/rig/rig-core/examples/agent.rs"
    )

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.static_context.size.should eq(1)
    agent.static_context.first.text.includes?("Rust Example").should be_true
  end

  it "runs the loader-backed example prompt through a provided agent" do
    Crig::Examples::AgentWithLoaders.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    ).should eq("completion:gpt-4o")
  end
end

describe Crig::Examples::AgentPromptChaining, tags: %w[examples agent_prompt_chaining] do
  it "builds the upstream prompt-chaining helper agents" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    rng_agent = Crig::Examples::AgentPromptChaining.build_rng_agent(client)
    adder_agent = Crig::Examples::AgentPromptChaining.build_adder_agent(client)

    rng_agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4)
    adder_agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4)
    rng_agent.preamble.should eq(Crig::Examples::AgentPromptChaining::RNG_PREAMBLE)
    adder_agent.preamble.should eq(Crig::Examples::AgentPromptChaining::ADDER_PREAMBLE)
  end

  it "chains agent prompts through the pipeline adapter" do
    rng_model = FakeCompletionClientModel.new("rng")
    adder_model = FakeCompletionClientModel.new("adder")
    rng_agent = Crig::AgentBuilder(FakeCompletionClientModel).new(rng_model)
      .preamble(Crig::Examples::AgentPromptChaining::RNG_PREAMBLE)
      .build
    adder_agent = Crig::AgentBuilder(FakeCompletionClientModel).new(adder_model)
      .preamble(Crig::Examples::AgentPromptChaining::ADDER_PREAMBLE)
      .build

    result = Crig::Examples::AgentPromptChaining.run_prompt(
      Crig::Examples::AgentPromptChaining.build_chain(rng_agent, adder_agent)
    )

    result.unwrap.should eq("completion:adder")
    rng_model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::AgentPromptChaining.default_prompt)
    adder_model.last_request.not_nil!.chat_history.last.rag_text.should eq("completion:rng")
  end
end

describe Crig::Examples::Extractor, tags: %w[examples extractor] do
  it "builds the upstream extractor helper for openai responses models" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"
      require "./examples/extractor"

      client = Crig::Providers::OpenAI::Client.new("test-key")
      extractor = Crig::Examples::Extractor.build_extractor(client)

      puts(JSON.build do |json|
        json.object do
          json.field "model", extractor.agent_builder.model.model
          json.field "tools" do
            json.array do
              extractor.agent_builder.static_tools_value.each do |tool|
                json.string(tool.name)
              end
            end
          end
        end
      end)
    CRYSTAL

    result["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4)
    result["tools"].as_a.map(&.as_s).should contain("submit")
  end

  it "formats extracted people and usage responses as pretty json" do
    person = Crig::Examples::Extractor::Person.new("John", "Doe", "software engineer")
    response = Crig::ExtractionResponse(Crig::Examples::Extractor::Person).new(
      person,
      Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3),
    )

    Crig::Examples::Extractor.pretty_person(person).includes?("\"first_name\": \"John\"").should be_true
    Crig::Examples::Extractor.pretty_response(response).includes?("\"job\": \"software engineer\"").should be_true
  end
end

describe Crig::Examples::ExtractorWithDeepSeek, tags: %w[examples extractor_with_deepseek] do
  it "builds the upstream deepseek extractor helper" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    extractor = Crig::Examples::ExtractorWithDeepSeek.build_extractor(client)

    # Check that the extractor has an agent
    extractor.agent.should_not be_nil
    # Check for the submit tool in the agent's tools
    extractor.agent.static_tools.any? { |tool| tool.name == "submit" }.should be_true
  end

  it "formats extracted people as pretty json" do
    person = Crig::Examples::ExtractorWithDeepSeek::Person.new("John", "Doe", "software engineer")

    Crig::Examples::ExtractorWithDeepSeek.pretty_person(person).includes?("\"job\": \"software engineer\"").should be_true
  end
end

describe Crig::Examples::Chain, tags: %w[examples chain] do
  it "builds the dictionary store from upstream sample entries" do
    store = Crig::Examples::Chain.build_store(FakeEmbeddingModel.new)

    store.len.should eq(3)
    store.get_document("doc1", Crig::Examples::Chain::DictionaryEntry).not_nil!.text.includes?("glarb-glarb").should be_true
  end

  it "builds the chain example pipeline and threads retrieved context into the prompt" do
    store = Crig::Examples::Chain.build_store(FakeEmbeddingModel.new)
    index = store.index(FakeEmbeddingModel.new)
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    response = Crig::Examples::Chain.build_chain(index, agent).call(Crig::Examples::Chain.default_prompt)

    response.unwrap.should eq("completion:gpt-4o")
    prompt = model.last_request.not_nil!.chat_history.last.rag_text || raise "missing prompt"
    prompt.includes?("Non standard word definitions").should be_true
    prompt.includes?("glarb-glarb").should be_true
  end
end

describe Crig::Examples::Rag, tags: %w[examples rag] do
  it "builds the upstream rag store from embedded word definitions" do
    store = Crig::Examples::Rag.build_store(FakeEmbeddingModel.new)

    store.len.should eq(3)
    store.get_document("doc1", Crig::Examples::Rag::WordDefinition).not_nil!.word.should eq("glarb-glarb")
  end

  it "builds a dynamic-context rag agent and prompts through it" do
    store = Crig::Examples::Rag.build_store(FakeEmbeddingModel.new)
    index = store.index(FakeEmbeddingModel.new)
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::Rag.build_agent(client, index)

    agent.preamble.should eq(Crig::Examples::Rag::PREAMBLE)
    agent.dynamic_context.size.should eq(1)
  end
end

describe Crig::Examples::VectorSearch, tags: %w[examples vector_search] do
  it "builds the upstream vector-search store from embedded word definitions" do
    store = Crig::Examples::VectorSearch.build_store(FakeEmbeddingModel.new)

    store.len.should eq(3)
    store.get_document("doc0", Crig::Examples::VectorSearch::WordDefinition).not_nil!.word.should eq("flurbo")
  end

  it "builds the upstream request helper" do
    request = Crig::Examples::VectorSearch.request

    request.query.should eq(Crig::Examples::VectorSearch.default_query)
    request.samples.should eq(1_u64)
  end

  it "returns top-n typed search results and matching id results" do
    store = Crig::Examples::VectorSearch.build_store(FakeEmbeddingModel.new)
    index = store.index(FakeEmbeddingModel.new)
    query = "flurbo"

    results = Crig::Examples::VectorSearch.search(index, query)
    id_results = Crig::Examples::VectorSearch.search_ids(index, query)

    results.size.should eq(1)
    results[0][1].should eq("doc0")
    results[0][2].should eq("flurbo")
    id_results.should eq([{results[0][0], "doc0"}])
  end
end

describe Crig::Examples::RMCP::StructRequest do
  it "deserializes the Rust example request shape" do
    request = Crig::Examples::RMCP::StructRequest.from_json(%({"a":2,"b":5}))

    request.a.should eq(2)
    request.b.should eq(5)
  end
end

describe Crig::Examples::RMCP::Counter do
  it "initializes with a server and exposes the sum tool behavior" do
    counter = Crig::Examples::RMCP::Counter.new
    result = counter.sum(Crig::Examples::RMCP::StructRequest.new(2, 5))

    result.content.first.as(MCP::Protocol::TextContentBlock).text.should eq("7")
    counter.server.should be_a(MCP::Server::Server)
  end

  it "lists and reads resources from the example server state" do
    counter = Crig::Examples::RMCP::Counter.new

    counter.list_resources.resources.map(&.uri).sort.should eq([
      "memo://insights",
      "str:////Users/to/some/path/",
    ])
    counter.read_resource("memo://insights").contents.first.as(MCP::Protocol::TextResourceContents).text.should contain("Business Intelligence Memo")
    counter.list_resource_templates.resource_templates.should eq([] of MCP::Protocol::ResourceTemplate)
  end
end

describe Crig::Examples::RMCP::StreamableServer do
  it "builds an HTTP server wrapper around the RMCP counter server" do
    streamable = Crig::Examples::RMCP::StreamableServer.from_counter

    streamable.endpoint.should eq("/mcp")
    streamable.http_server.should be_a(HTTP::Server)
    streamable.active_session_ids.should eq([] of String)
  end

  it "supports streamable HTTP MCP client requests for the RMCP example" do
    streamable = Crig::Examples::RMCP::StreamableServer.from_counter
    http_server = streamable.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Examples::RMCP.build_client("http://127.0.0.1:#{address.port}/mcp")
    tools = client.list_tools.not_nil!.tools
    result = client.call_tool("sum", {
      "a" => JSON::Any.new(2),
      "b" => JSON::Any.new(5),
    }).as(MCP::Protocol::CallToolResult)

    tools.map(&.name).should eq(["sum"])
    result.content.first.as(MCP::Protocol::TextContentBlock).text.should eq("7")

    client.close
    http_server.close
  end

  it "builds and runs the RMCP example through the completion client agent path" do
    streamable = Crig::Examples::RMCP::StreamableServer.from_counter
    http_server = streamable.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    openai_server = FakeOpenAIChatServer.new do |request|
      last_item = request["input"].as_a.last

      if last_item["type"].as_s == "function_call_output"
        {
          content_type: "application/json",
          body:         %({
            "id":"resp_final",
            "object":"response",
            "created_at":1,
            "status":"completed",
            "model":"gpt-4o",
            "usage":{
              "input_tokens":5,
              "input_tokens_details":{"cached_tokens":0},
              "output_tokens":4,
              "output_tokens_details":{"reasoning_tokens":0},
              "total_tokens":9
            },
            "output":[
              {
                "type":"message",
                "id":"msg_final",
                "role":"assistant",
                "status":"completed",
                "content":[{"type":"output_text","text":"7"}]
              }
            ],
            "tools":[]
          }),
        }
      else
        {
          content_type: "application/json",
          body:         %({
            "id":"resp_tool",
            "object":"response",
            "created_at":1,
            "status":"completed",
            "model":"gpt-4o",
            "usage":{
              "input_tokens":2,
              "input_tokens_details":{"cached_tokens":0},
              "output_tokens":3,
              "output_tokens_details":{"reasoning_tokens":0},
              "total_tokens":5
            },
            "output":[
              {
                "type":"function_call",
                "id":"fc_1",
                "arguments":{"a":2,"b":5},
                "call_id":"call_1",
                "name":"sum",
                "status":"completed"
              }
            ],
            "tools":[]
          }),
        }
      end
    end
    openai_http_server = openai_server.http_server
    openai_address = openai_http_server.bind_tcp("127.0.0.1", 0)
    spawn { openai_http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{openai_address.port}/v1")
    agent = Crig::Examples::RMCP.build_agent(client, Crig::Providers::OpenAI::GPT_4O, "http://127.0.0.1:#{address.port}/mcp")
    response = Crig::Examples::RMCP.run_prompt(
      client,
      Crig::Providers::OpenAI::GPT_4O,
      "http://127.0.0.1:#{address.port}/mcp",
      "What is 2+5?"
    )

    agent.tool_server_handle.should_not be_nil
    response.should eq("7")
    openai_server.requests.size.should eq(2)

    openai_http_server.close
    http_server.close
  end
end

describe Crig::Completion::PromptError do
  it "builds a cancelled prompt error with context" do
    history = [Crig::Completion::Message.user("hello")]
    error = Crig::Completion::PromptError.prompt_cancelled(history, "stop")

    error.message.should eq("PromptCancelled: stop")
    error.kind.should eq(Crig::Completion::PromptError::Kind::PromptCancelled)
    error.reason.should eq("stop")
    error.chat_history.should eq(history)
  end

  it "builds a max turns exceeded error with context" do
    history = [Crig::Completion::Message.user("hello")]
    prompt = Crig::Completion::Message.user("tool again")
    error = Crig::Completion::PromptError.max_turns_exceeded(0, history, prompt)

    error.message.should eq("MaxTurnsExceeded: 0")
    error.kind.should eq(Crig::Completion::PromptError::Kind::MaxTurnsError)
    error.reason.should eq("MaxTurnsExceeded: 0")
    error.chat_history.should eq(history)
    error.prompt.should eq(prompt)
    error.max_turns.should eq(0)
  end

  it "wraps completion, tool, and tool-server errors" do
    completion = Crig::Completion::PromptError.completion_error(
      Crig::Completion::CompletionError.provider_error("provider down")
    )
    tool = Crig::Completion::PromptError.tool_error(
      Crig::ToolSetError.tool_not_found("lookup")
    )
    tool_server = Crig::Completion::PromptError.tool_server_error(
      Crig::ToolServerError.send_error("disconnected")
    )

    completion.kind.should eq(Crig::Completion::PromptError::Kind::CompletionError)
    completion.completion_error.not_nil!.message.should eq("ProviderError: provider down")
    tool.kind.should eq(Crig::Completion::PromptError::Kind::ToolError)
    tool.tool_error.not_nil!.message.should eq("ToolNotFoundError: lookup")
    tool_server.kind.should eq(Crig::Completion::PromptError::Kind::ToolServerError)
    tool_server.tool_server_error.not_nil!.message.should eq("SendError: disconnected")
  end
end

describe Crig::Completion::Request::Document, tags: %w[completion request] do
  it "renders without metadata" do
    document = Crig::Completion::Request::Document.new("123", "This is a test document.")

    document.to_s.should eq("<file id: 123>\nThis is a test document.\n</file>\n")
  end

  it "renders with sorted metadata" do
    document = Crig::Completion::Request::Document.new(
      "123",
      "This is a test document.",
      {"length" => "42", "author" => "John Doe"}
    )

    document.to_s.should eq("<file id: 123>\n<metadata author: \"John Doe\" length: \"42\" />\nThis is a test document.\n</file>\n")
  end
end

describe Crig::Completion::Request::CompletionRequest, tags: %w[completion request] do
  it "normalizes documents into a user message" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is the capital of France?")),
      documents: [
        Crig::Completion::Request::Document.new("doc1", "Document 1 text."),
        Crig::Completion::Request::Document.new("doc2", "Document 2 text."),
      ]
    )

    normalized = request.normalized_documents
    normalized.should_not be_nil
    message = normalized.as(Crig::Completion::Message)
    message.role.user?.should be_true
    message.content.to_a.size.should eq(2)
  end

  it "returns nil when there are no documents" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("hello"))
    )

    request.normalized_documents.should be_nil
  end

  it "derives the output schema name from title" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("hello")),
      output_schema: JSON.parse(%({"title":"weather_response"}))
    )

    request.output_schema_name.should eq("weather_response")
  end
end

describe Crig::Completion::Request::CompletionRequestBuilder, tags: %w[completion builder] do
  it "builds a completion request from prompt, history, and documents" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .preamble("You are Marvin.")
      .message(Crig::Completion::Message.user("Earlier"))
      .document(Crig::Completion::Request::Document.new("doc1", "Document 1 text."))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .max_tokens(42)
      .build

    request.preamble.should eq("You are Marvin.")
    request.chat_history.to_a.size.should eq(2)
    request.documents.size.should eq(1)
    request.tool_choice.try(&.kind.required?).should be_true
    request.max_tokens.should eq(42)
  end

  it "sends through a completion model" do
    model = FakeCompletionModel.new
    response = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .send(model)

    response.raw_response.should eq("raw")
    model.last_request.should_not be_nil
  end

  it "merges additional params objects" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .additional_params(JSON.parse(%({"outer":{"a":1}})))
      .additional_params(JSON.parse(%({"outer":{"b":2},"other":3})))
      .build

    request.additional_params.should_not be_nil
    params = request.additional_params.as(JSON::Any)
    params["outer"]["a"].as_i.should eq(1)
    params["outer"]["b"].as_i.should eq(2)
    params["other"].as_i.should eq(3)
  end

  it "builds from string prompts via from_prompt" do
    builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")

    builder.prompt.rag_text.should eq("Who are you?")
  end

  it "builds from string prompts via new" do
    builder = Crig::Completion::Request::CompletionRequestBuilder.new("Who are you?")

    builder.prompt.rag_text.should eq("Who are you?")
  end

  it "builds from message prompts via new" do
    prompt = Crig::Completion::Message.user("Who are you?")
    builder = Crig::Completion::Request::CompletionRequestBuilder.new(prompt)

    builder.prompt.should eq(prompt)
  end
end

describe Crig::Completion::ToolChoice, tags: %w[completion tool_choice] do
  it "supports specific function selection" do
    choice = Crig::Completion::ToolChoice.specific(["weather", "stocks"])

    choice.kind.specific?.should be_true
    choice.function_names.should eq(["weather", "stocks"])
  end

  it "round-trips json variants" do
    variants = [
      Crig::Completion::ToolChoice.auto,
      Crig::Completion::ToolChoice.none,
      Crig::Completion::ToolChoice.required,
      Crig::Completion::ToolChoice.specific(["weather"]),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::ToolChoice.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.function_names.should eq(variant.function_names)
    end
  end
end

describe Crig::Completion::MediaType do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::MediaType.image(Crig::Completion::ImageMediaType::PNG),
      Crig::Completion::MediaType.audio(Crig::Completion::AudioMediaType::MP3),
      Crig::Completion::MediaType.document(Crig::Completion::DocumentMediaType::TXT),
      Crig::Completion::MediaType.video(Crig::Completion::VideoMediaType::WEBM),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::MediaType.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.image.should eq(variant.image)
      roundtrip.audio.should eq(variant.audio)
      roundtrip.document.should eq(variant.document)
      roundtrip.video.should eq(variant.video)
    end
  end
end

describe Crig::Completion::ImageDetail do
  it "parses upstream detail variants" do
    Crig::Completion::ImageDetail.parse?("low").should eq(Crig::Completion::ImageDetail::Low)
    Crig::Completion::ImageDetail.parse?("high").should eq(Crig::Completion::ImageDetail::High)
    Crig::Completion::ImageDetail.parse?("auto").should eq(Crig::Completion::ImageDetail::Auto)
    Crig::Completion::ImageDetail.parse?("unknown").should be_nil
  end
end

describe Crig::Completion::Image do
  it "builds wrapper helpers for common source kinds" do
    params = JSON.parse(%({"provider":"test"}))
    url = Crig::Completion::Image.url("https://example.com/a.png", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::High, params)
    base64 = Crig::Completion::Image.base64("Zm9v", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::Low)
    raw = Crig::Completion::Image.raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG)
    string = Crig::Completion::Image.string("hello", Crig::Completion::ImageMediaType::PNG)

    url.data.kind.url?.should be_true
    url.media_type.should eq(Crig::Completion::ImageMediaType::PNG)
    url.detail.should eq(Crig::Completion::ImageDetail::High)
    url.additional_params.should eq(params)
    base64.data.kind.base64?.should be_true
    base64.detail.should eq(Crig::Completion::ImageDetail::Low)
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::UserContent, tags: %w[completion content] do
  it "builds multimedia helpers" do
    image = Crig::Completion::UserContent.image_url("https://example.com/a.png", Crig::Completion::ImageMediaType::PNG)
    audio = Crig::Completion::UserContent.audio("Zm9v", Crig::Completion::AudioMediaType::MP3)
    document = Crig::Completion::UserContent.document("hello", Crig::Completion::DocumentMediaType::TXT)
    video = Crig::Completion::UserContent.video_url("https://example.com/a.mp4", Crig::Completion::VideoMediaType::MP4)

    image.kind.image?.should be_true
    image.image.as(Crig::Completion::Image).try_into_url.should eq("https://example.com/a.png")
    audio.kind.audio?.should be_true
    document.kind.document?.should be_true
    video.kind.video?.should be_true
    Crig::Completion::DocumentMediaType::Javascript.is_code.should be_true
  end
end

describe Crig::Completion::AssistantContent, tags: %w[completion content] do
  it "builds helper content variants" do
    text = Crig::Completion::AssistantContent.text("hello")
    tool_call = Crig::Completion::AssistantContent.tool_call("tool-1", "weather", JSON.parse(%({"city":"Paris"})))
    reasoning = Crig::Completion::AssistantContent.reasoning("thinking")
    image = Crig::Completion::AssistantContent.image_base64("Zm9v", Crig::Completion::ImageMediaType::PNG)

    text.kind.text?.should be_true
    tool_call.kind.tool_call?.should be_true
    tool_call.tool_call.not_nil!.function.name.should eq("weather")
    reasoning.kind.reasoning?.should be_true
    reasoning.reasoning.not_nil!.first_text.should eq("thinking")
    image.kind.image?.should be_true
    image.image.should_not be_nil
  end
end

describe Crig::Completion::DocumentSourceKind do
  it "supports source helpers and inner extraction" do
    url = Crig::Completion::DocumentSourceKind.url("https://example.com/file")
    base64 = Crig::Completion::DocumentSourceKind.base64("Zm9v")
    string = Crig::Completion::DocumentSourceKind.string("hello")
    unknown = Crig::Completion::DocumentSourceKind.unknown

    url.try_into_inner.should eq("https://example.com/file")
    base64.try_into_inner.should eq("Zm9v")
    string.try_into_inner.should eq("hello")
    unknown.try_into_inner.should be_nil
  end

  it "converts base64 images into data urls" do
    image = Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.base64("Zm9v"),
      Crig::Completion::ImageMediaType::PNG,
    )

    image.try_into_url.should eq("data:image/png;base64,Zm9v")
  end

  it "raises message errors for unsupported image url conversions" do
    expect_raises(Crig::Completion::MessageError, /media type is required/) do
      Crig::Completion::Image.base64("Zm9v").try_into_url
    end

    expect_raises(Crig::Completion::MessageError, /unknown type/) do
      Crig::Completion::Image.raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG).try_into_url
    end
  end
end

describe Crig::Completion::Audio do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Audio.url("https://example.com/a.mp3", Crig::Completion::AudioMediaType::MP3)
    base64 = Crig::Completion::Audio.base64("Zm9v", Crig::Completion::AudioMediaType::MP3)
    raw = Crig::Completion::Audio.raw(Bytes[1_u8, 2_u8], Crig::Completion::AudioMediaType::WAV)
    string = Crig::Completion::Audio.string("hello", Crig::Completion::AudioMediaType::AAC)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Video do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Video.url("https://example.com/a.mp4", Crig::Completion::VideoMediaType::MP4)
    base64 = Crig::Completion::Video.base64("Zm9v", Crig::Completion::VideoMediaType::WEBM)
    raw = Crig::Completion::Video.raw(Bytes[1_u8, 2_u8], Crig::Completion::VideoMediaType::MOV)
    string = Crig::Completion::Video.string("hello", Crig::Completion::VideoMediaType::AVI)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Document do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Document.url("https://example.com/a.pdf", Crig::Completion::DocumentMediaType::PDF)
    base64 = Crig::Completion::Document.base64("Zm9v", Crig::Completion::DocumentMediaType::TXT)
    raw = Crig::Completion::Document.raw(Bytes[1_u8, 2_u8], Crig::Completion::DocumentMediaType::CSV)
    string = Crig::Completion::Document.string("hello", Crig::Completion::DocumentMediaType::MARKDOWN)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Message, tags: %w[completion message] do
  it "supports conversion helpers from typed content" do
    text_message = Crig::Completion::Message.from(Crig::Completion::Text.new("hello"))
    image_message = Crig::Completion::Message.from(
      Crig::Completion::Image.new(
        Crig::Completion::DocumentSourceKind.url("https://example.com/a.png"),
        Crig::Completion::ImageMediaType::PNG,
      )
    )

    text_message.role.user?.should be_true
    text_message.rag_text.should eq("hello")
    image_message.role.user?.should be_true
  end

  it "supports additional upstream-style message conversions" do
    string_message = Crig::Completion::Message.from("hello")
    tool_result_message = Crig::Completion::Message.from(
      Crig::Completion::ToolResultContent.text("done")
    )
    assistant_message = Crig::Completion::Message.from(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("hi")
      )
    )

    string_message.role.user?.should be_true
    string_message.rag_text.should eq("hello")

    tool_result_message.role.user?.should be_true
    tool_result = tool_result_message.content.first.as(Crig::Completion::UserContent).tool_result
    tool_result.should_not be_nil
    tool_result.as(Crig::Completion::ToolResult).id.should eq("")
    tool_result.as(Crig::Completion::ToolResult).content.first.kind.text?.should be_true

    assistant_message.role.assistant?.should be_true
    assistant_message.content.first.as(Crig::Completion::AssistantContent).kind.text?.should be_true
  end
end

describe "Crig::Pipeline parallel N-arity", tags: %w[pipeline parallel narity] do
  it "parallel with 3 ops produces nested tuple" do
    op1 = Crig::Pipeline.map(->(x : Int32) { x + 1 })
    op2 = Crig::Pipeline.map(->(x : Int32) { x * 3 })
    op3 = Crig::Pipeline.map(->(x : Int32) { "#{x} is the number!" })

    result = Crig::Pipeline.parallel(op1, op2, op3).call(1)
    result.should eq({ {2, 3}, "1 is the number!" })
  end

  it "parallel with 4 ops produces nested tuple" do
    op1 = Crig::Pipeline.map(->(x : Int32) { x + 1 })
    op2 = Crig::Pipeline.map(->(x : Int32) { x * 3 })
    op3 = Crig::Pipeline.map(->(x : Int32) { "#{x} is the number!" })
    op4 = Crig::Pipeline.map(->(x : Int32) { x == 1 })

    result = Crig::Pipeline.parallel(op1, op2, op3, op4).call(1)
    result.should eq({ { {2, 3}, "1 is the number!" }, true })
  end

  it "nested parallel with passthrough" do
    op = Crig::Pipeline.parallel(
      Crig::Pipeline.passthrough(Int32),
      Crig::Pipeline.passthrough(Int32),
      Crig::Pipeline.passthrough(Int32),
    )

    result = op.call(1)
    result.should eq({ {1, 1}, 1 })
  end

  it "sequential and parallel combined" do
    op1 = Crig::Pipeline.map(->(x : Int32) { x + 1 })
    op2 = Crig::Pipeline.map(->(x : Int32) { x * 2 })
    op3 = Crig::Pipeline.map(->(x : Int32) { x * 3 })
    op4 = Crig::Pipeline.map(->(t : Tuple(Int32, Int32)) { t[0] + t[1] })

    pipeline = op1
      .chain(Crig::Pipeline.parallel(op2, op3))
      .chain(op4)

    result = pipeline.call(1)
    result.should eq(10)
  end
end

describe "Crig::Completion::Reasoning constructors", tags: %w[completion reasoning constructors] do
  it "constructs reasoning with new" do
    single = Crig::Completion::Reasoning.new("think")
    single.first_text.should eq("think")
    single.first_signature.should be_nil
    single.display_text.should eq("think")
  end

  it "constructs reasoning with signature" do
    signed = Crig::Completion::Reasoning.new_with_signature("signed", "sig-1")
    signed.first_text.should eq("signed")
    signed.first_signature.should eq("sig-1")
    signed.display_text.should eq("signed")
  end

  it "constructs multi reasoning" do
    multi = Crig::Completion::Reasoning.multi(["a", "b"])
    multi.display_text.should eq("a\nb")
    multi.first_text.should eq("a")
  end

  it "roundtrips reasoning content through JSON" do
    text_variant = Crig::Completion::ReasoningContent.text("plain", "sig")
    json = text_variant.to_json
    parsed = Crig::Completion::ReasoningContent.from_json(json)
    parsed.kind.text?.should be_true
    parsed.text.should eq("plain")
    parsed.signature.should eq("sig")

    encrypted_variant = Crig::Completion::ReasoningContent.encrypted("opaque")
    json2 = encrypted_variant.to_json
    parsed2 = Crig::Completion::ReasoningContent.from_json(json2)
    parsed2.kind.encrypted?.should be_true
    parsed2.data.should eq("opaque")

    redacted_variant = Crig::Completion::ReasoningContent.redacted("redacted")
    json3 = redacted_variant.to_json
    parsed3 = Crig::Completion::ReasoningContent.from_json(json3)
    parsed3.kind.redacted?.should be_true
    parsed3.data.should eq("redacted")

    summary_variant = Crig::Completion::ReasoningContent.summary("sum")
    json4 = summary_variant.to_json
    parsed4 = Crig::Completion::ReasoningContent.from_json(json4)
    parsed4.kind.summary?.should be_true
    parsed4.summary.should eq("sum")
  end
end

describe "merge_reasoning_blocks", tags: %w[streaming reasoning merge] do
  it "preserves order and signatures for matching ids" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new_with_signature("step-1", "sig-1").with_id("rs_1")
    second = Crig::Completion::Reasoning.new_with_signature("step-2", "sig-2").with_id("rs_1")
    incoming = Crig::Completion::Reasoning.new_with_signature("step-3", "sig-3").with_id("rs_1")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, second)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(1)
    accumulated.first.id.should eq("rs_1")
    accumulated.first.content.size.should eq(3)
    accumulated.first.content[0].text.should eq("step-1")
    accumulated.first.content[1].text.should eq("step-2")
    accumulated.first.content[2].text.should eq("step-3")
    accumulated.first.content[0].signature.should eq("sig-1")
    accumulated.first.content[1].signature.should eq("sig-2")
    accumulated.first.content[2].signature.should eq("sig-3")
  end

  it "keeps distinct ids as separate items" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new("step-1").with_id("rs_a")
    incoming = Crig::Completion::Reasoning.new("step-2").with_id("rs_b")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
    accumulated[0].id.should eq("rs_a")
    accumulated[1].id.should eq("rs_b")
  end

  it "keeps nil ids as separate items" do
    accumulated = [] of Crig::Completion::Reasoning
    first = Crig::Completion::Reasoning.new("first")
    incoming = Crig::Completion::Reasoning.new("second")

    Crig.merge_reasoning_blocks(accumulated, first)
    Crig.merge_reasoning_blocks(accumulated, incoming)

    accumulated.size.should eq(2)
  end
end

describe "OneOrMany#map_one_or_many", tags: %w[one_or_many map] do
  it "transforms single item to new type" do
    one = Crig::OneOrMany(String).one("42")
    result = one.map_one_or_many { |s| s.to_i32 }
    result.first.should eq(42)
    result.len.should eq(1)
  end

  it "transforms multiple items preserving OneOrMany" do
    many = Crig::OneOrMany(String).many(["1", "2", "3"])
    result = many.map_one_or_many { |s| s.to_i32 }
    result.to_a.should eq([1, 2, 3])
    result.len.should eq(3)
  end
end

describe "JSONUtils::StringOrVecConverter", tags: %w[json string_or_vec] do
  it "deserializes a single string into an array" do
    result = DummyStringOrVec.from_json(%({"items":"hello"}))
    result.items.should eq(["hello"])
  end

  it "deserializes an array into an array" do
    result = DummyStringOrVec.from_json(%({"items":["hello","world"]}))
    result.items.should eq(["hello", "world"])
  end
end

describe "JSONUtils::NullOrVecConverter", tags: %w[json null_or_vec] do
  it "deserializes null into empty array" do
    result = DummyNullOrVec.from_json(%({"items":null}))
    result.items.should eq([] of String)
  end

  it "deserializes an array into an array" do
    result = DummyNullOrVec.from_json(%({"items":["a","b"]}))
    result.items.should eq(["a", "b"])
  end
end

require "file_utils"
