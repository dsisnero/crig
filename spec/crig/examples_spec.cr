require "../spec_helper"
require "file_utils"
require "../../examples/agent"
require "../../examples/agent_stream_chat"
require "../../examples/agent_with_agent_tool/agent_with_agent_tool"
require "../../examples/agent_prompt_chaining"
require "../../examples/agent_with_cohere"
require "../../examples/agent_with_grok"
require "../../examples/agent_with_groq"
require "../../examples/agent_with_huggingface"
require "../../examples/agent_with_hyperbolic"
require "../../examples/agent_with_moonshot"
require "../../examples/agent_with_ollama"
require "../../examples/agent_with_openrouter"
require "../../examples/agent_with_tools"
require "../../examples/agent_with_tools_otel"
require "../../examples/agent_with_default_max_turns"
require "../../examples/agent_with_context"
require "../../examples/agent_with_deepseek"
require "../../examples/agent_with_echochambers"
require "../../examples/agent_with_together"
require "../../examples/agent_with_loaders"
require "../../examples/agent_with_mira"
require "../../examples/chain"
require "../../examples/enum_dispatch"
require "../../examples/extractor"
require "../../examples/extractor_with_deepseek"
require "../../examples/gemini_agent"
require "../../examples/gemini_embeddings"
require "../../examples/gemini_extractor"
require "../../examples/gemini_deep_research"
require "../../examples/gemini_interactions_api"
require "../../examples/gemini_streaming_with_tools"
require "../../examples/gemini_structured_output"
require "../../examples/gemini_extractor_with_rag"
require "../../examples/gemini_video_understanding"
require "../../examples/multi_turn_streaming_gemini"
require "../../examples/groq_streaming_reasoning"
require "../../examples/hyperbolic_image_generation"
require "../../examples/hyperbolic_audio_generation"
require "../../examples/huggingface_image_generation"
require "../../examples/huggingface_subproviders"
require "../../examples/huggingface_streaming"
require "../../examples/image"
require "../../examples/image_ollama"
require "../../examples/loaders"
require "../../examples/multi_extract"
require "../../examples/multi_turn_agent"
require "../../examples/multi_turn_agent_extended"
require "../../examples/multi_turn_streaming"
require "../../examples/anthropic_plaintext_document"
require "../../examples/openai_image_generation"
require "../../examples/rag"
require "../../examples/rag_dynamic_tools"
require "../../examples/rmcp"
require "../../examples/request_hook"
require "../../examples/reqwest_middleware"
require "../../examples/simple_model"
require "../../examples/together_embeddings"
require "../../examples/together_streaming"
require "../../examples/together_streaming_with_tools"
require "../../examples/transcription"
require "../../examples/anthropic_agent"
require "../../examples/anthropic_structured_output"
require "../../examples/anthropic_streaming"
require "../../examples/anthropic_streaming_with_tools"
require "../../examples/anthropic_think_tool"
require "../../examples/anthropic_think_tool_with_other_tools"
require "../../examples/calculator_chatbot"
require "../../examples/cohere_streaming"
require "../../examples/cohere_streaming_with_tools"
require "../../examples/complex_agentic_loop_claude"
require "../../examples/custom_vector_store"
require "../../examples/deepseek_streaming"
require "../../examples/debate"
require "../../examples/discord_bot"
require "../../examples/gemini_streaming"
require "../../examples/vector_search"
require "../../examples/vector_search_cohere"
require "../../examples/vector_search_ollama"
require "../../examples/voyageai_embeddings"
require "../../examples/ollama_streaming"
require "../../examples/ollama_streaming_pause_control"
require "../../examples/ollama_streaming_with_tools"
require "../../examples/ollama_structured_output"
require "../../examples/openai_audio_generation"
require "../../examples/openai_agent_completions_api"
require "../../examples/openai_agent_completions_api_otel"
require "../../examples/openai_structured_output"
require "../../examples/openai_streaming"
require "../../examples/openai_streaming_with_tools"
require "../../examples/openai_streaming_with_tools_otel"
require "../../examples/openrouter_multimodal"
require "../../examples/openrouter_provider_selection"
require "../../examples/openrouter_streaming_with_tools"
require "../../examples/perplexity_agent"
require "../../examples/pdf_agent"
require "../../examples/reasoning_loop"
require "../../examples/reasoning_roundtrip_test"
require "../../examples/xai_streaming"
require "../../examples/mistral_embeddings"
require "../../examples/multi_agent"
require "../../examples/rag_ollama"
require "../../examples/rag_dynamic_tools_multi_turn"
require "../../examples/sentiment_classifier"

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

class RecordingAgentHook
  include Crig::AgentHook

  getter events : Array(String)

  def initialize
    @events = [] of String
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    @events << event.kind.to_s
    Crig::Flow.cont
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

class FakeReasoningRoundtripModel
  include Crig::Completion::CompletionModel

  getter requests = [] of Crig::Completion::Request::CompletionRequest

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @requests << request
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("unused")
      ),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @requests << request
    turn = @requests.size
    raw_choices = if turn == 1
                    [
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_turn_1", "step"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning_delta("rs_turn_1", " one"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("First answer."),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message_id("msg_turn_1"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 7))
                      ),
                    ]
                  else
                    [
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).reasoning(
                        "rs_turn_2",
                        Crig::Completion::ReasoningContent.summary("follow-up reasoning"),
                      ),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message("Second answer with context."),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).message_id("msg_turn_2"),
                      Crig::RawStreamingChoice(Crig::FinalCompletionResponse).final_response(
                        Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 9))
                      ),
                    ]
                  end

    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream_raw_choices(raw_choices)
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeReasoningLoopModel
  include Crig::Completion::CompletionModel

  getter requests = [] of Crig::Completion::Request::CompletionRequest

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @requests << request
    submit_tool = request.tools.find { |tool| tool.name == "submit" }
    choice = if submit_tool
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "tool_call_submit",
                   "submit",
                   JSON.parse(%({"steps":["Compute 15 + 25","Compute 100 - 50","Divide the products"]})),
                 )
               )
             else
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("computed result")
               )
             end

    Crig::Completion::CompletionResponse(String).new(
      choice,
      Crig::Completion::Usage.new(output_tokens: 4),
      "completion:reasoning-loop",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    @requests << request
    Crig::StreamingCompletionResponse(Crig::FinalCompletionResponse).stream(
      ["streamed"],
      Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 1)),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

class FakeWasmCompat
  include Crig::WasmCompatSend
  include Crig::WasmCompatSync
  include Crig::WasmCompatSendStream
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

  # FIXME: Crystal 1.20.2 compiler bug triggers codegen crash in probe build
  pending "builds extractor helpers with the upstream example preambles" do
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

describe Crig::Examples::AgentWithToolsOtel, tags: %w[examples agent_with_tools_otel] do
  it "builds the upstream tools agent helper with telemetry span availability" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithToolsOtel.build_agent(client)

    agent.preamble.should eq(Crig::Examples::AgentWithTools::PREAMBLE)
    agent.static_tools.map(&.name).sort.should eq(%w[add subtract])
    Crig::Examples::AgentWithToolsOtel.current_span.disabled?.should be_true
  end

  it "runs the upstream calculator prompt helper" do
    model = FakeCompletionClientModel.new("gpt-4o")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
      .tool(Crig::Examples::AgentWithTools::Adder.new)
      .tool(Crig::Examples::AgentWithTools::Subtract.new)
      .build

    Crig::Examples::AgentWithToolsOtel.run_prompt(agent).should eq("completion:gpt-4o")
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

    final_response.output.should eq("chunk:gpt-4")
    final_response.messages.not_nil!.first.rag_text.should eq("Tell me a joke!")
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

    final_response.output.should eq("chunk:gpt-4o-mini")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OpenAIStreaming::PROMPT)
  end
end

