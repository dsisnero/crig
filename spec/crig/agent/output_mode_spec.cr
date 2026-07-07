require "../../spec_helper"

module Crig
  describe OutputMode do
    it "has all variants" do
      OutputMode::Auto.should be_a(OutputMode)
      OutputMode::Tool.should be_a(OutputMode)
      OutputMode::Native.should be_a(OutputMode)
      OutputMode::Prompted.should be_a(OutputMode)
    end

    it "defaults to Auto" do
      OutputMode.default.should eq(OutputMode::Auto)
    end
  end
end
