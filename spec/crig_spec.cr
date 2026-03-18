require "./spec_helper"

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
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text(%({"city":"Denver","temperature":72}))
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
    response : Crig::Completion::CompletionResponse(String),
  ) : Crig::HookAction
    @events << "response:#{response.raw_response}"
    return Crig::HookAction.terminate("stop-after-send") if @terminate_on_response
    Crig::HookAction.cont
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

class FakeProviderExtension
  include Crig::Provider(Symbol)

  def self.verify_path : String
    "/verify"
  end

  def builder_type : Symbol.class
    Symbol
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

  def initialize(@models : Array(Crig::ModelInfo))
  end

  def list_all : Crig::ModelList
    Crig::ModelList.new(@models)
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

describe Crig::VerifyError do
  it "builds parity-style verification errors" do
    Crig::VerifyError.invalid_authentication.message.should eq("invalid authentication")
    Crig::VerifyError.provider_error("boom").message.should eq("provider error: boom")
    Crig::VerifyError.http_error("timeout").message.should eq("http error: timeout")
  end
end

describe Crig::VerifyClient do
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
end

describe Crig::VerifyClientDyn do
  it "supports the dynamic verification interface" do
    client = SuccessfulVerifyClient.new.as(Crig::VerifyClientDyn)

    client.verify
  end
end

describe Crig::EmbeddingsClient(FakeEmbeddingsClientModel) do
  it "builds embedding models and builders through the client interface" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model("test-model")
    builder = client.embeddings(ExampleEmbedding, "test-model").document(ExampleEmbedding.new(["hello"]))

    model.name.should eq("test-model")
    builder.model.name.should eq("test-model")
    builder.build[0][1].first.document.should eq("test-model:hello")
  end

  it "supports explicit embedding dimensions" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model_with_ndims("test-model", 42)
    builder = client.embeddings_with_ndims(ExampleEmbedding, "test-model", 42).document(ExampleEmbedding.new(["hello"]))

    model.ndims.should eq(42)
    builder.model.ndims.should eq(42)
  end
end

describe Crig::EmbeddingsClientDyn do
  it "returns dynamic embedding models" do
    client = FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn)
    model = client.embedding_model("test-model")

    model.embed_text("hello").document.should eq("test-model:hello")
    client.embedding_model_with_ndims("test-model", 42).ndims.should eq(42)
  end
end

describe Crig::CompletionClient(FakeCompletionClientModel) do
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

describe Crig::CompletionClientDyn do
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

describe Crig::CompletionModelHandle do
  it "wraps a dynamic completion model for request and stream builders" do
    inner = FakeCompletionClientModel.new("gpt-4o").as(Crig::Completion::CompletionModelDyn)
    handle = Crig::CompletionModelHandle.new(inner)
    completion = handle.completion_request("hello").send(handle)
    stream = handle.completion_request("hello").stream(handle)

    completion.raw_response.should eq("raw:gpt-4o")
    stream.chunks.should eq(["chunk:gpt-4o"])
    stream.response.try(&.usage).try(&.total_tokens).should eq(3)
  end
end

describe Crig::FinalCompletionResponse do
  it "exposes token usage for dynamic streaming parity" do
    response = Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))

    response.token_usage.try(&.total_tokens).should eq(4)
  end
end

describe Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse) do
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
end

describe Crig::PauseControl do
  it "tracks paused state" do
    control = Crig::PauseControl.new

    control.is_paused.should be_false
    control.pause
    control.is_paused.should be_true
    control.resume
    control.is_paused.should be_false
  end
end

describe Crig::RawStreamingToolCall do
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

describe Crig::ToolCallDeltaContent do
  it "supports name and delta variants" do
    name = Crig::ToolCallDeltaContent.name("weather")
    delta = Crig::ToolCallDeltaContent.delta("{\"city\":\"Denver\"}")

    name.kind.name?.should be_true
    name.value.should eq("weather")
    delta.kind.delta?.should be_true
    delta.value.should eq("{\"city\":\"Denver\"}")
  end
end

describe Crig::RawStreamingChoice(String) do
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

describe Crig::StreamedAssistantContent(Crig::FinalCompletionResponse) do
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

describe Crig::StreamedUserContent do
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

describe Crig::StreamingResult(String) do
  it "stores raw streaming choices" do
    result = Crig::StreamingResult(String).new([
      Crig::RawStreamingChoice(String).message("hello"),
      Crig::RawStreamingChoice(String).final_response("done"),
    ])

    result.items.size.should eq(2)
    result.items.last.final_response.should eq("done")
  end
end

describe Crig::AgentBuilder(FakeCompletionClientModel) do
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
end

describe Crig::Agent(FakeCompletionClientModel) do
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