describe Crig::Examples::OpenAIStreamingWithTools, tags: %w[examples openai_streaming_with_tools] do
  it "builds the upstream openai streaming-with-tools agent helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::OpenAIStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams openai tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("gpt-4o")
    response = Crig::Examples::OpenAIStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::OpenAIStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:gpt-4o")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OpenAIStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::OpenAIStreamingWithToolsOtel, tags: %w[examples openai_streaming_with_tools_otel] do
  it "builds the upstream streaming tools agent helper with telemetry span availability" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIStreamingWithToolsOtel.build_agent(client)

    agent.name.should eq("Bob")
    agent.preamble.should eq(Crig::Examples::OpenAIStreamingWithTools::PREAMBLE)
    agent.static_tools.map(&.name).sort.should eq(%w[add subtract])
    Crig::Examples::OpenAIStreamingWithToolsOtel.current_span.disabled?.should be_true
  end

  it "streams the upstream tools prompt through the shared stdout helper" do
    model = FakeCompletionClientModel.new("gpt-4o")
    builder = Crig::AgentBuilder(FakeCompletionClientModel).new(model)
    Crig::Examples::AgentWithTools.tools.each do |tool|
      builder = builder.tool(tool)
    end
    agent = builder.build
    response = Crig::Examples::OpenAIStreamingWithToolsOtel.run_stream(agent)
    final_response = Crig::Examples::OpenAIStreamingWithToolsOtel.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:gpt-4o")
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

    final_response.output.should eq("chunk:llama3.2")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OllamaStreaming::PROMPT)
  end
end

describe Crig::Examples::OllamaStreamingWithTools, tags: %w[examples ollama_streaming_with_tools] do
  it "builds the upstream ollama streaming-with-tools agent helper" do
    client = Crig::Examples::OllamaStreamingWithTools.build_client("http://127.0.0.1:11434")
    agent = Crig::Examples::OllamaStreamingWithTools.build_agent(client)

    client.base_url.should eq("http://127.0.0.1:11434")
    agent.model.model.should eq(Crig::Examples::OllamaStreamingWithTools::MODEL)
    agent.preamble.should eq(Crig::Examples::OllamaStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams ollama tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("llama3.2")
    response = Crig::Examples::OllamaStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::OllamaStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:llama3.2")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OllamaStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::OllamaStreamingPauseControl, tags: %w[examples ollama_streaming_pause_control] do
  it "builds the upstream ollama pause-control client and model helpers" do
    client = Crig::Examples::OllamaStreamingPauseControl.build_client("http://127.0.0.1:11434")
    model = Crig::Examples::OllamaStreamingPauseControl.build_model(client)

    client.base_url.should eq("http://127.0.0.1:11434")
    model.model.should eq(Crig::Examples::OllamaStreamingPauseControl::MODEL)
  end

  it "builds the upstream pause-control completion request helper" do
    model = FakeCompletionClientModel.new("gemma3:4b")
    request = Crig::Examples::OllamaStreamingPauseControl.build_request(model)

    request.chat_history.last.rag_text.should eq(Crig::Examples::OllamaStreamingPauseControl::PROMPT)
    request.preamble.should eq(Crig::Examples::OllamaStreamingPauseControl::PREAMBLE)
    request.temperature.should eq(0.7)
  end

  it "processes streaming content with pause and resume control" do
    stream = Crig::StreamingCompletionResponse(Crig::Completion::CompletionResponse(String)).stream(
      [
        Crig::RawStreamingChoice(Crig::Completion::CompletionResponse(String)).message("part-1"),
        Crig::RawStreamingChoice(Crig::Completion::CompletionResponse(String)).message("part-2"),
        Crig::RawStreamingChoice(Crig::Completion::CompletionResponse(String)).final_response(
          Crig::Completion::CompletionResponse(String).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("done")),
            Crig::Completion::Usage.new(total_tokens: 12),
            "raw",
          )
        ),
      ]
    )

    stats = Crig::Examples::OllamaStreamingPauseControl.process_stream(stream, IO::Memory.new, pause_every: 1)

    stats.text.should eq("part-1part-2")
    stats.chunk_count.should eq(2)
    stats.usage.not_nil!.total_tokens.should eq(12)
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

    final_response.output.should eq("chunk:claude-stream")
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

    final_response.output.should eq("chunk:claude-4-sonnet")
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

    final_response.output.should eq("chunk:command")
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

    final_response.output.should eq("chunk:command-r")
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

    final_response.output.should eq("chunk:deepseek-chat")
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

    final_response.output.should eq("chunk:deepseek-chat")
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

    final_response.output.should eq("chunk:gemini-2.0-flash")
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

    final_response.output.should eq("chunk:gemini-2.5-flash")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::GeminiStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::MultiTurnStreamingGemini, tags: %w[examples multi_turn_streaming_gemini] do
  it "builds the upstream gemini multi-turn streaming agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::MultiTurnStreamingGemini.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Gemini::GEMINI_2_5_FLASH)
    agent.preamble.should eq(Crig::Examples::MultiTurnStreamingGemini::PREAMBLE)
    agent.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "streams prompts through the gemini multi-turn helper" do
    model = FakeCompletionClientModel.new("gemini-2.5-flash")
    result = Crig::Examples::MultiTurnStreamingGemini.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::MultiTurnStreamingGemini.stream_to_stdout(result, IO::Memory.new)

    final_response.output.should eq("chunk:gemini-2.5-flash")
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

    final_response.output.should eq("chunk:deepseek-r1-distill")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::GroqStreamingReasoning::PROMPT)
  end
end

describe Crig::Examples::OpenRouterStreamingWithTools, tags: %w[examples openrouter_streaming_with_tools] do
  it "builds the upstream openrouter streaming-with-tools agent helper" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    agent = Crig::Examples::OpenRouterStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenRouter::GEMINI_FLASH_2_0)
    agent.preamble.should eq(Crig::Examples::OpenRouterStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams openrouter tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("google/gemini-2.0-flash-001")
    response = Crig::Examples::OpenRouterStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::OpenRouterStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:google/gemini-2.0-flash-001")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::OpenRouterStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::OpenRouterMultimodal, tags: %w[examples openrouter_multimodal] do
  it "builds the upstream openrouter multimodal agent helper" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    agent = Crig::Examples::OpenRouterMultimodal.build_agent(
      client,
      "You are a helpful assistant that describes images in detail."
    )

    agent.model.model.should eq(Crig::Examples::OpenRouterMultimodal::VISION_MODEL)
    agent.preamble.should eq("You are a helpful assistant that describes images in detail.")
  end

  it "builds the upstream image, pdf, and mixed multimodal messages" do
    image = Crig::Examples::OpenRouterMultimodal.image_message
    pdf = Crig::Examples::OpenRouterMultimodal.pdf_message
    mixed = Crig::Examples::OpenRouterMultimodal.mixed_message

    image.content.to_a.size.should eq(2)
    image_image = image.content.to_a.last.as(Crig::Completion::UserContent).image.not_nil!
    image_image.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
    image_image.data.try_into_inner.should eq(Crig::Examples::OpenRouterMultimodal::IMAGE_URL)

    pdf.content.to_a.size.should eq(2)
    pdf_document = pdf.content.to_a.last.as(Crig::Completion::UserContent).document.not_nil!
    pdf_document.media_type.should eq(Crig::Completion::DocumentMediaType::PDF)
    pdf_document.data.try_into_inner.should eq(Crig::Examples::OpenRouterMultimodal::PDF_URL)

    mixed.content.to_a.size.should eq(4)
    mixed_image = mixed.content.to_a[2].as(Crig::Completion::UserContent).image.not_nil!
    mixed_image.media_type.should eq(Crig::Completion::ImageMediaType::PNG)
  end

  it "prompts a provided agent with multimodal messages" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("openrouter-vision")).build

    Crig::Examples::OpenRouterMultimodal.run_prompt(agent, Crig::Examples::OpenRouterMultimodal.image_message)
      .should eq("completion:openrouter-vision")
  end
end

