require "../spec_helper"

class FakeMemoryModel
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

describe Crig::AgentBuilder do
  describe "#memory" do
    it "attaches a conversation memory backend to the agent" do
      model = FakeMemoryModel.new
      memory = Crig::Memory::InMemoryConversationMemory.new

      builder = Crig::AgentBuilder(FakeMemoryModel).new(model)
        .memory(memory)

      builder.memory_value.should_not be_nil
    end

    it "sets a default conversation id" do
      model = FakeMemoryModel.new
      memory = Crig::Memory::InMemoryConversationMemory.new

      builder = Crig::AgentBuilder(FakeMemoryModel).new(model)
        .memory(memory)
        .conversation_id("thread-1")

      builder.default_conversation_id_value.should eq("thread-1")
    end
  end
end

describe Crig::PromptRequest do
  describe "#conversation" do
    it "loads history from memory before sending" do
      model = FakeMemoryModel.new
      memory = Crig::Memory::InMemoryConversationMemory.new
      memory.append("thread-1", [Crig::Completion::Message.user("hello"), Crig::Completion::Message.assistant("hi")])

      builder = Crig::AgentBuilder(FakeMemoryModel).new(model)
        .memory(memory)

      agent = builder.build
      request = agent.prompt("continue").conversation("thread-1")

      # After conversation(), the memory should still have the previously appended messages
      loaded = memory.load("thread-1")
      loaded.size.should eq(2)
    end
  end

  describe "#without_memory" do
    it "disables memory for the request" do
      model = FakeMemoryModel.new
      memory = Crig::Memory::InMemoryConversationMemory.new

      builder = Crig::AgentBuilder(FakeMemoryModel).new(model)
        .memory(memory)
        .conversation_id("thread-1")

      agent = builder.build
      request = agent.prompt("hi").without_memory

      request.memory.should be_nil
    end
  end
end
