require "../../spec_helper"

# Helper structs for extension tests
struct ReqId
  include JSON::Serializable
  getter value : String

  def initialize(@value : String)
  end
end

module Crig::Tool
  describe ToolFailure do
    it "per-kind constructors prefill retryable" do
      ToolFailure.timeout("t").retryable.should eq(true)
      ToolFailure.rate_limited("r").retryable.should eq(true)
      ToolFailure.network("n").retryable.should eq(true)
      ToolFailure.not_found("nf").retryable.should eq(false)
      ToolFailure.permission_denied("p").retryable.should eq(false)
      ToolFailure.invalid_args("i").retryable.should eq(false)
      ToolFailure.cancelled("c").retryable.should eq(false)
      ToolFailure.provider("p").retryable.should be_nil
      ToolFailure.other("o").retryable.should be_nil
      ToolFailure.new(ToolFailureKind::Timeout, "t").retryable.should be_nil
    end

    it "failure builders compose" do
      failure = ToolFailure.rate_limited("slow down")
        .with_http_status(429)
        .with_code("RATE_LIMIT")
        .with_retryable(false)

      failure.kind.should eq(ToolFailureKind::RateLimited)
      failure.http_status.should eq(429)
      failure.code.should eq("RATE_LIMIT")
      failure.retryable.should eq(false)
      failure.to_s.should eq("rate_limited: slow down")
    end

    it "kind has string representation" do
      ToolFailureKind::InvalidArgs.as_str.should eq("invalid_args")
      ToolFailureKind::Timeout.as_str.should eq("timeout")
      ToolFailureKind::Cancelled.as_str.should eq("cancelled")
      ToolFailureKind::NotFound.as_str.should eq("not_found")
      ToolFailureKind::PermissionDenied.as_str.should eq("permission_denied")
      ToolFailureKind::RateLimited.as_str.should eq("rate_limited")
      ToolFailureKind::Provider.as_str.should eq("provider")
      ToolFailureKind::Network.as_str.should eq("network")
      ToolFailureKind::Other.as_str.should eq("other")
    end
  end

  describe ToolOutcome do
    it "outcome predicates" do
      ok = ToolOutcome.success
      ok.success?.should be_true
      ok.error?.should be_false
      ok.error_kind.should be_nil
      ok.as_str.should eq("success")

      err = ToolOutcome.error(ToolFailure.not_found("x"))
      err.error?.should be_true
      err.is_error_kind?(ToolFailureKind::NotFound).should be_true
      err.is_error_kind?(ToolFailureKind::Timeout).should be_false
      err.error_kind.should eq(ToolFailureKind::NotFound)
      err.failure.try(&.kind).should eq(ToolFailureKind::NotFound)
      err.as_str.should eq("error")

      ToolOutcome.skipped.skip?.should be_true
      ToolOutcome.denied.denied?.should be_true
    end
  end

  describe ToolReturnOutcome do
    it "maps to observed outcome" do
      ToolReturnOutcome.success.into_tool_outcome.should eq(ToolOutcome.success)
      ToolReturnOutcome.denied.into_tool_outcome.should eq(ToolOutcome.denied)
      failure = ToolFailure.not_found("x")
      ToolReturnOutcome.error(failure).into_tool_outcome.should eq(ToolOutcome.error(failure))

      ToolReturnOutcome.success.as_str.should eq("success")
      ToolReturnOutcome.denied.as_str.should eq("denied")
      ToolReturnOutcome.error(ToolFailure.timeout("t")).as_str.should eq("error")
      ToolReturnOutcome.error(ToolFailure.timeout("t")).failure.try(&.kind).should eq(ToolFailureKind::Timeout)
      ToolReturnOutcome.denied.failure.should be_nil
    end
  end

  describe ToolReturn do
    it "success serializes verbatim string" do
      result = ToolReturn.success("hello\nworld").into_execution_result
      result.model_output.should eq("hello\nworld")
      result.outcome.success?.should be_true
    end

    it "failed preserves classification and output" do
      result = ToolReturn.failed(42, ToolFailure.not_found("id 7")).into_execution_result
      result.model_output.should eq("42")
      result.outcome.is_error_kind?(ToolFailureKind::NotFound).should be_true
    end

    it "extensions flow into execution result" do
      result = ToolReturn.success(1)
        .with_extension(ReqId.new("abc"))
        .into_execution_result
      result.extensions.get(ReqId).not_nil!.value.should eq("abc")
    end

    it "denied surfaces as denied observed outcome" do
      result = ToolReturn.denied("refused").into_execution_result
      result.outcome.should eq(ToolOutcome.denied)
      result.model_output.should eq("refused")
      result.outcome.denied?.should be_true
      result.outcome.skip?.should be_false
    end
  end

  describe ToolExecutionResult do
    it "success constructor" do
      result = ToolExecutionResult.success("ok")
      result.model_output.should eq("ok")
      result.outcome.success?.should be_true
    end

    it "failed constructor" do
      result = ToolExecutionResult.failed("nope", ToolFailure.not_found("missing"))
      result.model_output.should eq("nope")
      result.outcome.error?.should be_true
    end

    it "denied constructor" do
      result = ToolExecutionResult.denied("no access")
      result.model_output.should eq("no access")
      result.outcome.denied?.should be_true
    end

    it "with extensions" do
      result = ToolExecutionResult.success("data")
        .with_extension(ReqId.new("x-1"))
      result.extensions.get(ReqId).not_nil!.value.should eq("x-1")
    end
  end
end
