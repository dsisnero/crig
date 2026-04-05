require "../src/crig"

module Crig::Examples::ReqwestMiddleware
  PREAMBLE = "You are a helpful assistant."
  MODEL    = "claude-sonnet-4-20250514"

  class RetryHttpClient(T)
    include Crig::HttpClient::HttpClientExt

    getter inner : T
    getter policy : Crig::HttpClient::RetryPolicy

    def initialize(
      @inner : T,
      @policy : Crig::HttpClient::RetryPolicy = Crig::HttpClient::ExponentialBackoff.new(300.milliseconds, 2.0, 5.seconds, 5),
    )
    end

    def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
      retry_call { @inner.send(req, body) }
    end

    def send_multipart(req : HTTP::Request, form : Crig::HttpClient::MultipartForm) : Crig::HttpClient::Result(Crig::HttpClient::Response(Crig::HttpClient::LazyBytes), Crig::HttpClient::Error)
      retry_call { @inner.send_multipart(req, form) }
    end

    def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Crig::HttpClient::Result(Crig::HttpClient::StreamingResponse, Crig::HttpClient::Error)
      retry_call { @inner.send_streaming(req, body) }
    end

    private def retry_call(&block)
      retry_state = nil.as({Int32, Time::Span}?)

      loop do
        result = yield
        return result unless error = result.error
        return result unless delay = @policy.retry(error, retry_state)

        retry_num = retry_state ? retry_state.not_nil![0] + 1 : 1
        retry_state = {retry_num, delay}
      end
    end
  end

  def self.build_http_client(
    inner : T = Crig::HttpClient::MockStreamingClient.new,
    policy : Crig::HttpClient::RetryPolicy = Crig::HttpClient::ExponentialBackoff.new(300.milliseconds, 2.0, 5.seconds, 5),
  ) forall T
    RetryHttpClient(T).new(inner, policy)
  end

  def self.build_client(
    api_key : String,
    http_client : Crig::HttpClient::HttpClientExt,
    base_url : String = Crig::Providers::Anthropic::ANTHROPIC_API_BASE_URL,
  ) : Crig::Providers::Anthropic::Client
    Crig::Providers::Anthropic::Client.builder
      .http_client(http_client)
      .api_key(api_key)
      .base_url(base_url)
      .build
  end

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end
end
