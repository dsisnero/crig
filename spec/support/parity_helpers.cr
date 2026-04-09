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

class FakeXAIAudioGenerationServer
  getter requests : Array(JSON::Any)

  def initialize(&@handler : JSON::Any -> NamedTuple(content_type: String, body: String, status_code: Int32?))
    @requests = [] of JSON::Any
  end

  def http_server : HTTP::Server
    HTTP::Server.new do |context|
      unless context.request.method == "POST" && context.request.path == "/v1/tts"
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

class FakeXAIImageGenerationServer
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

struct DummyStringifiedJSON
  include JSON::Serializable

  @[JSON::Field(converter: Crig::JSONUtils::StringifiedJSON)]
  getter data : JSON::Any

  def initialize(@data : JSON::Any)
  end
end

struct DummyMaybeStringifiedJSON
  include JSON::Serializable

  @[JSON::Field(ignore_serialize: true)]
  getter data : JSON::Any

  def initialize(@data : JSON::Any)
  end

  def self.new(pull : JSON::PullParser)
    data = JSON.parse(%({}))

    pull.read_begin_object
    until pull.kind.end_object?
      key = pull.read_object_key
      case key
      when "data"
        data = Crig::JSONUtils::StringifiedJSON.deserialize_maybe_stringified(pull)
      else
        pull.skip
      end
    end
    pull.read_end_object

    new(data)
  end
end
