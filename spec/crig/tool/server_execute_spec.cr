require "../../spec_helper"

module Crig
  describe ToolServerHandle do
    it "execute returns ToolResult for successful call" do
      tool = DynamicTool.new("greet", "Greets", JSON.parse(%({"type":"string"}))) do |args, ctx|
        Tool::ToolResult.success(Tool::ToolOutput.text("Hello #{args}"))
      end

      handle = ToolServerHandle.with_resolver("test", ->(name : String, args : String) { tool.call(args) })

      result = handle.execute("greet", "world", Tool::ToolContext.new)
      result.success?.should be_true
      result.output.as_text.should eq("Hello world")
    end

    it "execute returns ToolResult for failing call" do
      handle = ToolServerHandle.with_resolver("test", ->(name : String, args : String) { raise "not found" })

      result = handle.execute("nope", "{}", Tool::ToolContext.new)
      result.error?.should be_true
    end

    it "publishes per-dispatch result metadata back to the caller context" do
      tool = DynamicTool.new("meta", "Sets metadata", JSON.parse(%({"type":"object"}))) do |args, ctx|
        ctx.insert_result("dispatch-1")
        Tool::ToolResult.success(Tool::ToolOutput.text("done"))
      end

      handle = ToolServer.new.tool(tool).run

      context = Tool::ToolContext.new
      result = handle.execute("meta", "{}", context)

      result.success?.should be_true
      context.result(String).should eq("dispatch-1")
    end

    it "clears prior dispatch result metadata before a new execute" do
      tool = DynamicTool.new("meta", "Sets metadata", JSON.parse(%({"type":"object"}))) do |args, ctx|
        ctx.insert_result("dispatch-2")
        Tool::ToolResult.success(Tool::ToolOutput.text("done"))
      end

      handle = ToolServer.new.tool(tool).run

      context = Tool::ToolContext.new
      context.insert_result("stale")
      result = handle.execute("meta", "{}", context)

      result.success?.should be_true
      context.result(String).should eq("dispatch-2")
    end

    it "executes concurrent tool calls in parallel" do
      release = Channel(Nil).new(2)
      wg = WaitGroup.new(2)

      tool = DynamicTool.new("barrier", "Blocks until both arrive", JSON.parse(%({"type":"object"}))) do |args, ctx|
        wg.done
        release.receive
        Tool::ToolResult.success(Tool::ToolOutput.text("done"))
      end

      handle = ToolServer.new.tool(tool).run

      result_channel = Channel(Tool::ToolResult).new(2)
      spawn { result_channel.send(handle.execute("barrier", "{}", Tool::ToolContext.new)) }
      spawn { result_channel.send(handle.execute("barrier", "{}", Tool::ToolContext.new)) }

      # Wait for both fibers to be inside the tool. If execution were
      # sequential, the first call would block on release.receive and the
      # second would never start, so wg.wait would hang.
      wg.wait
      2.times { release.send(nil) }

      results = 2.times.map { result_channel.receive }.to_a
      results.size.should eq(2)
      results.all?(&.success?).should be_true
    end

    it "allows adding a tool while another tool is executing" do
      started = Channel(Nil).new(1)
      allow_finish = Channel(Nil).new(1)

      tool = DynamicTool.new("controlled", "Waits", JSON.parse(%({"type":"object"}))) do |args, ctx|
        started.send(nil)
        allow_finish.receive
        Tool::ToolResult.success(Tool::ToolOutput.text("42"))
      end

      server = ToolServer.new.tool(tool)
      handle = server.run

      result_channel = Channel(Tool::ToolResult).new(1)
      spawn do
        result_channel.send(handle.execute("controlled", "{}", Tool::ToolContext.new))
      end

      # Wait until the tool call is mid-execution, then add a new tool.
      started.receive
      add_tool = DynamicTool.new("extra", "Extra tool", JSON.parse(%({"type":"object"}))) do |args, ctx|
        Tool::ToolResult.success(Tool::ToolOutput.text("extra"))
      end
      handle.add_tool(add_tool)

      # Release the running tool and confirm it completes.
      allow_finish.send(nil)
      result = result_channel.receive
      result.success?.should be_true
      result.output.render.should eq("42")

      # The new tool is registered and callable.
      handle.call_tool("extra", "{}").should eq("extra")
    end
  end
end
