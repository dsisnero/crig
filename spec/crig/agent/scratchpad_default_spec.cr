require "../../spec_helper"

# Scratchpad types should be classes (not structs) for shared mutable state.
class RequiredCounter
  include JSON::Serializable
  property count : Int32

  def initialize(@count : Int32)
  end
end

module Crig
  describe Scratchpad, "update with initial parameter" do
    it "works with initial parameter" do
      pad = Scratchpad.new
      pad.update(RequiredCounter, initial: RequiredCounter.new(0)) { |c| c.count += 1 }
      pad.get(RequiredCounter).not_nil!.count.should eq(1)
    end

    it "raises without initial for types that fail from_json({})" do
      pad = Scratchpad.new
      expect_raises(Exception, /from_json/) do
        pad.update(RequiredCounter) { |c| c.count += 1 }
      end
    end

    it "insert then update works" do
      pad = Scratchpad.new
      pad.insert(RequiredCounter.new(5))
      pad.update(RequiredCounter) { |c| c.count += 1 }
      pad.get(RequiredCounter).not_nil!.count.should eq(6)
    end
  end
end
