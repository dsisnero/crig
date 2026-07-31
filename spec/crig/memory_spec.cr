require "../spec_helper"

describe Crig::Memory::InMemoryConversationMemory, tags: %w[memory] do
  user_message = ->(text : String) : Crig::Completion::Message {
    Crig::Completion::Message.user(Crig::Completion::UserContent.text(text))
  }

  it "stores and loads messages for a conversation" do
    memory = Crig::Memory::InMemoryConversationMemory.new

    memory.load("conv1").should be_empty

    memory.append("conv1", [user_message.call("hello")])

    memory.load("conv1").size.should eq(1)
  end

  it "appends messages to an existing conversation" do
    memory = Crig::Memory::InMemoryConversationMemory.new

    memory.append("conv1", [user_message.call("a")])
    memory.append("conv1", [user_message.call("b")])

    memory.load("conv1").size.should eq(2)
  end

  it "clears a conversation" do
    memory = Crig::Memory::InMemoryConversationMemory.new

    memory.append("conv1", [user_message.call("hello")])

    memory.clear("conv1")
    memory.load("conv1").should be_empty
  end

  it "handles concurrent appends from multiple fibers without data loss" do
    memory = Crig::Memory::InMemoryConversationMemory.new
    n = 50
    ready = Channel(Nil).new(n)
    done = Channel(Nil).new(n)

    n.times do |i|
      spawn do
        ready.receive
        memory.append("concurrent", [user_message.call("msg-#{i}")])
        done.send(nil)
      end
    end

    n.times { ready.send(nil) }
    n.times { done.receive }

    messages = memory.load("concurrent")
    messages.size.should eq(n)
  end

  it "handles reads concurrent with writes without corruption" do
    memory = Crig::Memory::InMemoryConversationMemory.new
    ready = Channel(Nil).new(2)
    done = Channel(Nil).new(2)

    10.times { |i| memory.append("conv", [user_message.call("init-#{i}")]) }

    spawn do
      ready.receive
      50.times { |i| memory.append("conv", [user_message.call("writer-#{i}")]) }
      done.send(nil)
    end

    spawn do
      ready.receive
      50.times do
        msgs = memory.load("conv")
        msgs.should be_a(Array(Crig::Completion::Message))
      end
      done.send(nil)
    end

    ready.send(nil)
    ready.send(nil)
    done.receive
    done.receive
  end
end

describe Crig::Memory::DemotingPolicyMemory(
  Crig::Memory::InMemoryConversationMemory,
  Crig::Memory::SlidingWindowMemory,
  Crig::Memory::NoopDemotionHook,
), tags: %w[memory policy] do
  it "delegates append and clear to the inner store" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(10)
    hook = Crig::Memory::NoopDemotionHook.new
    memory = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    msg = Crig::Completion::Message.user(Crig::Completion::UserContent.text("hello"))
    memory.append("conv1", [msg])
    memory.load("conv1").size.should eq(1)

    memory.clear("conv1")
    memory.load("conv1").should be_empty
  end

  it "applies the sliding window policy on load" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(3)
    hook = Crig::Memory::NoopDemotionHook.new
    memory = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    5.times do |i|
      msg = Crig::Completion::Message.user(Crig::Completion::UserContent.text("msg-#{i}"))
      memory.append("conv1", [msg])
    end

    kept = memory.load("conv1")
    kept.size.should eq(3)
  end

  it "tracks conversations" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(1)
    hook = Crig::Memory::NoopDemotionHook.new
    memory = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    memory.append("conv1", [
      Crig::Completion::Message.user(Crig::Completion::UserContent.text("first")),
      Crig::Completion::Message.user(Crig::Completion::UserContent.text("second")),
    ])
    memory.load("conv1")
    memory.tracked_conversations.should eq(1)
  end
end

describe Crig::Memory::CompactingMemory(
  Crig::Memory::InMemoryConversationMemory,
  Crig::Memory::SlidingWindowMemory,
  Crig::Memory::TemplateCompactor,
), tags: %w[memory policy] do
  it "delegates append and clear to the inner store" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(10)
    compactor = Crig::Memory::TemplateCompactor.new("summary")
    memory = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    msg = Crig::Completion::Message.user(Crig::Completion::UserContent.text("hello"))
    memory.append("conv1", [msg])
    memory.load("conv1").size.should eq(1)

    memory.clear("conv1")
    memory.load("conv1").should be_empty
  end

  it "returns kept messages when under window limit" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(5)
    compactor = Crig::Memory::TemplateCompactor.new("summary")
    memory = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    3.times do |i|
      msg = Crig::Completion::Message.user(Crig::Completion::UserContent.text("msg-#{i}"))
      memory.append("conv1", [msg])
    end

    kept = memory.load("conv1")
    kept.size.should eq(3)
  end

  it "tracks conversations" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::SlidingWindowMemory.last_messages(1)
    compactor = Crig::Memory::TemplateCompactor.new("summary")
    memory = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    memory.append("conv1", [
      Crig::Completion::Message.user(Crig::Completion::UserContent.text("first")),
      Crig::Completion::Message.user(Crig::Completion::UserContent.text("second")),
    ])
    memory.load("conv1")
    memory.tracked_conversations.should eq(1)
  end
end
