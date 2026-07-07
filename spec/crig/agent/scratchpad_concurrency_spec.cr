require "../../spec_helper"
require "wait_group"

class CountScratchMT
  include JSON::Serializable
  property value : Int32 = 0
end

module Crig
  describe Scratchpad, "concurrent safety" do
    it "supports concurrent updates from multiple fibers" do
      pad = Scratchpad.new
      wg = WaitGroup.new(10)

      10.times do
        spawn do
          pad.update(CountScratchMT) { |c| c.value += 1 }
          wg.done
        end
      end

      wg.wait

      c = pad.get(CountScratchMT)
      c.not_nil!.value.should eq(10)
    end

    it "supports concurrent insert and get from multiple fibers" do
      pad = Scratchpad.new
      wg = WaitGroup.new(6)

      3.times do |i|
        spawn do
          pad.insert(i.to_i64)
          wg.done
        end
      end

      3.times do
        spawn do
          pad.get(Int64)
          wg.done
        end
      end

      wg.wait
    end

    it "shared scratchpad across cloned HookContext works concurrently" do
      ctx1 = HookContext.new(is_streaming: false)
      ctx2 = HookContext.new(is_streaming: false, scratchpad: ctx1.scratchpad)

      wg = WaitGroup.new(2)

      spawn do
        ctx1.scratchpad.update(CountScratchMT) { |c| c.value += 1 }
        wg.done
      end

      spawn do
        ctx2.scratchpad.update(CountScratchMT) { |c| c.value += 1 }
        wg.done
      end

      wg.wait

      ctx1.scratchpad.get(CountScratchMT).not_nil!.value.should eq(2)
    end
  end
end
