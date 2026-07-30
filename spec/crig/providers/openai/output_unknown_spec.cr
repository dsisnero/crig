require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe Output do
    it "parses known message output type" do
      json = JSON.parse(%({"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[]}))
      output = Output.from_json_value(json)
      output.kind.message?.should be_true
    end

    it "parses known function_call output type" do
      json = JSON.parse(%({"type":"function_call","id":"call_1","call_id":"call_1","name":"get_weather","arguments":{},"status":"completed"}))
      output = Output.from_json_value(json)
      output.kind.function_call?.should be_true
    end

    it "parses reasoning output type" do
      json = JSON.parse(%({"type":"reasoning","id":"r_01","summary":[],"status":"completed"}))
      output = Output.from_json_value(json)
      output.kind.reasoning?.should be_true
    end

    it "captures unknown output type as Unknown preserving payload" do
      json = JSON.parse(%({"type":"code_interpreter_call","id":"ci_1","input":"print(1)","output":"1"}))
      output = Output.from_json_value(json)
      output.kind.unknown?.should be_true
      output.raw_value.should be_truthy
      raw = output.raw_value.not_nil!
      raw["type"].as_s.should eq("code_interpreter_call")
      raw["input"].as_s.should eq("print(1)")
    end

    it "captures missing type field as Unknown" do
      json = JSON.parse(%({"id":"unknown","data":"some value"}))
      output = Output.from_json_value(json)
      output.kind.unknown?.should be_true
      output.raw_value.should be_truthy
      raw = output.raw_value.not_nil!
      raw["data"].as_s.should eq("some value")
    end

    it "round-trips Unknown through to_json_value" do
      json = JSON.parse(%({"type":"code_interpreter_call","id":"ci_1","input":"test"}))
      output = Output.from_json_value(json)
      roundtripped = output.to_json_value
      roundtripped["type"].as_s.should eq("code_interpreter_call")
      roundtripped["input"].as_s.should eq("test")
    end
  end
end
