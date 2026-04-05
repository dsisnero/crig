require "../src/crig"

module Crig::Examples::OllamaStreamingPauseControl
  PREAMBLE = "You are a helpful AI assistant. Provide concise explanations."
  PROMPT   = "Explain backpropagation in neural networks."
  MODEL    = "gemma3:4b"

  record StreamStats,
    text : String,
    chunk_count : Int32,
    usage : Crig::Completion::Usage?

  def self.build_client(base_url : String = Crig::Providers::Ollama::OLLAMA_API_BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.new(Crig::Nothing.new, base_url)
  end

  def self.build_model(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
  ) : Crig::Providers::Ollama::CompletionModel
    client.completion_model(model)
  end

  def self.build_request(
    model : M,
    prompt : String = PROMPT,
    preamble : String = PREAMBLE,
  ) : Crig::Completion::Request::CompletionRequest forall M
    model.completion_request(prompt)
      .preamble(preamble)
      .temperature(0.7)
      .build
  end

  def self.run_stream(
    model : M,
    prompt : String = PROMPT,
    preamble : String = PREAMBLE,
  ) : Crig::StreamingCompletionResponse(Crig::Completion::CompletionResponse(String)) forall M
    model.stream(build_request(model, prompt, preamble))
  end

  def self.process_stream(
    stream : Crig::StreamingCompletionResponse(Crig::Completion::CompletionResponse(String)),
    io : IO = STDOUT,
    pause_every : Int32 = 50,
  ) : StreamStats
    collected = IO::Memory.new
    chunk_count = 0
    usage = nil.as(Crig::Completion::Usage?)

    while item = stream.next_item
      case item.kind
      when .text?
        chunk = item.text.try(&.text) || ""
        io << chunk
        collected << chunk
        chunk_count += 1

        if pause_every > 0 && chunk_count % pause_every == 0
          stream.pause
          stream.resume
        end
      when .tool_call?, .reasoning?
        chunk_count += 1
      when .final?
        usage = item.final.try(&.usage)
      else
      end
    end

    StreamStats.new(collected.to_s, chunk_count, usage)
  end
end