describe Crig::Examples::OpenRouterProviderSelection, tags: %w[examples openrouter_provider_selection] do
  it "builds the upstream provider preference helpers" do
    Crig::Examples::OpenRouterProviderSelection.order_preferences.to_json_value["provider"]["order"].as_a.map(&.as_s)
      .should eq(["DeepInfra", "DeepSeek", "Chutes"])
    Crig::Examples::OpenRouterProviderSelection.allowlist_preferences.to_json_value["provider"]["only"].as_a.map(&.as_s)
      .should eq(["DeepInfra", "AtlasCloud"])
    Crig::Examples::OpenRouterProviderSelection.blocklist_preferences.to_json_value["provider"]["ignore"].as_a.map(&.as_s)
      .should eq(["Google Vertex"])
    Crig::Examples::OpenRouterProviderSelection.latency_preferences.to_json_value["provider"]["sort"].as_s.should eq("latency")
    Crig::Examples::OpenRouterProviderSelection.price_with_throughput_preferences
      .to_json_value["provider"]["sort"].as_s.should eq("price")
    Crig::Examples::OpenRouterProviderSelection.require_parameters_preferences
      .to_json_value["provider"]["require_parameters"].as_bool.should be_true
    Crig::Examples::OpenRouterProviderSelection.zdr_preferences.to_json_value["provider"]["zdr"].as_bool.should be_true
    Crig::Examples::OpenRouterProviderSelection.quantization_preferences
      .to_json_value["provider"]["quantizations"].as_a.map(&.as_s).should eq(["fp8"])
    max_price = Crig::Examples::OpenRouterProviderSelection.max_price_preferences.to_json_value["provider"]["max_price"]
    max_price["prompt"].as_f.should eq(0.30)
    max_price["completion"].as_f.should eq(0.50)
  end

  it "builds the combined routing params and agent helper" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    params = Crig::Examples::OpenRouterProviderSelection.combined_params
    agent = Crig::Examples::OpenRouterProviderSelection.build_agent(client, params)

    agent.model.model.should eq(Crig::Examples::OpenRouterProviderSelection::DEEPSEEK_V3_2)
    agent.additional_params.should eq(params)
  end

  it "runs the provider-selection prompt through a provided agent" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("deepseek-v3.2")).build

    Crig::Examples::OpenRouterProviderSelection.run_prompt(agent, "Say hello in one sentence.")
      .should eq("completion:deepseek-v3.2")
  end
end

describe Crig::Examples::ReasoningLoop, tags: %w[examples reasoning_loop] do
  it "builds the upstream anthropic reasoning loop helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::ReasoningLoop.build_agent(client)

    agent.chain_of_thought_extractor.agent.preamble.not_nil!.includes?(Crig::Examples::ReasoningLoop::CHAIN_OF_THOUGHT_PROMPT.strip).should be_true
    agent.executor.preamble.should eq(Crig::Examples::ReasoningLoop::EXECUTOR_PREAMBLE)
    agent.executor.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "extracts steps and runs the executor with history" do
    model = FakeReasoningLoopModel.new
    reasoning_agent = Crig::Examples::ReasoningLoop::ReasoningAgent(FakeReasoningLoopModel).new(
      Crig::ExtractorBuilder(FakeReasoningLoopModel, Crig::Examples::ReasoningLoop::ChainOfThoughtSteps)
        .new(model)
        .build,
      Crig::AgentBuilder(FakeReasoningLoopModel).new(model)
        .tools(Crig::Examples::AgentWithDefaultMaxTurns::TOOLS)
        .build,
    )

    result = Crig::Examples::ReasoningLoop.run_prompt(reasoning_agent)

    result.should eq("computed result")
    model.requests.first.tools.map(&.name).should contain("submit")
    model.requests.last.chat_history.first.rag_text.should eq(Crig::Examples::ReasoningLoop::PROMPT)
    model.requests.last.chat_history.last.content.to_a.first.as(Crig::Completion::UserContent).text.not_nil!.text.should contain("Step 1: Compute 15 + 25")
  end
end

describe Crig::Examples::ReasoningRoundtripTest, tags: %w[examples reasoning_roundtrip_test] do
  it "builds the provider helpers with reasoning params" do
    anthropic = Crig::Examples::ReasoningRoundtripTest.build_anthropic(Crig::Providers::Anthropic::Client.new("test-key"))
    gemini = Crig::Examples::ReasoningRoundtripTest.build_gemini(Crig::Providers::Gemini::Client.new("test-key"))
    openai = Crig::Examples::ReasoningRoundtripTest.build_openai(Crig::Providers::OpenAI::Client.new("test-key"))
    openrouter = Crig::Examples::ReasoningRoundtripTest.build_openrouter(Crig::Providers::OpenRouter::Client.new("test-key"))

    anthropic.additional_params.not_nil!["thinking"]["budget_tokens"].as_i.should eq(2048)
    gemini.additional_params.not_nil!["generationConfig"]["thinkingConfig"]["includeThoughts"].as_bool.should be_true
    openai.additional_params.not_nil!["reasoning"]["effort"].as_s.should eq("medium")
    openrouter.additional_params.not_nil!["include_reasoning"].as_bool.should be_true
  end

  it "round-trips reasoning content into turn two history" do
    model = FakeReasoningRoundtripModel.new
    agent = Crig::Examples::ReasoningRoundtripTest::TestAgent(FakeReasoningRoundtripModel).new(
      model,
      Crig::Examples::ReasoningRoundtripTest::PREAMBLE,
      JSON.parse(%({"reasoning":{"effort":"medium"}})),
    )

    turn_1, turn_2 = Crig::Examples::ReasoningRoundtripTest.run_test(agent)

    turn_1.reasoning_count.should eq(1)
    turn_1.reasoning_delta_count.should eq(2)
    turn_1.streamed_text.should eq("First answer.")
    turn_1.message_id.should eq("msg_turn_1")
    turn_2.streamed_text.should eq("Second answer with context.")

    second_request = model.requests[1]
    second_request.chat_history.size.should eq(3)
    assistant_message = second_request.chat_history.to_a[1]
    assistant_message.id.should eq("msg_turn_1")
    assistant_items = assistant_message.content.to_a.select(Crig::Completion::AssistantContent)
    assistant_items.any?(&.kind.reasoning?).should be_true
    assistant_items.any? { |item| item.text.try(&.text) == "First answer." }.should be_true
  end
end

describe Crig::Examples::TogetherStreaming, tags: %w[examples together_streaming] do
  it "builds the upstream together streaming agent helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    agent = Crig::Examples::TogetherStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Together::LLAMA_3_8B_CHAT_HF)
    agent.preamble.should eq(Crig::Examples::TogetherStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams together prompts through a provided agent" do
    model = FakeCompletionClientModel.new("meta-llama/Llama-3-8b-chat-hf")
    response = Crig::Examples::TogetherStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::TogetherStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:meta-llama/Llama-3-8b-chat-hf")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::TogetherStreaming::PROMPT)
  end
end

describe Crig::Examples::TogetherStreamingWithTools, tags: %w[examples together_streaming_with_tools] do
  it "builds the upstream together streaming-with-tools agent helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    agent = Crig::Examples::TogetherStreamingWithTools.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Together::LLAMA_2_70B_CHAT_TOGETHER)
    agent.preamble.should eq(Crig::Examples::TogetherStreamingWithTools::PREAMBLE)
    agent.max_tokens.should eq(1024_i64)
    agent.static_tools.map(&.name).should eq(%w[add subtract])
  end

  it "streams together tool prompts through a provided agent" do
    model = FakeCompletionClientModel.new("togethercomputer/llama-2-70b-chat")
    response = Crig::Examples::TogetherStreamingWithTools.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model)
        .tools(Crig::Examples::AgentWithTools.tools)
        .build
    )
    final_response = Crig::Examples::TogetherStreamingWithTools.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:togethercomputer/llama-2-70b-chat")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::TogetherStreamingWithTools::PROMPT)
  end
end

describe Crig::Examples::XAIStreaming, tags: %w[examples xai_streaming] do
  it "builds the upstream xai streaming agent helper" do
    client = Crig::Providers::XAI::Client.new("test-key")
    agent = Crig::Examples::XAIStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::XAI::GROK_3_MINI)
    agent.preamble.should eq(Crig::Examples::XAIStreaming::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "streams xai prompts through a provided agent" do
    model = FakeCompletionClientModel.new("grok-3-mini")
    response = Crig::Examples::XAIStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::XAIStreaming.stream_to_stdout(response, IO::Memory.new)

    final_response.output.should eq("chunk:grok-3-mini")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::XAIStreaming::PROMPT)
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

    final_response.output.should eq("chunk:llama-3.1")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::HuggingFaceStreaming::PROMPT)
  end
end

describe Crig::Examples::HuggingFaceSubproviders, tags: %w[examples huggingface_subproviders] do
  it "builds builder-based huggingface clients for the upstream subproviders" do
    models = Crig::Examples::HuggingFaceSubproviders::MODELS

    clients = models.map do |model, subprovider|
      {model, Crig::Examples::HuggingFaceSubproviders.build_client("test-key", subprovider)}
    end

    clients.map(&.[1].subprovider.to_s).should eq(
      ["together", "hf-inference/models", "sambanova", "fireworks-ai", "nebius"]
    )
  end

  it "builds the upstream partial and tools agent helpers" do
    model_name, subprovider = Crig::Examples::HuggingFaceSubproviders::MODELS.first
    client = Crig::Examples::HuggingFaceSubproviders.build_client("test-key", subprovider)
    builder = Crig::Examples::HuggingFaceSubproviders.build_partial_agent(client, model_name)
    agent = Crig::Examples::HuggingFaceSubproviders.build_tools_agent(client, model_name)

    builder.model.model.should eq(model_name)
    agent.model.model.should eq(model_name)
    agent.preamble.should eq(Crig::Examples::HuggingFaceSubproviders::PREAMBLE)
    agent.static_tools.map(&.name).sort.should eq(%w[add subtract])
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

