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

# Tool with a custom name for disambiguation in multi-tool tests.
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
