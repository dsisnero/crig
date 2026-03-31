require "../src/crig"

module Crig::Examples::AnthropicPlaintextDocument
  PREAMBLE = "You are a helpful assistant that analyzes documents."
  PROMPT   = "List the three main goals of Rust mentioned in this document."

  PLAIN_TEXT = <<-'TEXT'.strip
    The Rust Programming Language

    Rust is a systems programming language focused on three goals: safety, speed,
    and concurrency. It accomplishes these goals without a garbage collector, making
    it useful for a number of use cases other languages aren't good at: embedding in
    other languages, programs with specific space and time requirements, and writing
    low-level code, like device drivers and operating systems.

    Key Features:
    - Zero-cost abstractions
    - Move semantics
    - Guaranteed memory safety
    - Threads without data races
    - Trait-based generics
    - Pattern matching
    - Type inference
    - Minimal runtime
    - Efficient C bindings
  TEXT

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_4_SONNET,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.document(text : String = PLAIN_TEXT) : Crig::Completion::Document
    Crig::Completion::Document.new(
      Crig::Completion::DocumentSourceKind.string(text),
      Crig::Completion::DocumentMediaType::TXT,
    )
  end

  def self.document_prompt(agent : Crig::Agent(M), text : String = PLAIN_TEXT) : String forall M
    agent.prompt(document(text)).send
  end

  def self.instruction_message(
    text : String = PLAIN_TEXT,
    prompt : String = PROMPT,
  ) : Crig::Completion::Message
    Crig::Completion::Message.user([
      Crig::Completion::UserContent.document(text, Crig::Completion::DocumentMediaType::TXT),
      Crig::Completion::UserContent.text(prompt),
    ])
  end

  def self.instruction_prompt(
    agent : Crig::Agent(M),
    text : String = PLAIN_TEXT,
    prompt : String = PROMPT,
  ) : String forall M
    agent.prompt(instruction_message(text, prompt)).send
  end
end