describe Crig::Examples::GeminiExtractorWithRag, tags: %w[examples gemini_extractor_with_rag] do
  it "builds the upstream gemini rag extractor helper" do
    http_server = HTTP::Server.new do |context|
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print(%({
        "embeddings":[
          {"values":[0.1,0.2,0.3]},
          {"values":[0.2,0.3,0.4]},
          {"values":[0.3,0.4,0.5]},
          {"values":[0.4,0.5,0.6]},
          {"values":[0.5,0.6,0.7]},
          {"values":[0.6,0.7,0.8]},
          {"values":[0.7,0.8,0.9]},
          {"values":[0.8,0.9,1.0]},
          {"values":[0.9,1.0,1.1]}
        ]
      }))
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    extractor = Crig::Examples::GeminiExtractorWithRag.build_extractor(client)

    extractor.agent.model.model.should eq(Crig::Providers::Gemini::GEMINI_2_5_FLASH)
    extractor.agent.dynamic_context.size.should eq(1)
    extractor.agent.preamble.not_nil!.includes?(Crig::Examples::GeminiExtractorWithRag::PREAMBLE.strip).should be_true

    http_server.close
  end

  it "builds a rag index from embedded questionnaire documents" do
    index = Crig::Examples::GeminiExtractorWithRag.build_index(FakeEmbeddingsClientModel.new("embedding-001", 3))
    request = Crig::VectorSearchRequest.builder.query("technical skills").samples(1_u64).build

    index.top_n_results(request).should_not be_empty
  end
end

describe Crig::Examples::GeminiVideoUnderstanding, tags: %w[examples gemini_video_understanding] do
  it "builds the upstream gemini video-understanding agent helper" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    agent = Crig::Examples::GeminiVideoUnderstanding.build_agent(client)

    agent.model.model.should eq(Crig::Examples::GeminiVideoUnderstanding::MODEL)
    agent.preamble.should eq(Crig::Examples::GeminiVideoUnderstanding::PREAMBLE)
    agent.additional_params.not_nil!["generationConfig"]["topK"].as_i.should eq(1)
  end

  it "builds the upstream video prompt payload" do
    message = Crig::Examples::GeminiVideoUnderstanding.video_prompt

    message.role.user?.should be_true
    message.content.to_a.size.should eq(2)
    message.content.to_a.first.as(Crig::Completion::UserContent).text.not_nil!.text.should eq(
      Crig::Examples::GeminiVideoUnderstanding::PROMPT
    )
    video = message.content.to_a.last.as(Crig::Completion::UserContent).video.not_nil!
    video.data.kind.url?.should be_true
    video.data.try_into_inner.should eq(Crig::Examples::GeminiVideoUnderstanding::VIDEO_URL)
  end

  it "prompts a provided agent with video content" do
    model = FakeCompletionClientModel.new("gemini-video")
    response = Crig::Examples::GeminiVideoUnderstanding.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )

    response.should eq("completion:gemini-video")
  end
end

describe Crig::Examples::GeminiInteractionsAPI, tags: %w[examples gemini_interactions_api] do
  it "builds the upstream gemini interactions client and model helpers" do
    client = Crig::Examples::GeminiInteractionsAPI.build_client("test-key")
    model = Crig::Examples::GeminiInteractionsAPI.build_model(client)

    client.base_url.should eq(Crig::Providers::Gemini::GEMINI_API_BASE_URL)
    model.model.should eq(Crig::Examples::GeminiInteractionsAPI::BASIC_MODEL)
  end

  it "builds basic, follow-up, search, url, code, and tool requests" do
    model = Crig::Examples::GeminiInteractionsAPI.build_model(
      Crig::Providers::Gemini::InteractionsClient.new("test-key")
    )

    basic = Crig::Examples::GeminiInteractionsAPI.basic_request(model)
    follow = Crig::Examples::GeminiInteractionsAPI.follow_request(model, "interaction-123")
    search = Crig::Examples::GeminiInteractionsAPI.search_request(model)
    url = Crig::Examples::GeminiInteractionsAPI.url_request(model)
    code = Crig::Examples::GeminiInteractionsAPI.code_request(model)
    tool = Crig::Examples::GeminiInteractionsAPI.tool_request(model)

    basic.additional_params.not_nil!["store"].as_bool.should be_true
    follow.additional_params.not_nil!["previous_interaction_id"].as_s.should eq("interaction-123")
    search.additional_params.not_nil!["tools"].as_a.first["type"].as_s.should eq("google_search")
    url.additional_params.not_nil!["tools"].as_a.first["type"].as_s.should eq("url_context")
    code.additional_params.not_nil!["tools"].as_a.first["type"].as_s.should eq("code_execution")
    tool.tools.not_nil!.first.name.should eq("add")
    tool.tool_choice.not_nil!.kind.required?.should be_true
  end

  it "extracts text and tool calls from interaction completion choices" do
    choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many([
      Crig::Completion::AssistantContent.text("Hello"),
      Crig::Completion::AssistantContent.tool_call("call-1", "add", JSON.parse(%({"x":7,"y":11}))),
    ])

    Crig::Examples::GeminiInteractionsAPI.extract_text(choice).should eq("Hello")
    Crig::Examples::GeminiInteractionsAPI.first_tool_call(choice).not_nil!.function.name.should eq("add")
  end
end

describe Crig::Examples::GeminiDeepResearch, tags: %w[examples gemini_deep_research] do
  it "builds the upstream deep research params and request helpers" do
    client = Crig::Examples::GeminiDeepResearch.build_client("test-key")
    model = Crig::Examples::GeminiDeepResearch.build_model(client)
    params = Crig::Examples::GeminiDeepResearch.deep_research_params
    request = Crig::Examples::GeminiDeepResearch.build_request(model)

    params.agent.should eq(Crig::Examples::GeminiDeepResearch::DEEP_RESEARCH_AGENT)
    params.background.should be_true
    params.store.should be_true
    params.agent_config.not_nil!.kind.deep_research?.should be_true
    request.additional_params.not_nil!["agent"].as_s.should eq(Crig::Examples::GeminiDeepResearch::DEEP_RESEARCH_AGENT)
  end

  it "extracts text and tracks stream state across interaction events" do
    outputs = [
      Crig::Providers::Gemini::Interactions::Content.text(
        Crig::Providers::Gemini::Interactions::TextContent.new("Hello")
      ),
    ]
    state = Crig::Examples::GeminiDeepResearch::StreamState.new
    start_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"interaction.start",
      "interaction":{"id":"interaction-1","outputs":[]},
      "event_id":"event-1"
    }))
    delta_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.delta",
      "index":0,
      "delta":{"type":"text","text":"Hello"},
      "event_id":"event-2"
    }))
    complete_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"interaction.complete",
      "interaction":{"id":"interaction-1","outputs":[{"type":"text","text":"Hello"}]},
      "event_id":"event-3"
    }))

    Crig::Examples::GeminiDeepResearch.extract_text(outputs).should eq("Hello")
    state = Crig::Examples::GeminiDeepResearch.handle_stream_event(state, start_event)
    state.interaction_id.should eq("interaction-1")
    state = Crig::Examples::GeminiDeepResearch.handle_stream_event(state, delta_event)
    state.saw_text.should be_true
    state = Crig::Examples::GeminiDeepResearch.handle_stream_event(state, complete_event)
    state.is_complete.should be_true
    state.last_event_id.should eq("event-3")
  end
end

describe Crig::Examples::TogetherEmbeddings, tags: %w[examples together_embeddings] do
  it "builds the upstream together embeddings builder helper" do
    client = Crig::Providers::Together::Client.new("test-key")
    builder = Crig::Examples::TogetherEmbeddings.build_embeddings(client)

    builder.model.model.should eq(Crig::Examples::TogetherEmbeddings::MODEL)
    builder.documents.size.should eq(2)
    builder.documents.map { |entry| entry[0].message }.should eq(["Hello, world!", "Goodbye, world!"])
  end

  it "embeds the upstream together documents through a provided embeddings client" do
    builder = Crig::Examples::TogetherEmbeddings.build_embeddings(FakeEmbeddingsClient.new)
    results = builder.build

    results.map { |entry| entry[1].first.document }.should eq(
      [
        "#{Crig::Examples::TogetherEmbeddings::MODEL}:Hello, world!",
        "#{Crig::Examples::TogetherEmbeddings::MODEL}:Goodbye, world!",
      ]
    )
  end
