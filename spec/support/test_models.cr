# Shared test-double models for specs.
# These are loaded automatically via spec_helper's `require "./support/*"`.

# Minimal CompletionModel that returns a fixed "ok" response.
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

# CompletionModel that returns a fixed JSON string via tool-call or text.
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

    Crig::Completion::CompletionResponse(String).new(choice, @usage, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @last_request = request
    ["streamed"]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

# Minimal EmbeddingModel that returns fixed-dimension embeddings.
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

# In-memory Channel-based test HTTP client for SSE streaming.
class ReconnectingSseClient
  include Crig::HttpClient::HttpClientExt

  getter sent_requests = [] of HTTP::Request

  @stream_calls : Int32 = 0

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

# Test payload struct for typed-prompt and extractor specs.
struct WeatherPayload
  include JSON::Serializable

  getter city : String
  getter temperature : Int32

  def initialize(@city : String, @temperature : Int32)
  end
end

# CompletionModel that returns a fixed JSON weather response.
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

# Tool argument struct shared across tool specs.
struct EchoArgs
  include JSON::Serializable

  getter value : String

  def initialize(@value : String)
  end
end

# Tool that echoes its argument value.
struct EchoTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
  end

  def call_typed(args : EchoArgs) : String
    args.value
  end
end

# Tool with a custom name for disambiguation in multi-tool tests.
struct DefaultNamedTool
  include Crig::Tool(EchoArgs, String)

  NAME = "default-named"

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
  end

  def call_typed(args : EchoArgs) : String
    args.value
  end
end

# CompletionModel that returns "completion:{name}" text and "raw:{name}" raw_response.
# Used across agent, builder, and request-hook specs.
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

# Image-generation model for request-builder and concurrency specs.
class FakeImageGenerationModel
  include Crig::ImageGenerationModel
  include Crig::ImageGenerationModelDyn

  getter last_request : Crig::ImageGenerationRequest?

  def image_generation(request : Crig::ImageGenerationRequest)
    @last_request = request
    Crig::ImageGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-image")
  end

  def image_generation_request : Crig::ImageGenerationRequestBuilder
    Crig::ImageGenerationRequestBuilder.new(self)
  end
end

# Audio-generation model for request-builder and concurrency specs.
class FakeAudioGenerationModel
  include Crig::AudioGenerationModel
  include Crig::AudioGenerationModelDyn

  getter last_request : Crig::AudioGenerationRequest?

  def audio_generation(request : Crig::AudioGenerationRequest) : Crig::AudioGenerationResponse(String)
    @last_request = request
    Crig::AudioGenerationResponse(String).new(Bytes[4_u8, 5_u8], "raw-audio")
  end

  def audio_generation_request : Crig::AudioGenerationRequestBuilder
    Crig::AudioGenerationRequestBuilder.new(self)
  end
end

# Transcription model for request-builder and concurrency specs.
class FakeTranscriptionModel
  include Crig::TranscriptionModel
  include Crig::TranscriptionModelDyn

  getter last_request : Crig::TranscriptionRequest?

  def transcription(request : Crig::TranscriptionRequest)
    @last_request = request
    Crig::TranscriptionResponse(String).new("hello world", "raw-transcription")
  end

  def transcription_request : Crig::TranscriptionRequestBuilder
    Crig::TranscriptionRequestBuilder.new(self)
  end
end

# Transcription model that raises on every call.
class FailingTranscriptionModel
  include Crig::TranscriptionModel
  include Crig::TranscriptionModelDyn

  def transcription(request : Crig::TranscriptionRequest)
    raise Crig::TranscriptionError.new("provider unavailable for #{request.filename}")
  end

  def transcription_request : Crig::TranscriptionRequestBuilder
    Crig::TranscriptionRequestBuilder.new(self)
  end
end

struct FailingEchoTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
  end

  def call_typed(args : EchoArgs) : String
    raise "boom"
  end
end

# Document payload used by vector-store specs.
struct StoredDoc
  include JSON::Serializable

  getter id : String
  getter name : String

  def initialize(@id : String, @name : String)
  end
end

def vector_embedding(document : String, values : Array(Float64)) : Crig::OneOrMany(Crig::Embeddings::Embedding)
  Crig::OneOrMany(Crig::Embeddings::Embedding).one(Crig::Embeddings::Embedding.new(document, values))
end

# Embeddable documents for embeddings-builder and client specs.
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

struct RecursiveFailingTool
  include Crig::Tool(EchoArgs, String)

  def name : String
    "echo"
  end

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
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

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
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

  def description : String
    "Echo the given value with runtime state"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
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

  def description : String
    "Sleeps for the configured duration"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object","properties":{}}))
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

class FakeConcurrentToolTurnStreamingModel
  include Crig::Completion::CompletionModel

  getter turn_counter = 0

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

    choice = if turn.zero?
               Crig::OneOrMany(Crig::Completion::AssistantContent).many([
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_1",
                   "call_1",
                   "tool_one",
                   JSON.parse(%({"input":"one"})),
                 ),
                 Crig::Completion::AssistantContent.tool_call_with_call_id(
                   "tool_call_2",
                   "call_2",
                   "tool_two",
                   JSON.parse(%({"input":"two"})),
                 ),
               ])
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("done")
               )
             end

    usage = turn.zero? ? Crig::Completion::Usage.new(total_tokens: 4) : Crig::Completion::Usage.new(total_tokens: 6)
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).new(
      turn.zero? ? [] of String : ["done"],
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

# SSE client that fails the first connect, opens and errors mid-stream on the
# second, then recovers on the third — used to assert retry-cycle reset on open.
class OpenErrorThenReconnectSseClient
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
    call = @stream_calls
    spawn do
      case call
      when 2
        channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok("data: first\n\n".to_slice))
        channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).err(Crig::HttpClient::Error.stream_ended))
      when 3
        channel.send(Crig::HttpClient::Result(Bytes, Crig::HttpClient::Error).ok("data: recovered\n\n".to_slice))
      end
      channel.close
    end

    Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error).ok(
      Crig::HttpClient::StreamingResponse.new(channel: channel)
    )
  end
end
