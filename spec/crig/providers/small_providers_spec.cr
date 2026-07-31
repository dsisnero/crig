require "../../spec_helper"
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

    # Anthropic-compatible client
    anthropic = Crig::Providers::Moonshot::AnthropicClientBuilder.new("dummy-key").build
    anthropic.inner.api_key.token.should eq("dummy-key")
    anthropic.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::Moonshot::MOONSHOT_ANTHROPIC_BASE_URL))
  end

  it "supports global and china entrypoints" do
    global = Crig::Providers::Moonshot::Client.builder.api_key("key").global.build
    china = Crig::Providers::Moonshot::Client.builder.api_key("key").china.build

    global.base_url.should eq(Crig::Providers::Moonshot::MOONSHOT_GLOBAL_API_BASE_URL)
    china.base_url.should eq(Crig::Providers::Moonshot::MOONSHOT_API_BASE_URL)

    # Anthropic entrypoints
    anthropic_global = Crig::Providers::Moonshot::AnthropicClientBuilder.new("key").global.build
    anthropic_china = Crig::Providers::Moonshot::AnthropicClientBuilder.new("key").china.build

    anthropic_global.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::Moonshot::MOONSHOT_ANTHROPIC_BASE_URL))
    anthropic_china.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::Moonshot::MOONSHOT_CHINA_ANTHROPIC_BASE_URL))
  end

  it "normalizes openai bases to anthropic bases" do
    Crig::Providers::Moonshot.normalize_anthropic_base_url(Crig::Providers::Moonshot::MOONSHOT_GLOBAL_API_BASE_URL)
      .should eq("https://api.moonshot.ai/anthropic")
    Crig::Providers::Moonshot.normalize_anthropic_base_url(Crig::Providers::Moonshot::MOONSHOT_API_BASE_URL)
      .should eq("https://api.moonshot.cn/anthropic")
    Crig::Providers::Moonshot.normalize_anthropic_base_url("https://proxy.example.com/v1")
      .should eq("https://proxy.example.com/anthropic")
  end

  it "normalize preserves existing anthropic base" do
    Crig::Providers::Moonshot.normalize_anthropic_base_url("https://proxy.example.com/anthropic")
      .should eq("https://proxy.example.com/anthropic")
  end

  it "anthropic primary override wins" do
    result = Crig::Providers::Moonshot.resolve_anthropic_base_override(
      "https://primary.example.com/anthropic",
      "https://api.moonshot.cn/v1",
    )
    result.should eq("https://primary.example.com/anthropic")
  end

  it "coerces required tool_choice to auto with steering message" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .model("kimi-k2.5")
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    payload = Crig::Providers::Moonshot::MoonshotCompletionRequest.from_request("kimi-k2.5", request).to_json_value

    payload["tool_choice"].as_s.should eq("auto")
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
          .tool_choice(Crig::Completion::ToolChoice.specific(["lookup"]))
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