end

describe Crig::Examples::MistralEmbeddings, tags: %w[examples mistral_embeddings] do
  it "builds the upstream mistral embeddings payloads" do
    model = FakeEmbeddingsClientModel.new("mistral-embed", 3)
    results = Crig::Examples::MistralEmbeddings.build_embeddings(model)

    results.map { |entry| entry[0].word }.should eq(%w[flurbo glarb-glarb linglingdong])
  end

  it "searches the upstream mistral embedding-backed store" do
    model = FakeEmbeddingsClientModel.new(Crig::Examples::MistralEmbeddings::MODEL, 3)
    results = Crig::Examples::MistralEmbeddings.search(model)

    results.should_not be_empty
  end
end

describe Crig::Examples::VoyageAIEmbeddings, tags: %w[examples voyageai_embeddings] do
  it "builds the upstream voyageai embeddings builder helper" do
    client = Crig::Providers::VoyageAI::Client.new("test-key")
    builder = Crig::Examples::VoyageAIEmbeddings.build_embeddings(client)

    builder.model.model.should eq(Crig::Examples::VoyageAIEmbeddings::MODEL)
    builder.documents.size.should eq(2)
    builder.documents.map { |entry| entry[0].message }.should eq(["Hello, world!", "Goodbye, world!"])
  end

  it "embeds the upstream voyageai documents through a provided embeddings client" do
    builder = Crig::Examples::VoyageAIEmbeddings.build_embeddings(FakeEmbeddingsClient.new)
    results = builder.build

    results.map { |entry| entry[1].first.document }.should eq(
      [
        "#{Crig::Examples::VoyageAIEmbeddings::MODEL}:Hello, world!",
        "#{Crig::Examples::VoyageAIEmbeddings::MODEL}:Goodbye, world!",
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

describe Crig::Examples::Transcription, tags: %w[examples transcription] do
  it "builds the upstream provider-specific transcription helpers" do
    openai = Crig::Examples::Transcription.whisper_model(Crig::Providers::OpenAI::Client.new("test-key"))
    gemini = Crig::Examples::Transcription.gemini_model(Crig::Providers::Gemini::Client.new("test-key"))
    azure = Crig::Examples::Transcription.azure_model(
      Crig::Providers::Azure::Client.new(
        Crig::Providers::Azure::AzureOpenAIAuth.api_key("test-key"),
        "https://example.invalid",
        "2024-06-01"
      )
    )
    groq = Crig::Examples::Transcription.groq_model(Crig::Providers::Groq::Client.new("test-key"))
    huggingface = Crig::Examples::Transcription.huggingface_model(Crig::Providers::HuggingFace::Client.new("test-key"))
    mistral = Crig::Examples::Transcription.mistral_model(Crig::Providers::Mistral::Client.new("test-key"))

    openai.model.should eq(Crig::Providers::OpenAI::WHISPER_1)
    gemini.model.should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    azure.model.should eq("whisper")
    groq.model.should eq(Crig::Providers::Groq::WHISPER_LARGE_V3)
    huggingface.model.should eq("whisper-large-v3")
    mistral.model.should eq(Crig::Providers::Mistral::VOXTRAL_MINI)
  end

  it "transcribes a file through a provided transcription model" do
    path = "#{Dir.current}/tmp_transcription_fixture.txt"
    File.write(path, "audio-bytes")
    begin
      text = Crig::Examples::Transcription.transcribe(FakeTranscriptionClientModel.new("whisper-1"), path)
      text.should eq("text:whisper-1")
    ensure
      File.delete(path) if File.exists?(path)
    end
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

describe Crig::Examples::OpenAIAgentCompletionsAPI, tags: %w[examples openai_agent_completions_api] do
  it "builds the upstream openai completions-api agent helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIAgentCompletionsAPI.build_agent(client)

    agent.preamble.should eq(Crig::Examples::OpenAIAgentCompletionsAPI::PREAMBLE)
    agent.model.should be_a(Crig::Providers::OpenAI::CompletionModel)
  end

  it "runs the completions-api prompt through a provided agent" do
    response = Crig::Examples::OpenAIAgentCompletionsAPI.run_prompt(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4o")).build
    )

    response.should eq("completion:gpt-4o")
  end
end

describe Crig::Examples::OpenAIAgentCompletionsApiOtel, tags: %w[examples openai_agent_completions_api_otel] do
  it "builds the upstream completions-api agent helper with telemetry span availability" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    agent = Crig::Examples::OpenAIAgentCompletionsApiOtel.build_agent(client)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.should eq(Crig::Examples::OpenAIAgentCompletionsApiOtel::PREAMBLE)
    Crig::Examples::OpenAIAgentCompletionsApiOtel.current_span.disabled?.should be_true
  end
end

describe Crig::Examples::ReqwestMiddleware, tags: %w[examples reqwest_middleware] do
  it "builds the upstream retrying transport helper" do
    inner = Crig::HttpClient::MockStreamingClient.new
    client = Crig::Examples::ReqwestMiddleware.build_http_client(inner)

    client.inner.should be_a(Crig::HttpClient::MockStreamingClient)
    client.policy.should be_a(Crig::HttpClient::ExponentialBackoff)
  end

  it "builds the upstream anthropic client and agent with a middleware-style transport" do
    transport = Crig::Examples::ReqwestMiddleware.build_http_client
    client = Crig::Examples::ReqwestMiddleware.build_client("anthropic-key", transport, "https://example.test")
    agent = Crig::Examples::ReqwestMiddleware.build_agent(client)

    client.http_client.should be_a(Crig::Providers::Anthropic::Client::WrappedTransport)
    agent.model.model.should eq(Crig::Examples::ReqwestMiddleware::MODEL)
    agent.preamble.should eq(Crig::Examples::ReqwestMiddleware::PREAMBLE)
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

describe Crig::Examples::HyperbolicAudioGeneration, tags: %w[examples hyperbolic_audio_generation] do
  it "builds the upstream hyperbolic audio generation model helper" do
    client = Crig::Providers::Hyperbolic::Client.new("test-key")
    model = Crig::Examples::HyperbolicAudioGeneration.build_model(client)

    model.language.should eq(Crig::Examples::HyperbolicAudioGeneration::DEFAULT_LANG)
  end

  it "builds and sends the upstream hyperbolic audio generation request helper" do
    model = FakeAudioGenerationClientModel.new("EN")
    response = Crig::Examples::HyperbolicAudioGeneration.generate(model)

    response.audio.should eq(Bytes[7_u8, 8_u8])
    model.last_request.not_nil!.text.should eq(Crig::Examples::HyperbolicAudioGeneration::DEFAULT_TEXT)
    model.last_request.not_nil!.voice.should eq(Crig::Examples::HyperbolicAudioGeneration::DEFAULT_VOICE)
  end

  it "writes generated audio bytes to an io" do
    io = IO::Memory.new
    response = Crig::AudioGenerationResponse(String).new(Bytes[1_u8, 2_u8, 3_u8], "raw-audio")

    Crig::Examples::HyperbolicAudioGeneration.write_audio(response, io)

    io.to_slice.should eq(Bytes[1_u8, 2_u8, 3_u8])
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

describe Crig::Examples::ImageOllama, tags: %w[examples image_ollama] do
  it "builds the upstream ollama image agent helper" do
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new, "http://127.0.0.1:11434")
    agent = Crig::Examples::ImageOllama.build_agent(client)

    agent.model.model.should eq(Crig::Examples::ImageOllama::MODEL)
    agent.preamble.should eq(Crig::Examples::ImageOllama::PREAMBLE)
    agent.temperature.should eq(0.5)
  end

  it "builds a jpeg image prompt from bytes" do
    image = Crig::Examples::ImageOllama.image_from_bytes(Bytes[1_u8, 2_u8, 3_u8])

    image.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
    image.data.kind.base64?.should be_true
    image.data.try_into_inner.should eq(Base64.strict_encode(Bytes[1_u8, 2_u8, 3_u8]))
  end

  it "prompts a provided agent with image content" do
    model = FakeCompletionClientModel.new("llava")
    response = Crig::Examples::ImageOllama.prompt_image(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build,
      Crig::Examples::ImageOllama.image_from_bytes(Bytes[1_u8, 2_u8, 3_u8])
    )

    response.should eq("completion:llava")
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

describe Crig::Examples::AgentWithEchochambers, tags: %w[examples agent_with_echochambers] do
  it "builds the upstream echochambers agent and chatbot helpers" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::AgentWithEchochambers.build_agent(client, "echo-key")
    chatbot = Crig::Examples::AgentWithEchochambers.build_chatbot(agent)

    agent.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    agent.preamble.not_nil!.should contain("EchoChambers rooms")
    agent.static_tools.map(&.name).sort.should eq(
      %w[get_agent_metrics get_history get_metrics_history get_room_metrics send_message]
    )
    typeof(chatbot).to_s.should contain("Crig::Integrations::ChatBot")
  end

  it "keeps the upstream tool definitions and sender shape" do
    send_message = Crig::Examples::AgentWithEchochambers::SendMessage.new("echo-key")
    definition = Crig.tool_definition(send_message)
    payload = send_message.call_typed(
      Crig::Examples::AgentWithEchochambers::SendMessageArgs.new(
        "Hello, world!",
        "general",
        Crig::Examples::AgentWithEchochambers::MessageSender.new("Rig_Assistant", "gpt-4")
      )
    )

    definition.name.should eq("send_message")
    payload["room_id"].as_s.should eq("general")
    payload["sender"]["username"].as_s.should eq("Rig_Assistant")
    payload["api_key_present"].as_bool.should be_true
  end
end

describe Crig::Examples::MultiAgent, tags: %w[examples multi_agent] do
  it "builds the translator agent and tool wrapper" do
    model = FakeCompletionClientModel.new("deepseek-chat")
    agent = Crig::Examples::MultiAgent.build_translator_agent(model)
    tool = Crig::Examples::MultiAgent::TranslatorTool(FakeCompletionClientModel).new(agent)

    agent.preamble.should eq(Crig::Examples::MultiAgent::TRANSLATOR_PREAMBLE)
    tool.name.should eq("translator")
    tool.call_typed(Crig::Examples::MultiAgent::TranslatorArgs.new("Hola")).should eq("completion:deepseek-chat")
  end

  it "builds the multi-agent system and chatbot helper" do
    model = FakeCompletionClientModel.new("deepseek-chat")
    agent = Crig::Examples::MultiAgent.build_multi_agent_system(model)
    chatbot = Crig::Examples::MultiAgent.build_chatbot(agent)

    agent.preamble.should eq(Crig::Examples::MultiAgent::SYSTEM_PREAMBLE)
    agent.static_tools.map(&.name).should eq(["translator"])
    chatbot.should be_a(Crig::Integrations::ChatBot(Crig::Integrations::AgentImpl(FakeCompletionClientModel)))
  end

  it "runs the upstream multi-agent helper through a provided agent" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("deepseek-chat")).build

    Crig::Examples::MultiAgent.run_prompt(agent, "Hola").should eq("completion:deepseek-chat")
  end
