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

  it "drops leading orphan tool result into demoted set" do
    tc = tool_call_message("call_1", "t")
    tr = tool_result_message("call_1")
    policy = Crig::Memory::SlidingWindowMemory.last_messages(3)
    messages = [tc, tr, Crig::Completion::Message.user("after"), Crig::Completion::Message.assistant("done")]
    result = policy.apply(messages)
    result.should_not be_nil
    result.not_nil!.size.should eq(2)
    result.not_nil![0].rag_text.should eq("after")
  end

  it "demotes orphan tool result with prefix in apply_with_demoted" do
    tc = tool_call_message("call_1", "t")
    tr = tool_result_message("call_1")
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    kept, demoted = policy.apply_with_demoted([tc, tr, Crig::Completion::Message.user("after"), Crig::Completion::Message.assistant("done")])
    kept.size.should eq(2)
    kept[0].rag_text.should eq("after")
    demoted.size.should eq(2)
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

  it "charges per-message overhead" do
    counter = Crig::Memory::HeuristicTokenCounter.new(4.0, 4, 256)
    empty = counter.count(Crig::Completion::Message.user(""))
    empty.should be >= 4
  end

  it "is monotonic in text length" do
    counter = Crig::Memory::HeuristicTokenCounter.new(4.0, 4, 256)
    small = counter.count(Crig::Completion::Message.user("hi"))
    big = counter.count(Crig::Completion::Message.user("x" * 400))
    big.should be > small
  end

  it "counts system messages via text length" do
    counter = Crig::Memory::HeuristicTokenCounter.new(4.0, 4, 256)
    sys = Crig::Completion::Message.system("you are helpful")
    cost = counter.count(sys)
    cost.should be > 0
  end

  it "clamps invalid bytes_per_token" do
    zero = Crig::Memory::HeuristicTokenCounter.new(0.0, 0, 0)
    zero.count(Crig::Completion::Message.user("abcd")).should be >= 4

    nan = Crig::Memory::HeuristicTokenCounter.new(Float64::NAN, 0, 0)
    nan.count(Crig::Completion::Message.user("abcd")).should be >= 4
  end

  it "drives TokenWindowMemory" do
    policy = Crig::Memory::TokenWindowMemory.new(100, Crig::Memory::HeuristicTokenCounter.openai)
    out = policy.apply([
      Crig::Completion::Message.user("a" * 2000),
      Crig::Completion::Message.user("short"),
    ])
    out.should_not be_nil
    out.not_nil!.size.should eq(1)
  end

  it "counts tool call messages" do
    counter = Crig::Memory::HeuristicTokenCounter.new(4.0, 4, 256)
    tc = tool_call_message("call_1", "search")
    cost = counter.count(tc)
    cost.should be > 0
  end
end

describe Crig::Memory::TokenWindowMemory do
  it "keeps messages within budget" do
    counter = FixedTokenCounter.new(1)
    policy = Crig::Memory::TokenWindowMemory.new(2, counter)
    result = policy.apply([
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
      Crig::Completion::Message.user("c"),
      Crig::Completion::Message.assistant("d"),
    ])
    result.should_not be_nil
    result.not_nil!.size.should eq(2)
  end

  it "passes through when under budget" do
    counter = FixedTokenCounter.new(1)
    policy = Crig::Memory::TokenWindowMemory.new(Int32::MAX, counter)
    result = policy.apply([
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
    ])
    result.should_not be_nil
    result.not_nil!.size.should eq(2)
  end

  it "skips message larger than budget" do
    counter = FixedTokenCounter.new(10)
    policy = Crig::Memory::TokenWindowMemory.new(5, counter)
    result = policy.apply([Crig::Completion::Message.user("anything")])
    result.should_not be_nil
    result.not_nil!.should be_empty
  end

  it "reports demoted prefix" do
    counter = FixedTokenCounter.new(1)
    policy = Crig::Memory::TokenWindowMemory.new(2, counter)
    kept, demoted = policy.apply_with_demoted([
      Crig::Completion::Message.user("a"),
      Crig::Completion::Message.assistant("b"),
      Crig::Completion::Message.user("c"),
      Crig::Completion::Message.assistant("d"),
    ])
    kept.size.should eq(2)
    demoted.size.should eq(2)
  end

  it "drops leading orphan tool result" do
    tc = tool_call_message("call_1", "t")
    tr = tool_result_message("call_1")
    counter = FixedTokenCounter.new(10)
    policy = Crig::Memory::TokenWindowMemory.new(25, counter)
    result = policy.apply([tc, tr, Crig::Completion::Message.user("after")])
    result.should_not be_nil
    result.not_nil!.size.should eq(1)
    result.not_nil![0].rag_text.should eq("after")
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

