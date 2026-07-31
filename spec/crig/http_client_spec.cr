require "../spec_helper"
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
    source = Crig::HttpClient::GenericEventSource.new(client, request)

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
    source = Crig::HttpClient::GenericEventSource.new(client, request)

    initial_error = source.receive?.not_nil!
    initial_error.error.not_nil!.kind.stream_ended?.should be_true

    open = source.receive?.not_nil!.unwrap
    open.kind.open?.should be_true

    connected = source.receive?.not_nil!.unwrap
    connected.kind.message?.should be_true
    connected.message.not_nil!.data.should eq("connected")
    source.receive?.should be_nil
  end

  it "resets the retry cycle after opening when a mid-stream error occurs" do
    client = OpenErrorThenReconnectSseClient.new
    request = HTTP::Request.new("GET", "/events")
    retry_policy = Crig::HttpClient::ExponentialBackoff.new(
      1.millisecond,
      2.0,
      10.milliseconds,
      1,
    )
    source = Crig::HttpClient::GenericEventSource.new(client, request, retry_policy)

    initial_error = source.receive?.not_nil!
    initial_error.error.not_nil!.kind.stream_ended?.should be_true

    first_open = source.receive?.not_nil!.unwrap
    first_open.kind.open?.should be_true

    first = source.receive?.not_nil!.unwrap
    first.kind.message?.should be_true
    first.message.not_nil!.data.should eq("first")

    mid_stream_error = source.receive?.not_nil!
    mid_stream_error.error.not_nil!.kind.stream_ended?.should be_true

    second_open = source.receive?.not_nil!.unwrap
    second_open.kind.open?.should be_true

    recovered = source.receive?.not_nil!.unwrap
    recovered.kind.message?.should be_true
    recovered.message.not_nil!.data.should eq("recovered")
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
