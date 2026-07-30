require "../../spec_helper"

module Crig::Completion
  describe PromptError do
    it "memory_error surfaces a MemoryError as PromptError" do
      mem_err = Crig::Memory::MemoryError.backend("Database connection failed")
      err = PromptError.memory_error(mem_err)

      err.kind.memory_error?.should be_true
      err.message.to_s.should contain("Database connection failed")
    end

    it "memory_error carries the source error" do
      mem_err = Crig::Memory::MemoryError.backend("timeout", detail: "redis timeout")
      err = PromptError.memory_error(mem_err)

      err.message.to_s.should contain("MemoryError")
      err.message.to_s.should contain("timeout")
    end
  end
end