describe Crig::Memory::DemotingPolicyMemory do
  it "delegates load/append/clear to inner" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    hook = Crig::Memory::NoopDemotionHook.new
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.append("c1", [Crig::Completion::Message.user("hello")])
    mem.load("c1").size.should eq(1)
    mem.clear("c1")
    mem.load("c1").size.should eq(0)
  end

  it "exposes inner, policy, hook accessors" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    hook = Crig::Memory::NoopDemotionHook.new
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.inner.should be_a(Crig::Memory::InMemoryConversationMemory)
    mem.policy.should be_a(Crig::Memory::NoopMemoryPolicy)
    mem.hook.should be_a(Crig::Memory::NoopDemotionHook)
  end

  it "runs policy on loaded messages" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    10.times { |i| inner.append("c1", [Crig::Completion::Message.user("msg#{i}")]) }
    policy = Crig::Memory::SlidingWindowMemory.last_messages(3)
    hook = Crig::Memory::NoopDemotionHook.new
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    loaded = mem.load("c1")
    loaded.size.should eq(3)
  end

  it "delivers demoted messages to hook on first load" do
    delivered_messages = [] of Crig::Completion::Message

    inner = Crig::Memory::InMemoryConversationMemory.new
    5.times { |i| inner.append("c1", [Crig::Completion::Message.user("msg#{i}")]) }
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    hook = DemotingHookSpy.new(delivered_messages)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")
    # First 3 messages should have been demoted
    delivered_messages.size.should eq(3)
  end

  it "does not re-deliver already delivered messages" do
    delivered = [] of Crig::Completion::Message

    inner = Crig::Memory::InMemoryConversationMemory.new
    5.times { |i| inner.append("c1", [Crig::Completion::Message.user("msg#{i}")]) }
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    hook = DemotingHookSpy.new(delivered)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")
    first_delivery = delivered.size
    delivered.clear
    mem.load("c1")
    # Second load should not re-deliver
    delivered.size.should eq(0)
    first_delivery.should eq(3)
  end

  it "returns decomposition via into_inner" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    hook = Crig::Memory::NoopDemotionHook.new
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    i, p, h = mem.into_inner
    i.should be_a(Crig::Memory::InMemoryConversationMemory)
    p.should be_a(Crig::Memory::NoopMemoryPolicy)
    h.should be_a(Crig::Memory::NoopDemotionHook)
  end

  it "only reports newly demoted messages on subsequent appends" do
    delivered = [] of Crig::Completion::Message
    hook = DemotingHookSpy.new(delivered)
    inner = Crig::Memory::InMemoryConversationMemory.new
    inner.append("c1", [
      Crig::Completion::Message.user("1"),
      Crig::Completion::Message.assistant("2"),
      Crig::Completion::Message.user("3"),
      Crig::Completion::Message.assistant("4"),
    ])
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")
    first_count = delivered.size
    first_count.should eq(2)

    inner.append("c1", [Crig::Completion::Message.user("5")])
    mem.load("c1")
    (delivered.size - first_count).should eq(1)
  end

  it "skips hook when nothing evicted" do
    delivered = [] of Crig::Completion::Message
    hook = DemotingHookSpy.new(delivered)
    inner = Crig::Memory::InMemoryConversationMemory.new
    inner.append("c1", [Crig::Completion::Message.user("1"), Crig::Completion::Message.assistant("2")])
    policy = Crig::Memory::SlidingWindowMemory.last_messages(10)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")
    delivered.size.should eq(0)
  end

  it "clear resets watermark so hook fires again" do
    delivered = [] of Crig::Completion::Message
    hook = DemotingHookSpy.new(delivered)
    inner = Crig::Memory::InMemoryConversationMemory.new
    inner.append("c1", [Crig::Completion::Message.user("1"), Crig::Completion::Message.assistant("2")])
    policy = Crig::Memory::SlidingWindowMemory.last_messages(1)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")  # demotes 1, delivered = 1
    mem.clear("c1")
    inner.append("c1", [Crig::Completion::Message.user("3"), Crig::Completion::Message.assistant("4")])
    mem.load("c1")  # demotes 1 again, delivered = 2
    delivered.size.should eq(2)
  end

  it "forget drops in-process watermark" do
    delivered = [] of Crig::Completion::Message
    hook = DemotingHookSpy.new(delivered)
    inner = Crig::Memory::InMemoryConversationMemory.new
    inner.append("c1", [Crig::Completion::Message.user("1"), Crig::Completion::Message.assistant("2")])
    policy = Crig::Memory::SlidingWindowMemory.last_messages(1)
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    mem.load("c1")
    mem.tracked_conversations.should eq(1)
    mem.forget("c1")
    mem.tracked_conversations.should eq(0)
    # Re-load re-delivers since watermark was forgotten
    mem.load("c1")
    delivered.size.should eq(2)
  end

  it "raises MemoryError on hook failure" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    5.times { |i| inner.append("c1", [Crig::Completion::Message.user("msg#{i}")]) }
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    hook = FailingDemotionHook.new
    mem = Crig::Memory::DemotingPolicyMemory.new(inner, policy, hook)

    begin
      mem.load("c1")
      fail("expected MemoryError")
    rescue e : Crig::Memory::MemoryError
      e.message.try(&.includes?("demotion hook failed")).should be_true
    end
  end
