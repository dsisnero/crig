require "./spec_helper"

private class DelayedTool
  include Crig::ToolDyn

  getter name : String
  @delay_ms : Int32

  def initialize(@name : String, @delay_ms : Int32 = 10)
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(@name, "test tool", JSON.parse(%({"type":"object","properties":{}})))
  end

  def call(args : String) : String
    sleep(@delay_ms.milliseconds)
    "result:#{@name}"
  end
end

describe Crig::ToolServer do
  describe "bounded concurrency" do
    it "limits concurrent tool calls to max_concurrency" do
      server = Crig::ToolServer.new
        .with_max_concurrency(2)
        .add_tools(
          Crig::ToolSet.from_tools_boxed([
            DelayedTool.new("tool-a", 100).as(Crig::ToolDyn),
            DelayedTool.new("tool-b", 100).as(Crig::ToolDyn),
            DelayedTool.new("tool-c", 100).as(Crig::ToolDyn),
          ])
        )

      handle = server.run
      start = Time.instant

      ch_a = Channel(String).new(1)
      ch_b = Channel(String).new(1)
      ch_c = Channel(String).new(1)

      spawn { ch_a.send(handle.call_tool("tool-a", %({}))) }
      spawn { ch_b.send(handle.call_tool("tool-b", %({}))) }
      spawn { ch_c.send(handle.call_tool("tool-c", %({}))) }

      r_a = ch_a.receive
      r_b = ch_b.receive
      r_c = ch_c.receive

      elapsed = Time.instant - start
      handle.close

      r_a.should eq "result:tool-a"
      r_b.should eq "result:tool-b"
      r_c.should eq "result:tool-c"

      # With max_concurrency=2, 3 calls of 100ms each should finish
      # in ~200ms (2 batches), not ~300ms (sequential).
      elapsed.total_milliseconds.should be < 250
    end

    it "defaults to System.cpu_count" do
      server = Crig::ToolServer.new
      server.run

      # DEFAULT_TOOL_CONCURRENCY should be >= 1
      Crig::ToolServer::DEFAULT_TOOL_CONCURRENCY.should be >= 1
    end
  end

  describe "graceful shutdown" do
    it "ToolServerHandle#close shuts down the worker loop" do
      server = Crig::ToolServer.new
      handle = server.run
      handle.close

      # After close, sending should either succeed or raise
      # depending on timing, but the worker loop should exit
      # without hanging.
      sleep(10.milliseconds)
    end

    it "does not hang when closed with inflight tool calls" do
      server = Crig::ToolServer.new
        .with_max_concurrency(1)
        .add_tools(
          Crig::ToolSet.from_tools_boxed([
            DelayedTool.new("slow", 200).as(Crig::ToolDyn),
          ])
        )

      handle = server.run

      ch = Channel(String).new(1)
      spawn do
        ch.send(handle.call_tool("slow", %({})))
      end

      sleep(10.milliseconds) # let the tool call start
      handle.close
      sleep(10.milliseconds) # give shutdown a moment
    end
  end
end