describe Crig::HookAction do
  it "supports continue and terminate helpers" do
    Crig::HookAction.cont.kind.continue?.should be_true
    terminated = Crig::HookAction.terminate("stop")

    terminated.kind.terminate?.should be_true
    terminated.reason.should eq("stop")
  end
end

describe Crig::ToolCallHookAction do
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

describe Crig::PromptHook do
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
    Crig::StreamingError.completion("boom").message.should eq("CompletionError: boom")
    Crig::StreamingError.prompt("stop").message.should eq("PromptError: stop")
    Crig::StreamingError.tool("missing").message.should eq("ToolSetError: missing")
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

    result.items.size.should eq(2)
    result.items[0].kind.stream_assistant_item?.should be_true
    result.items[0].assistant_item.try(&.text).try(&.text).should eq("chunk:gpt-4o")
    result.items[1].kind.final_response?.should be_true
    result.items[1].final_response.try(&.response).should eq("chunk:gpt-4o")
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

describe Crig::DynClientBuilderError do
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
end

describe Crig::AnyClient do
  it "exposes supported dynamic client capabilities" do
    client = Crig::AnyClient.new(FakeCompletionClient.new)

    client.as_completion.should_not be_nil
    client.as_embedding.should be_nil
    client.as_transcription.should be_nil
  end

  it "supports manually composed capability sets" do
    client = Crig::AnyClient.new(
      completion: FakeCompletionClient.new.as(Crig::CompletionClientDyn),
      embeddings: FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn),
    )

    client.as_completion.should_not be_nil
    client.as_embedding.should_not be_nil
  end
end

describe Crig::DynClientBuilder do
  it "registers and looks up provider factories by provider:model key" do
    builder = Crig::DynClientBuilder.new.register("openai", "gpt-4o") do
      Crig::AnyClient.new(FakeCompletionClient.new)
    end

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

  it "raises parity-style not-found errors for missing registrations" do
    builder = Crig::DynClientBuilder.new

    expect_raises(Crig::DynClientBuilderError, "Provider 'openai:gpt-4o' not found") do
      builder.from_env("openai", "gpt-4o")
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

describe Crig::ClientBuilderError do
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
end

describe Crig::Capabilities do
  it "exposes capability flags on provider capability sets" do
    capabilities = FakeCapabilities.new

    capabilities.completion_capability.should be_true
    capabilities.embeddings_capability.should be_false
    capabilities.transcription_capability.should be_true
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
    client.get("/models").method.should eq("GET")
    client.get_sse("/events").uri.should eq("https://api.example.com/events")
    client.post_sse("/stream").uri.should eq("https://api.example.com/stream")
  end
end

describe Crig::Client::ClientBuilder(FakeProviderExtension, Crig::NeedsApiKey, Nil) do
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

describe Crig::ModelListingClient do
  it "lists all models through the client interface" do
    client = FakeModelListingClient.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = client.list_models

    models.len.should eq(2)
    models.data[0].display_name.should eq("GPT-4")
  end
end

describe Crig::ModelLister(Array(Crig::ModelInfo)) do
  it "lists all models through the lister interface" do
    lister = FakeModelLister.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = lister.list_all

    models.len.should eq(2)
    models.data[1].display_name.should eq("GPT-3.5 Turbo")
  end
end

describe Crig::AudioGenerationClient(FakeAudioGenerationClientModel) do
  it "builds audio generation models through the client interface" do
    client = FakeAudioGenerationClient.new
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    model.name.should eq("tts-1")
    response.response.should eq("audio:tts-1")
    model.last_request.try(&.voice).should eq("alloy")
  end
end

describe Crig::AudioGenerationClientDyn do
  it "builds dynamic audio generation models" do
    client = FakeAudioGenerationClient.new.as(Crig::AudioGenerationClientDyn)
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end
end

describe Crig::AudioGenerationModelHandle do
  it "wraps a dynamic model for the request builder" do
    inner = FakeAudioGenerationClientModel.new("tts-1").as(Crig::AudioGenerationModelDyn)
    handle = Crig::AudioGenerationModelHandle.new(inner)
    response = handle.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end
end

describe Crig::ImageGenerationClient(FakeImageGenerationClientModel) do
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

describe Crig::ImageGenerationClientDyn do
  it "builds dynamic image generation models" do
    client = FakeImageGenerationClient.new.as(Crig::ImageGenerationClientDyn)
    model = client.image_generation_model("dall-e-3")
    response = model.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end
end

describe Crig::ImageGenerationModelHandle do
  it "wraps a dynamic image model for the request builder" do
    inner = FakeImageGenerationClientModel.new("dall-e-3").as(Crig::ImageGenerationModelDyn)
    handle = Crig::ImageGenerationModelHandle.new(inner)
    response = handle.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end