end

describe Crig::Examples::Debate, tags: %w[examples debate] do
  it "builds the upstream openai-vs-cohere debate helper" do
    openai_client = Crig::Providers::OpenAI::Client.new("test-key")
    cohere_client = Crig::Providers::Cohere::Client.new("test-key")
    debater = Crig::Examples::Debate.build_debater(openai_client, cohere_client)

    debater.agent_a.model.model.should eq(Crig::Providers::OpenAI::GPT_4)
    debater.agent_b.model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
    debater.agent_a.preamble.should eq(Crig::Examples::Debate::POSITION_A)
    debater.agent_b.preamble.should eq(Crig::Examples::Debate::POSITION_B)
  end

  it "runs debate rounds through provided agents and threads responses between them" do
    debater = Crig::Examples::Debate::Debater(FakeCompletionClientModel, FakeCompletionClientModel).new(
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4")).build,
      Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("command-r")).build,
    )

    exchanges = Crig::Examples::Debate.run_rounds(debater, 2)

    exchanges.size.should eq(2)
    exchanges.first.prompt_a.should eq("Plead your case!")
    exchanges.first.response_a.should eq("completion:gpt-4")
    exchanges.first.response_b.should eq("completion:command-r")
    exchanges.last.prompt_a.should eq("completion:command-r")
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

describe Crig::Examples::MultiTurnStreaming, tags: %w[examples multi_turn_streaming] do
  it "builds the upstream anthropic multi-turn streaming agent helper" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    agent = Crig::Examples::MultiTurnStreaming.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    agent.preamble.should eq(Crig::Examples::MultiTurnStreaming::PREAMBLE)
    agent.static_tools.map(&.name).should eq(%w[add subtract multiply divide])
  end

  it "streams prompts through the multi-turn helper" do
    model = FakeCompletionClientModel.new("claude-3-5-sonnet")
    result = Crig::Examples::MultiTurnStreaming.run_stream(
      Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    )
    final_response = Crig::Examples::MultiTurnStreaming.stream_to_stdout(result, IO::Memory.new)

    final_response.output.should eq("chunk:claude-3-5-sonnet")
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
end

describe Crig::Examples::Extractor, tags: %w[examples extractor] do
  # FIXME: Crystal 1.20.2 compiler bug triggers codegen crash in probe build
  pending "builds the upstream extractor helper for openai responses models" do
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

    # Check that the extractor has an agent with the upstream output-schema contract
    extractor.agent.should_not be_nil
    extractor.agent.output_schema.should_not be_nil
    extractor.agent.static_tools.any? { |tool| tool.name == "submit" }.should be_false
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

describe Crig::Examples::RagDynamicTools, tags: %w[examples rag_dynamic_tools] do
  it "builds the upstream dynamic toolset and schemas" do
    toolset = Crig::Examples::RagDynamicTools.toolset

    toolset.contains("add").should be_true
    toolset.contains("subtract").should be_true
    toolset.get_tool_definitions.map(&.name).sort.should eq(%w[add subtract])
  end

  it "builds a dynamic tool index from embedded tool schemas" do
    model = FakeEmbeddingsClientModel.new("text-embedding-ada-002", 3)
    index = Crig::Examples::RagDynamicTools.build_index(model)
    request = Crig::VectorSearchRequest.builder.query("subtract values").samples(1_u64).build

    index.top_n_results(request).should_not be_empty
  end

  it "builds the upstream rag dynamic-tools agent helper" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[
            {"object":"embedding","embedding":[0.1,0.2,0.3],"index":0},
            {"object":"embedding","embedding":[0.3,0.2,0.1],"index":1}
          ],
          "model":"text-embedding-ada-002",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    agent = Crig::Examples::RagDynamicTools.build_agent(client)

    agent.preamble.should eq("You are a calculator here to help the user perform arithmetic operations.")
    agent.dynamic_tools.size.should eq(1)
    server.requests.first["model"].as_s.should eq(Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002)

    http_server.close
  end

  it "accepts the upstream ToolSet-shaped dynamic_tools builder path" do
    model = FakeEmbeddingsClientModel.new("text-embedding-ada-002", 3)
    index = Crig::Examples::RagDynamicTools.build_index(model)
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("gpt-4"))
      .dynamic_tools(1, index, Crig::Examples::RagDynamicTools.toolset)
      .build

    agent.dynamic_tools.size.should eq(1)
    agent.dynamic_tools.first.tools.map(&.name).sort.should eq(%w[add subtract])
  end
end