describe Crig::Providers::XiaomiMimo do
  it "supports client initialization and builders" do
    client = Crig::Providers::XiaomiMimo::Client.new("dummy-key")
    built = Crig::Providers::XiaomiMimo::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    built.api_key.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::XiaomiMimo::XIAOMI_MIMO_API_BASE_URL)
  end

  it "builds xiaomi requests and rejects specific tool choice mode" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be concise")
      .tool(Crig::Completion::ToolDefinition.new("lookup", "Lookup", JSON.parse(%({"type":"object"}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    payload = Crig::Providers::XiaomiMimo::XiaomiMimoCompletionRequest.from_request(
      Crig::Providers::XiaomiMimo::MIMO_V2_PRO,
      request
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::XiaomiMimo::MIMO_V2_PRO)
    payload["messages"].as_a.first["role"].as_s.should eq("system")
    payload["tools"].as_a.first["function"]["name"].as_s.should eq("lookup")
    payload["tool_choice"].as_s.should eq("required")

    expect_raises(Crig::Completion::CompletionError, /Provider doesn't support only using specific tools/) do
      Crig::Providers::XiaomiMimo::XiaomiMimoCompletionRequest.from_request(
        Crig::Providers::XiaomiMimo::MIMO_V2_PRO,
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

    client = Crig::Providers::XiaomiMimo::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::XiaomiMimo::MIMO_V2_PRO)
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

  it "supports anthropic client initialization" do
    anthropic = Crig::Providers::XiaomiMimo::AnthropicClientBuilder.new("dummy-key").build
    anthropic.inner.api_key.token.should eq("dummy-key")
    anthropic.inner.base_url.should eq(
      Crig::Providers::Anthropic.normalize_anthropic_base_url(
        Crig::Providers::XiaomiMimo::ANTHROPIC_API_BASE_URL
      )
    )
  end

  it "normalizes openai bases to anthropic bases" do
    Crig::Providers::XiaomiMimo.normalize_anthropic_base_url(
      Crig::Providers::XiaomiMimo::XIAOMI_MIMO_API_BASE_URL
    ).should eq(Crig::Providers::XiaomiMimo::ANTHROPIC_API_BASE_URL)

    Crig::Providers::XiaomiMimo.normalize_anthropic_base_url(
      "https://proxy.example.com/v1"
    ).should eq("https://proxy.example.com/anthropic/v1")
  end

  it "normalize preserves existing anthropic base" do
    Crig::Providers::XiaomiMimo.normalize_anthropic_base_url(
      Crig::Providers::XiaomiMimo::ANTHROPIC_API_BASE_URL
    ).should eq(Crig::Providers::XiaomiMimo::ANTHROPIC_API_BASE_URL)
  end

  it "anthropic primary override wins" do
    result = Crig::Providers::XiaomiMimo.resolve_anthropic_base_override(
      "https://primary.example.com/anthropic/v1",
      Crig::Providers::XiaomiMimo::XIAOMI_MIMO_API_BASE_URL,
    )
    result.should eq("https://primary.example.com/anthropic/v1")
  end
end

describe Crig::Providers::MiniMax do
  it "supports client initialization and builders" do
    client = Crig::Providers::MiniMax::Client.new("dummy-key")
    built = Crig::Providers::MiniMax::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    built.api_key.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::MiniMax::GLOBAL_API_BASE_URL)

    # Anthropic-compatible client
    anthropic = Crig::Providers::MiniMax::AnthropicClientBuilder.new("dummy-key").build
    anthropic.inner.api_key.token.should eq("dummy-key")
    anthropic.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::MiniMax::GLOBAL_ANTHROPIC_API_BASE_URL))
  end

  it "supports global and china entrypoints" do
    global = Crig::Providers::MiniMax::Client.builder.api_key("key").global.build
    china = Crig::Providers::MiniMax::Client.builder.api_key("key").china.build

    global.base_url.should eq(Crig::Providers::MiniMax::GLOBAL_API_BASE_URL)
    china.base_url.should eq(Crig::Providers::MiniMax::CHINA_API_BASE_URL)

    # Anthropic entrypoints
    anthropic_global = Crig::Providers::MiniMax::AnthropicClientBuilder.new("key").global.build
    anthropic_china = Crig::Providers::MiniMax::AnthropicClientBuilder.new("key").china.build

    anthropic_global.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::MiniMax::GLOBAL_ANTHROPIC_API_BASE_URL))
    anthropic_china.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::MiniMax::CHINA_ANTHROPIC_API_BASE_URL))
  end

  it "normalizes openai bases to anthropic bases" do
    Crig::Providers::MiniMax.normalize_anthropic_base_url(Crig::Providers::MiniMax::GLOBAL_API_BASE_URL)
      .should eq(Crig::Providers::MiniMax::GLOBAL_ANTHROPIC_API_BASE_URL)
    Crig::Providers::MiniMax.normalize_anthropic_base_url(Crig::Providers::MiniMax::CHINA_API_BASE_URL)
      .should eq(Crig::Providers::MiniMax::CHINA_ANTHROPIC_API_BASE_URL)
    Crig::Providers::MiniMax.normalize_anthropic_base_url("https://proxy.example.com/v1")
      .should eq("https://proxy.example.com/anthropic")
  end

  it "normalize preserves existing anthropic base" do
    Crig::Providers::MiniMax.normalize_anthropic_base_url(Crig::Providers::MiniMax::CHINA_ANTHROPIC_API_BASE_URL)
      .should eq(Crig::Providers::MiniMax::CHINA_ANTHROPIC_API_BASE_URL)
  end

  it "anthropic primary override wins" do
    result = Crig::Providers::MiniMax.resolve_anthropic_base_override(
      "https://primary.example.com/anthropic",
      Crig::Providers::MiniMax::CHINA_API_BASE_URL,
    )
    result.should eq("https://primary.example.com/anthropic")
  end

  it "builds completion requests and rejects specific tool choice" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be concise")
      .tool(Crig::Completion::ToolDefinition.new("lookup", "Lookup", JSON.parse(%({"type":"object"}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    payload = Crig::Providers::MiniMax::MiniMaxCompletionRequest.from_request(
      Crig::Providers::MiniMax::MINIMAX_M2_7,
      request
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::MiniMax::MINIMAX_M2_7)
    payload["messages"].as_a.first["role"].as_s.should eq("system")
    payload["tools"].as_a.first["function"]["name"].as_s.should eq("lookup")
    payload["tool_choice"].as_s.should eq("required")

    expect_raises(Crig::Completion::CompletionError, /Provider doesn't support only using specific tools/) do
      Crig::Providers::MiniMax::MiniMaxCompletionRequest.from_request(
        Crig::Providers::MiniMax::MINIMAX_M2_7,
        Crig::Completion::Request::CompletionRequestBuilder
          .from_prompt("Hello")
          .tool_choice(Crig::Completion::ToolChoice.specific(["lookup"]))
          .build
      )
    end
  end
end

describe Crig::Providers::ZAI do
  it "supports client initialization and builders" do
    client = Crig::Providers::ZAI::Client.new("dummy-key")
    built = Crig::Providers::ZAI::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    built.api_key.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::ZAI::GENERAL_API_BASE_URL)

    # Anthropic-compatible client
    anthropic = Crig::Providers::ZAI::AnthropicClientBuilder.new("dummy-key").build
    anthropic.inner.api_key.token.should eq("dummy-key")
    anthropic.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::ZAI::ANTHROPIC_API_BASE_URL))
  end

  it "supports general and coding entrypoints" do
    general = Crig::Providers::ZAI::Client.builder.api_key("key").general.build
    coding = Crig::Providers::ZAI::Client.builder.api_key("key").coding.build

    general.base_url.should eq(Crig::Providers::ZAI::GENERAL_API_BASE_URL)
    coding.base_url.should eq(Crig::Providers::ZAI::CODING_API_BASE_URL)

    # Anthropic entrypoints
    anthropic_general = Crig::Providers::ZAI::AnthropicClientBuilder.new("key").general.build
    anthropic_coding = Crig::Providers::ZAI::AnthropicClientBuilder.new("key").coding.build

    anthropic_general.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::ZAI::ANTHROPIC_API_BASE_URL))
    anthropic_coding.inner.base_url.should eq(Crig::Providers::Anthropic.normalize_anthropic_base_url(Crig::Providers::ZAI::ANTHROPIC_API_BASE_URL))
  end

  it "normalizes openai style bases to anthropic base" do
    Crig::Providers::ZAI.normalize_anthropic_base_url(Crig::Providers::ZAI::GENERAL_API_BASE_URL)
      .should eq(Crig::Providers::ZAI::ANTHROPIC_API_BASE_URL)
    Crig::Providers::ZAI.normalize_anthropic_base_url(Crig::Providers::ZAI::CODING_API_BASE_URL)
      .should eq(Crig::Providers::ZAI::ANTHROPIC_API_BASE_URL)
    Crig::Providers::ZAI.normalize_anthropic_base_url("https://proxy.example.com/api/paas/v4")
      .should eq("https://proxy.example.com/api/anthropic")
    Crig::Providers::ZAI.normalize_anthropic_base_url("https://proxy.example.com/api/coding/paas/v4")
      .should eq("https://proxy.example.com/api/anthropic")
  end

  it "normalize preserves existing anthropic base" do
    Crig::Providers::ZAI.normalize_anthropic_base_url("https://proxy.example.com/api/anthropic")
      .should eq("https://proxy.example.com/api/anthropic")
  end

  it "anthropic primary override wins" do
    result = Crig::Providers::ZAI.resolve_anthropic_base_override(
      "https://primary.example.com/api/anthropic",
      Crig::Providers::ZAI::GENERAL_API_BASE_URL,
    )
    result.should eq("https://primary.example.com/api/anthropic")
  end

  it "builds completion requests and rejects specific tool choice" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be concise")
      .tool(Crig::Completion::ToolDefinition.new("lookup", "Lookup", JSON.parse(%({"type":"object"}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    payload = Crig::Providers::ZAI::ZAiCompletionRequest.from_request(
      Crig::Providers::ZAI::GLM_4_6,
      request
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::ZAI::GLM_4_6)
    payload["messages"].as_a.first["role"].as_s.should eq("system")
    payload["tools"].as_a.first["function"]["name"].as_s.should eq("lookup")
    payload["tool_choice"].as_s.should eq("required")
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

describe Crig::Providers::ChatGPT do
  it "supports client initialization with access token" do
    client = Crig::Providers::ChatGPT::Client.new("test-token")
    client.access_token.should eq("test-token")
    client.base_url.should eq(Crig::Providers::ChatGPT::CHATGPT_API_BASE_URL)
  end

  it "builds client through builder" do
    built = Crig::Providers::ChatGPT::Client.builder
      .access_token("token-123")
      .account_id("acct-456")
      .originator("test-rig")
      .build

    built.access_token.should eq("token-123")
    built.account_id.should eq("acct-456")
    built.ext.originator.should eq("test-rig")
  end

  it "exposes all model constants" do
    Crig::Providers::ChatGPT::GPT_5_4.should eq("gpt-5.4")
    Crig::Providers::ChatGPT::GPT_5_4_PRO.should eq("gpt-5.4-pro")
    Crig::Providers::ChatGPT::GPT_5_3_CODEX.should eq("gpt-5.3-codex")
    Crig::Providers::ChatGPT::GPT_5_3_CHAT_LATEST.should eq("gpt-5.3-chat-latest")
  end

  it "builds a completion model through the client" do
    client = Crig::Providers::ChatGPT::Client.new("test-token")
    model = client.completion_model(Crig::Providers::ChatGPT::GPT_5_4)

    model.should be_a(Crig::Providers::ChatGPT::ResponsesCompletionModel)
    model.model.should eq(Crig::Providers::ChatGPT::GPT_5_4)
  end
end

describe Crig::Providers::Copilot do
  it "supports client initialization with access token" do
    client = Crig::Providers::Copilot::Client.new("test-token")
    client.access_token.should eq("test-token")
    client.base_url.should eq(Crig::Providers::Copilot::GITHUB_COPILOT_API_BASE_URL)
  end

  it "builds client through builder" do
    built = Crig::Providers::Copilot::Client.builder
      .access_token("gh-token")
      .base_url("https://custom.copilot.com")
      .build

    built.access_token.should eq("gh-token")
    built.base_url.should eq("https://custom.copilot.com")
  end

  it "routes codex models to responses API" do
    model = Crig::Providers::Copilot::CompletionModel.new(
      Crig::Providers::Copilot::Client.new("test-token"),
      Crig::Providers::Copilot::GPT_5_3_CODEX,
    )
    # Internal routing check: codex models use responses path
    Crig::Providers::Copilot::CODEX_MODELS.includes?(Crig::Providers::Copilot::GPT_5_3_CODEX).should be_true
  end

  it "exposes embedding models" do
    client = Crig::Providers::Copilot::Client.new("test-token")
    emb = client.embedding_model(Crig::Providers::Copilot::TEXT_EMBEDDING_3_SMALL)

    emb.should be_a(Crig::Providers::Copilot::EmbeddingModel)
    emb.model.should eq(Crig::Providers::Copilot::TEXT_EMBEDDING_3_SMALL)
  end

  it "exposes all model constants" do
    Crig::Providers::Copilot::GPT_4O.should eq("gpt-4o")
    Crig::Providers::Copilot::CLAUDE_SONNET_4.should eq("claude-sonnet-4")
    Crig::Providers::Copilot::GEMINI_3_FLASH.should eq("gemini-3-flash-preview")
    Crig::Providers::Copilot::O3_MINI.should eq("o3-mini")
    Crig::Providers::Copilot::TEXT_EMBEDDING_3_LARGE.should eq("text-embedding-3-large")
  end
end
