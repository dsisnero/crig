require "./spec_helper"

describe Crig::Memory::InMemoryConversationMemory do
  describe "#load" do
    it "returns empty for unknown conversation" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.load("unknown").should eq([] of Crig::Completion::Message)
    end
  end

  describe "#append and #load round-trip" do
    it "stores and loads messages" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("c1", [Crig::Completion::Message.user("hello"), Crig::Completion::Message.assistant("hi")])

      loaded = mem.load("c1")
      loaded.size.should eq(2)
      loaded[0].role.user?.should be_true
      loaded[1].role.assistant?.should be_true
    end

    it "isolates conversations from each other" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("a", [Crig::Completion::Message.user("hi a")])
      mem.append("b", [Crig::Completion::Message.user("hi b")])

      mem.load("a").size.should eq(1)
      mem.load("b").size.should eq(1)
    end

    it "appends across multiple calls" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("c", [Crig::Completion::Message.user("one")])
      mem.append("c", [Crig::Completion::Message.assistant("two")])

      mem.load("c").size.should eq(2)
    end
  end

  describe "#clear" do
    it "removes all messages for a conversation" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("c", [Crig::Completion::Message.user("x")])
      mem.clear("c")

      mem.load("c").should eq([] of Crig::Completion::Message)
    end

    it "does not affect other conversations" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("a", [Crig::Completion::Message.user("a")])
      mem.append("b", [Crig::Completion::Message.user("b")])
      mem.clear("a")

      mem.load("a").should eq([] of Crig::Completion::Message)
      mem.load("b").size.should eq(1)
    end
  end

  describe "#with_filter" do
    it "transforms loaded messages through the filter" do
      mem = Crig::Memory::InMemoryConversationMemory.new
        .with_filter(->(msgs : Array(Crig::Completion::Message)) { msgs.reverse.first(2).to_a })

      mem.append("c", [
        Crig::Completion::Message.user("1"),
        Crig::Completion::Message.assistant("2"),
        Crig::Completion::Message.user("3"),
        Crig::Completion::Message.assistant("4"),
      ])

      loaded = mem.load("c")
      loaded.size.should eq(2)
    end

    it "does not filter without a filter set" do
      mem = Crig::Memory::InMemoryConversationMemory.new
      mem.append("c", [Crig::Completion::Message.user("hello")])

      loaded = mem.load("c")
      loaded.size.should eq(1)
    end
  end
end

describe Crig::Memory::MemoryError do
  it "builds backend error" do
    err = Crig::Memory::MemoryError.backend("connection refused", "redis://localhost")
    err.kind.should eq(Crig::Memory::MemoryError::Kind::Backend)
    err.message.to_s.includes?("connection refused").should be_true
  end

  it "builds policy error" do
    err = Crig::Memory::MemoryError.policy("max turns exceeded")
    err.kind.should eq(Crig::Memory::MemoryError::Kind::Policy)
  end

  it "builds internal error" do
    err = Crig::Memory::MemoryError.internal("lock poisoned")
    err.kind.should eq(Crig::Memory::MemoryError::Kind::Internal)
  end
end

describe Crig::Memory::NoopDemotionHook do
  it "implements DemotionHook without side effects" do
    hook = Crig::Memory::NoopDemotionHook.new
    hook.on_demote("c1", [Crig::Completion::Message.user("hello")])
    # Should not raise
  end
end

describe Crig::Memory::SlidingWindowMemory do
  it "keeps last N messages" do
    policy = Crig::Memory::SlidingWindowMemory.last_messages(3)
    messages = [
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
      Crig::Completion::Message.user("c"),
      Crig::Completion::Message.assistant("d"),
      Crig::Completion::Message.user("e"),
    ]
    result = policy.apply(messages)
    result.should_not be_nil
    result.not_nil!.size.should eq(3)
  end

  it "returns all messages when below limit" do
    policy = Crig::Memory::SlidingWindowMemory.last_messages(10)
    messages = [
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
    ]
    result = policy.apply(messages)
    result.should_not be_nil
    result.not_nil!.size.should eq(2)
  end

  it "reports demoted messages" do
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    messages = [
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
      Crig::Completion::Message.user("c"),
    ]
    kept, demoted = policy.apply_with_demoted(messages)
    kept.size.should eq(2)
    demoted.size.should eq(1)
  end
end

describe Crig::Memory::NoopMemoryPolicy do
  it "returns input unchanged" do
    policy = Crig::Memory::NoopMemoryPolicy.new
    messages = [Crig::Completion::Message.user("hello")]
    result = policy.apply(messages)
    result.should_not be_nil
    result.not_nil!.size.should eq(1)
  end
end

describe Crig::Memory::HeuristicTokenCounter do
  it "counts tokens for a user message" do
    counter = Crig::Memory::HeuristicTokenCounter.new(4.0, 4, 256)
    msg = Crig::Completion::Message.user("hello world")
    count = counter.count(msg)
    count.should be > 0
  end

  it "provides openai preset" do
    counter = Crig::Memory::HeuristicTokenCounter.openai
    counter.bytes_per_token.should eq(4.0)
    counter.per_message_overhead.should eq(4)
  end

  it "provides anthropic preset" do
    counter = Crig::Memory::HeuristicTokenCounter.anthropic
    counter.bytes_per_token.should eq(3.5)
  end
end

describe Crig::Memory::TemplateCompactor do
  it "produces a summary from evicted messages" do
    compactor = Crig::Memory::TemplateCompactor.new
    evicted = [
      Crig::Completion::Message.user("What is 2+2?"),
      Crig::Completion::Message.assistant("It's 4."),
    ]
    result = compactor.compact("conv-1", evicted, nil)
    result.role.user?.should be_true
  end

  it "includes previous summary in rolling compaction" do
    compactor = Crig::Memory::TemplateCompactor.new
    prev_summary = Crig::Completion::Message.user("[Conversation summary so far]\nPrior turns about math")
    evicted = [Crig::Completion::Message.user("ok thanks")]
    result = compactor.compact("conv-2", evicted, prev_summary)
    result.role.user?.should be_true
  end
end