describe Crig::Examples::RagDynamicToolsMultiTurn, tags: %w[examples rag_dynamic_tools_multi_turn] do
  it "builds the upstream multi-turn dynamic tool rag agent helper" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"
      require "./examples/rag_dynamic_tools_multi_turn"

      class FakeOpenAIEmbeddingServer
        getter requests = [] of JSON::Any

        def http_server : HTTP::Server
          HTTP::Server.new do |context|
            body = context.request.body.try(&.gets_to_end) || ""
            @requests << JSON.parse(body)
            context.response.content_type = "application/json"
            context.response.print(%({
              "object":"list",
              "data":[
                {"object":"embedding","embedding":[0.1,0.2,0.3],"index":0},
                {"object":"embedding","embedding":[0.3,0.2,0.1],"index":1}
              ],
              "model":"text-embedding-ada-002",
              "usage":{"prompt_tokens":2,"total_tokens":2}
            }))
          end
        end
      end

      server = FakeOpenAIEmbeddingServer.new
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
      agent = Crig::Examples::RagDynamicToolsMultiTurn.build_agent(client)
      dynamic_source = agent.dynamic_tools.first

      puts(JSON.build do |json|
        json.object do
          json.field "model", agent.model.model
          json.field "preamble", agent.preamble
          json.field "sample", dynamic_source.sample
          json.field "tool_count", dynamic_source.tools.size
          json.field "embedding_model", server.requests.first["model"].as_s
        end
      end)

      http_server.close
    CRYSTAL

    result["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4)
    result["preamble"].as_s.should eq(Crig::Examples::RagDynamicToolsMultiTurn::PREAMBLE)
    result["sample"].as_i.should eq(2)
    result["tool_count"].as_i.should eq(2)
    result["embedding_model"].as_s.should eq(Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002)
  end

  it "runs the multi-turn dynamic tool helper through a provided agent" do
    model = FakeCompletionClientModel.new("rag-dynamic-tools-multi-turn")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build

    Crig::Examples::RagDynamicToolsMultiTurn.run_prompt(agent).should eq("completion:rag-dynamic-tools-multi-turn")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::RagDynamicToolsMultiTurn::PROMPT)
  end
end

describe Crig::Examples::CalculatorChatbot, tags: %w[examples calculator_chatbot] do
  it "builds the upstream calculator rag agent helper" do
    result = run_crig_probe <<-'CRYSTAL'
      require "./src/crig"
      require "./examples/calculator_chatbot"

      class FakeOpenAIEmbeddingServer
        getter requests = [] of JSON::Any

        def http_server : HTTP::Server
          HTTP::Server.new do |context|
            body = context.request.body.try(&.gets_to_end) || ""
            @requests << JSON.parse(body)
            context.response.content_type = "application/json"
            context.response.print(%({
              "object":"list",
              "data":[
                {"object":"embedding","embedding":[0.1,0.2,0.3],"index":0},
                {"object":"embedding","embedding":[0.3,0.2,0.1],"index":1},
                {"object":"embedding","embedding":[0.2,0.1,0.3],"index":2},
                {"object":"embedding","embedding":[0.4,0.1,0.2],"index":3}
              ],
              "model":"text-embedding-ada-002",
              "usage":{"prompt_tokens":4,"total_tokens":4}
            }))
          end
        end
      end

      server = FakeOpenAIEmbeddingServer.new
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
      agent = Crig::Examples::CalculatorChatbot.build_agent(client)
      chatbot = Crig::Examples::CalculatorChatbot.build_chatbot(agent)
      dynamic_source = agent.dynamic_tools.first

      puts(JSON.build do |json|
        json.object do
          json.field "preamble", agent.preamble
          json.field "sample", dynamic_source.sample
          json.field "tool_count", dynamic_source.tools.size
          json.field "embedding_model", server.requests.first["model"].as_s
          json.field "chatbot_class", typeof(chatbot).to_s
        end
      end)

      http_server.close
    CRYSTAL

    result["preamble"].as_s.should eq(Crig::Examples::CalculatorChatbot::PREAMBLE)
    result["sample"].as_i.should eq(2)
    result["tool_count"].as_i.should eq(4)
    result["embedding_model"].as_s.should eq(Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002)
    result["chatbot_class"].as_s.should contain("Crig::Integrations::ChatBot")
  end

  it "builds the upstream calculator chatbot wrapper for an agent" do
    agent = Crig::AgentBuilder(FakeCliChatbotCompletionModel).new(FakeCliChatbotCompletionModel.new).build
    chatbot = Crig::Examples::CalculatorChatbot.build_chatbot(agent)
    input = IO::Memory.new("calculate 3 + 4\nexit\n")
    output = IO::Memory.new

    chatbot.run(input, output)

    output.to_s.should contain("agent reply")
  end
end

describe Crig::Examples::CustomVectorStore, tags: %w[examples custom_vector_store] do
  it "builds the upstream custom vector store with embedded sample documents" do
    model = FakeEmbeddingsClientModel.new("text-embedding-ada-002", 3)
    store = Crig::Examples::CustomVectorStore.build_store(model)

    store.key.should eq("test_vectors")
    store.embedding_model.should eq(model)
    store.top_n_results(Crig::Examples::CustomVectorStore.request).size.should eq(2)
  end

  it "returns typed documents and ids through the custom vector store search helpers" do
    model = FakeEmbeddingsClientModel.new("text-embedding-ada-002", 3)
    store = Crig::Examples::CustomVectorStore.build_store(model)

    results = Crig::Examples::CustomVectorStore.search(store)
    ids = Crig::Examples::CustomVectorStore.search_ids(store)

    results.size.should eq(2)
    ids.size.should eq(2)
    results.first[2].title.should contain("Programming")
  end
end

describe Crig::Examples::ComplexAgenticLoopClaude, tags: %w[examples complex_agentic_loop_claude] do
  it "builds the upstream anthropic beta client and knowledge index helpers" do
    client = Crig::Examples::ComplexAgenticLoopClaude.build_anthropic_client("test-key", "https://example.test")
    index = Crig::Examples::ComplexAgenticLoopClaude.build_vector_index(FakeEmbeddingModel.new)

    client.anthropic_betas.should eq([Crig::Examples::ComplexAgenticLoopClaude::ANTHROPIC_BETA])
    Crig::Examples::ComplexAgenticLoopClaude.knowledge_entries.size.should eq(4)
    index.top_n_results(Crig::VectorSearchRequest.builder.query("climate").samples(1_u64).build).should_not be_empty
  end

  it "builds the upstream specialist agents and orchestrator tool loop" do
    client = Crig::Examples::ComplexAgenticLoopClaude.build_anthropic_client("test-key", "https://example.test")
    index = Crig::Examples::ComplexAgenticLoopClaude.build_vector_index(FakeEmbeddingModel.new)
    research = Crig::Examples::ComplexAgenticLoopClaude.build_research_agent(client)
    analysis = Crig::Examples::ComplexAgenticLoopClaude.build_analysis_agent(client)
    recommendation = Crig::Examples::ComplexAgenticLoopClaude.build_recommendation_agent(client)
    orchestrator = Crig::Examples::ComplexAgenticLoopClaude.build_orchestrator_agent(client, index)

    research.name.should eq("research_agent")
    analysis.name.should eq("data_analysis_agent")
    recommendation.name.should eq("recommendation_agent")
    orchestrator.name.should eq("orchestrator_agent")
    orchestrator.static_tools.map(&.name).should contain("think")
    orchestrator.static_tools.map(&.name).should contain("search_vector_store")
  end

  it "runs the upstream multi-turn prompt helper through a provided agent" do
    model = FakeCompletionClientModel.new("claude-3-7-sonnet")
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(model).build
    history = [] of Crig::Completion::Message

    Crig::Examples::ComplexAgenticLoopClaude.run_prompt(agent, history: history).should eq("completion:claude-3-7-sonnet")
    model.last_request.not_nil!.chat_history.last.rag_text.should eq(Crig::Examples::ComplexAgenticLoopClaude::QUERY)
  end
end

describe Crig::Examples::DiscordBot, tags: %w[examples discord_bot] do
  it "builds the upstream discord agent and bot helpers" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    agent = Crig::Examples::DiscordBot.build_agent(client)
    bot = Crig::Examples::DiscordBot.build_bot(agent, "discord-token")

    agent.model.model.should eq(Crig::Examples::DiscordBot::MODEL)
    agent.preamble.should eq(Crig::Examples::DiscordBot::PREAMBLE)
    bot.token.should eq("discord-token")
  end

  it "builds the upstream discord bot helper from env" do
    original = ENV["DISCORD_BOT_TOKEN"]?
    ENV["DISCORD_BOT_TOKEN"] = "env-discord-token"

    begin
      client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
      agent = Crig::Examples::DiscordBot.build_agent(client)

      Crig::Examples::DiscordBot.build_bot_from_env(agent).token.should eq("env-discord-token")
    ensure
      if original
        ENV["DISCORD_BOT_TOKEN"] = original
      else
        ENV.delete("DISCORD_BOT_TOKEN")
      end
    end
  end
end