end

describe Crig::TranscriptionClient(FakeTranscriptionClientModel) do
  it "builds transcription models through the client interface" do
    client = FakeTranscriptionClient.new
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send

    model.name.should eq("whisper-1")
    response.response.should eq("transcription:whisper-1")
    model.last_request.try(&.filename).should eq("clip.wav")
  end
end

describe Crig::TranscriptionClientDyn do
  it "builds dynamic transcription models" do
    client = FakeTranscriptionClient.new.as(Crig::TranscriptionClientDyn)
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
  end
end

describe Crig::TranscriptionModelHandle do
  it "wraps a dynamic transcription model for the request builder" do
    inner = FakeTranscriptionClientModel.new("whisper-1").as(Crig::TranscriptionModelDyn)
    handle = Crig::TranscriptionModelHandle.new(inner)
    response = handle.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
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
    one_or_many.first.should eq("hello")
  end

  it "builds many items and preserves order" do
    one_or_many = Crig::OneOrMany(String).many(["hello", "world"])

    one_or_many.to_a.should eq(["hello", "world"])
    one_or_many.rest.should eq(["world"])
    one_or_many.last.should eq("world")
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

  it "rejects empty collections" do
    expect_raises(Crig::EmptyListError, "Cannot create OneOrMany with an empty vector.") do
      Crig::OneOrMany(String).many([] of String)
    end
  end
end

describe Crig::Embeddings do
  it "collects texts from embeddable values" do
    Crig::Embeddings.to_texts(ExampleEmbedding.new(["hello", "world"])).should eq(["hello", "world"])
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

describe Crig::EvalOutcome do
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

describe Crig::SemanticSimilarityMetric do
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
    list.iter.size.should eq(1)
  end

  it "supports empty lists" do
    list = Crig::Model::ModelList.new([] of Crig::Model::Model)

    list.empty?.should be_true
    list.len.should eq(0)
  end

  it "round-trips via json" do
    list = Crig::Model::ModelList.new([Crig::Model::Model.from_id("gpt-4")])
    parsed = Crig::Model::ModelList.from_json(list.to_json)

    parsed.len.should eq(1)
    parsed.data.first.id.should eq("gpt-4")
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

describe Crig::Completion::Message do
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

describe Crig::Completion::ReasoningContent do
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

describe Crig::Completion::ToolResultContent do
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

describe Crig::Completion::Usage do
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

describe Crig::Completion::ToolDefinition do
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

describe Crig::Completion::PromptError do
  it "builds a cancelled prompt error with context" do
    history = [Crig::Completion::Message.user("hello")]
    error = Crig::Completion::PromptError.prompt_cancelled(history, "stop")

    error.message.should eq("PromptCancelled: stop")
    error.reason.should eq("stop")
    error.chat_history.should eq(history)
  end

  it "builds a max turns exceeded error with context" do
    history = [Crig::Completion::Message.user("hello")]
    prompt = Crig::Completion::Message.user("tool again")
    error = Crig::Completion::PromptError.max_turns_exceeded(0, history, prompt)

    error.message.should eq("MaxTurnsExceeded: 0")
    error.reason.should eq("MaxTurnsExceeded: 0")
    error.chat_history.should eq(history)
    error.prompt.should eq(prompt)
    error.max_turns.should eq(0)
  end
end

describe Crig::Completion::Request::Document do
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

describe Crig::Completion::Request::CompletionRequest do
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

describe Crig::Completion::Request::CompletionRequestBuilder do
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
end

describe Crig::Completion::ToolChoice do
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

describe Crig::Completion::UserContent do
  it "builds multimedia helpers" do
    image = Crig::Completion::UserContent.image_url("https://example.com/a.png", Crig::Completion::ImageMediaType::PNG)
    audio = Crig::Completion::UserContent.audio("Zm9v", Crig::Completion::AudioMediaType::MP3)
    document = Crig::Completion::UserContent.document("hello", Crig::Completion::DocumentMediaType::TXT)

    image.kind.image?.should be_true
    image.image.as(Crig::Completion::Image).try_into_url.should eq("https://example.com/a.png")
    audio.kind.audio?.should be_true
    document.kind.document?.should be_true
    Crig::Completion::DocumentMediaType::Javascript.is_code.should be_true
  end
end

describe Crig::Completion::AssistantContent do
  it "builds image helper content" do
    content = Crig::Completion::AssistantContent.image_base64("Zm9v", Crig::Completion::ImageMediaType::PNG)

    content.kind.image?.should be_true
    content.image.should_not be_nil
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
end

describe Crig::Completion::Message do
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
