require "../src/crig"

module Crig::Examples::AgentStreamChat
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.default_history : Array(Crig::Completion::Message)
    [
      Crig::Completion::Message.user("Tell me a joke!"),
      Crig::Completion::Message.assistant("Why did the chicken cross the road?\n\nTo get to the other side!"),
    ]
  end

  def self.run_stream(agent : Crig::Agent(M), prompt : String = "Entertain me!", history : Array(Crig::Completion::Message) = default_history) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_chat(prompt, history).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