describe Crig::Examples::PdfAgent, tags: %w[examples pdf_agent] do
  it "loads and chunks the upstream pdf fixture" do
    chunks = Crig::Examples::PdfAgent.load_pdf("vendor/rig/tests/data/pages.pdf")

    chunks.should_not be_empty
    chunks.any? { |chunk| !chunk.empty? }.should be_true
  end

  it "builds the upstream ollama client helper" do
    client = Crig::Examples::PdfAgent.build_client

    client.base_url.should eq(Crig::Examples::PdfAgent::BASE_URL)
  end

  it "builds embeddings and a vector index from pdf chunks" do
    chunks = ["first chunk", "second chunk"]
    model = FakeEmbeddingsClientModel.new("bge-m3", 3)
    embeddings = Crig::Examples::PdfAgent.build_embeddings(model, chunks)
    index = Crig::Examples::PdfAgent.build_index(model, chunks)

    embeddings.size.should eq(2)
    embeddings.first[0].content.should eq("first chunk")
    index.top_n_results(Crig::VectorSearchRequest.builder.query("first").samples(1_u64).build).should_not be_empty
  end

  it "builds the upstream rag agent and chatbot helpers" do
    model = FakeEmbeddingsClientModel.new("bge-m3", 3)
    index = Crig::Examples::PdfAgent.build_index(model, ["pdf chunk"])
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new, Crig::Examples::PdfAgent::BASE_URL)
    agent = Crig::Examples::PdfAgent.build_agent(client, index)
    chatbot = Crig::Examples::PdfAgent.build_chatbot(agent)

    agent.model.model.should eq(Crig::Examples::PdfAgent::COMPLETION_MODEL)
    agent.preamble.should eq(Crig::Examples::PdfAgent::PREAMBLE)
    agent.dynamic_context.size.should eq(1)
    typeof(chatbot).to_s.should contain("Crig::Integrations::ChatBot")
  end
end

describe Crig::Examples::RagOllama, tags: %w[examples rag_ollama] do
  it "builds the upstream ollama client helper" do
    client = Crig::Examples::RagOllama.build_client

    client.base_url.should eq(Crig::Examples::RagOllama::BASE_URL)
  end

  it "builds the upstream ollama rag store from embedded word definitions" do
    store = Crig::Examples::RagOllama.build_store(FakeEmbeddingsClientModel.new("nomic-embed-text", 3))

    store.len.should eq(3)
    store.get_document("doc1", Crig::Examples::RagOllama::WordDefinition).not_nil!.word.should eq("glarb-glarb")
  end

  it "builds the upstream ollama rag agent helper" do
    index = Crig::Examples::RagOllama.build_store(FakeEmbeddingsClientModel.new("nomic-embed-text", 3))
      .index(FakeEmbeddingsClientModel.new("nomic-embed-text", 3))
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new, Crig::Examples::RagOllama::BASE_URL)
    agent = Crig::Examples::RagOllama.build_agent(client, index)

    agent.model.model.should eq(Crig::Examples::RagOllama::COMPLETION_MODEL)
    agent.preamble.should eq(Crig::Examples::RagOllama::PREAMBLE)
    agent.dynamic_context.size.should eq(1)
  end

  it "runs the upstream ollama rag prompt through a provided agent" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("qwen2.5:14b")).build

    Crig::Examples::RagOllama.run_prompt(agent).should eq("completion:qwen2.5:14b")
  end
end

describe Crig::Examples::SentimentClassifier, tags: %w[examples sentiment_classifier] do
  it "builds the upstream openai sentiment extractor helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    extractor = Crig::Examples::SentimentClassifier.build_extractor(client)

    extractor.agent.output_schema.should_not be_nil
    extractor.agent.static_tools.any? { |tool| tool.name == "submit" }.should be_false
  end

  it "keeps the upstream sentiment model shape" do
    sentiment = Crig::Examples::SentimentClassifier::DocumentSentiment.new(
      Crig::Examples::SentimentClassifier::Sentiment::Positive
    )

    sentiment.sentiment.positive?.should be_true
  end
end

describe Crig::Examples::VectorSearchCohere, tags: %w[examples vector_search_cohere] do
  it "builds the upstream cohere vector search store helpers" do
    document_model = FakeEmbeddingsClientModel.new("doc-model", 3)
    search_model = FakeEmbeddingsClientModel.new("query-model", 3)
    built_document_model, built_search_model, store = Crig::Examples::VectorSearchCohere.build_store(document_model, search_model)

    built_document_model.should eq(document_model)
    built_search_model.should eq(search_model)
    store.len.should eq(3)
  end

  it "returns top-n word matches through the cohere vector search helper" do
    document_model = FakeEmbeddingsClientModel.new("doc-model", 3)
    search_model = FakeEmbeddingsClientModel.new("query-model", 3)
    _, _, store = Crig::Examples::VectorSearchCohere.build_store(document_model, search_model)
    request = Crig::VectorSearchRequest.builder.query("Which instrument is found in the Nebulon Mountain Ranges?").samples(1_u64).build

    results = store.index(search_model).top_n(request, Crig::Examples::VectorSearch::WordDefinition).map { |score, id, doc| {score, id, doc.word} }

    results.should_not be_empty
    %w[flurbo glarb-glarb linglingdong].should contain(results.first[2])
  end
end

describe Crig::Examples::VectorSearchOllama, tags: %w[examples vector_search_ollama] do
  it "builds the upstream ollama client helper" do
    client = Crig::Examples::VectorSearchOllama.build_client

    client.base_url.should eq(Crig::Examples::VectorSearchOllama::BASE_URL)
  end

  it "builds the upstream ollama vector search store helpers" do
    embedding_model, store = Crig::Examples::VectorSearchOllama.build_store(FakeEmbeddingsClientModel.new("nomic-embed-text", 3))

    embedding_model.name.should eq("nomic-embed-text")
    store.len.should eq(3)
  end

  it "returns word and id matches through the ollama vector search helper" do
    embedding_model, store = Crig::Examples::VectorSearchOllama.build_store(FakeEmbeddingsClientModel.new("nomic-embed-text", 3))
    request = Crig::VectorSearchRequest.builder.query(Crig::Examples::VectorSearch.default_query).samples(1_u64).build
    index = store.index(embedding_model)

    results = index.top_n(request, Crig::Examples::VectorSearch::WordDefinition).map { |score, id, doc| {score, id, doc.word} }
    ids = index.top_n_ids(request)

    results.should_not be_empty
    ids.should_not be_empty
  end
end

describe Crig::Examples::PerplexityAgent, tags: %w[examples perplexity_agent] do
  it "builds the upstream perplexity agent helper" do
    client = Crig::Providers::Perplexity::Client.new("test-key")
    agent = Crig::Examples::PerplexityAgent.build_agent(client)

    agent.model.model.should eq(Crig::Providers::Perplexity::SONAR)
    agent.preamble.should eq(Crig::Examples::PerplexityAgent::PREAMBLE)
    agent.temperature.should eq(0.5)
    agent.additional_params.not_nil!["return_related_questions"].as_bool.should be_true
    agent.additional_params.not_nil!["return_images"].as_bool.should be_true
  end

  it "runs the upstream perplexity prompt helper through a provided agent" do
    agent = Crig::AgentBuilder(FakeCompletionClientModel).new(FakeCompletionClientModel.new("sonar")).build

    Crig::Examples::PerplexityAgent.run_prompt(agent).should eq("completion:sonar")
  end
end

describe Crig::Examples::RMCP::StructRequest do
  it "deserializes the Rust example request shape" do
    request = Crig::Examples::RMCP::StructRequest.from_json(%({"a":2,"b":5}))
    request.a.should eq(2)
    request.b.should eq(5)
  end
end

describe Crig::Examples::RMCP::StreamableServer do
  it "serves the counter sum tool over streamable HTTP to a connected client" do
    server = Crig::Examples::RMCP::StreamableServer.from_counter
    http = server.http_server
    address = http.bind_unused_port("127.0.0.1")
    spawn { http.listen }
    Fiber.yield

    begin
      uri = "http://127.0.0.1:#{address.port}/mcp"
      client = MCP::Client::Client.new(
        client_info: MCP::Protocol::Implementation.new("crig-test", "0.1.0"),
        client_options: MCP::Client::ClientOptions.new(
          capabilities: MCP::Protocol::ClientCapabilities.new
        )
      )
      client.connect(MCP::Client::StreamableHttpClientTransport.from_uri(uri))

      tools = client.list_tools.not_nil!.tools
      tools.map(&.name).should contain("sum")

      result = client.call_tool(
        "sum",
        {"a" => JSON::Any.new(3_i64), "b" => JSON::Any.new(5_i64)}
      ).as(MCP::Protocol::CallToolResult)

      text = result.content.first.as(MCP::Protocol::TextContentBlock).text
      text.should eq("8")
    ensure
      http.close
    end
  end
end