end

describe Crig::Memory::CompactingMemory do
  it "delegates load/append/clear to inner" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    mem.append("c1", [Crig::Completion::Message.user("hello")])
    mem.load("c1").size.should eq(1)
    mem.clear("c1")
    mem.load("c1").size.should eq(0)
  end

  it "splices summary when messages are evicted" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    5.times { |i| inner.append("c1", [Crig::Completion::Message.user("msg#{i}")]) }
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    loaded = mem.load("c1")
    # Should have summary + kept messages
    loaded.size.should eq(3) # summary + 2 kept
    loaded[0].rag_text.try(&.includes?("Conversation summary")).should be_true
  end

  it "returns only kept messages when nothing evicted" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    inner.append("c1", [Crig::Completion::Message.user("hello")])
    policy = Crig::Memory::SlidingWindowMemory.last_messages(10)
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    loaded = mem.load("c1")
    loaded.size.should eq(1)
  end

  it "uses previous summary as carry_over" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    3.times { |i| inner.append("c1", [Crig::Completion::Message.user("batch1-msg#{i}")]) }

    # First load evicts 1 (keeps 2), creates summary
    policy = Crig::Memory::SlidingWindowMemory.last_messages(2)
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)
    mem.load("c1")

    # Add more messages
    2.times { |i| inner.append("c1", [Crig::Completion::Message.user("batch2-msg#{i}")]) }
    loaded = mem.load("c1")
    # Should have summary + kept messages
    loaded[0].rag_text.try(&.includes?("Conversation summary")).should be_true
  end

  it "exposes inner, policy, compactor accessors" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    mem.inner.should be_a(Crig::Memory::InMemoryConversationMemory)
    mem.policy.should be_a(Crig::Memory::NoopMemoryPolicy)
    mem.compactor.should be_a(Crig::Memory::TemplateCompactor)
  end

  it "returns decomposition via into_inner" do
    inner = Crig::Memory::InMemoryConversationMemory.new
    policy = Crig::Memory::NoopMemoryPolicy.new
    compactor = Crig::Memory::TemplateCompactor.new
    mem = Crig::Memory::CompactingMemory.new(inner, policy, compactor)

    i, p, c = mem.into_inner
    i.should be_a(Crig::Memory::InMemoryConversationMemory)
    p.should be_a(Crig::Memory::NoopMemoryPolicy)
    c.should be_a(Crig::Memory::TemplateCompactor)
  end
end

private class FailingDemotionHook
  include Crig::Memory::DemotionHook

  def on_demote(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
    raise "simulated hook failure"
  end
end

private class DemotingHookSpy
  include Crig::Memory::DemotionHook

  getter received : Array(Crig::Completion::Message)

  def initialize(@received : Array(Crig::Completion::Message))
  end

  def on_demote(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
    @received.concat(messages)
  end
end

private class FixedTokenCounter
  include Crig::Memory::TokenCounter

  getter value : Int32

  def initialize(@value : Int32)
  end

  def count(message : Crig::Completion::Message) : Int32
    @value
  end
end

private def tool_call_message(id : String, name : String) : Crig::Completion::Message
  items = Array(Crig::Completion::UserContent | Crig::Completion::AssistantContent).new
  items << Crig::Completion::AssistantContent.tool_call(id, name, JSON.parse("{}"))
  Crig::Completion::Message.new(
    Crig::Completion::Message::Role::Assistant,
    Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(items),
  )
end

private def tool_result_message(call_id : String) : Crig::Completion::Message
  items = Array(Crig::Completion::UserContent | Crig::Completion::AssistantContent).new
  items << Crig::Completion::UserContent.tool_result(
    call_id,
    Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
      Crig::Completion::ToolResultContent.text("ok"),
    ),
  )
  Crig::Completion::Message.new(
    Crig::Completion::Message::Role::User,
    Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(items),
  )
end
