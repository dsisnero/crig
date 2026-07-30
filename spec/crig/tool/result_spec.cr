require "../../spec_helper"

module Crig::Tool
  describe ToolErrorKind do
    it "per-kind constructors set default retryability" do
      ToolExecutionError.timeout("t").retryable.should eq(true)
      ToolExecutionError.rate_limited("r").retryable.should eq(true)
      ToolExecutionError.network("n").retryable.should eq(true)
      ToolExecutionError.not_found("nf").retryable.should eq(false)
      ToolExecutionError.permission_denied("p").retryable.should eq(false)
      ToolExecutionError.invalid_args("i").retryable.should eq(false)
      ToolExecutionError.cancelled("c").retryable.should eq(false)
      ToolExecutionError.provider("p").retryable.should be_nil
      ToolExecutionError.other("o").retryable.should be_nil
    end

    it "has stable string representation" do
      ToolErrorKind::InvalidArgs.as_str.should eq("invalid_args")
      ToolErrorKind::Timeout.as_str.should eq("timeout")
      ToolErrorKind::Cancelled.as_str.should eq("cancelled")
      ToolErrorKind::NotFound.as_str.should eq("not_found")
      ToolErrorKind::PermissionDenied.as_str.should eq("permission_denied")
      ToolErrorKind::RateLimited.as_str.should eq("rate_limited")
      ToolErrorKind::Provider.as_str.should eq("provider")
      ToolErrorKind::Network.as_str.should eq("network")
      ToolErrorKind::Other.as_str.should eq("other")
    end
  end

  describe ToolExecutionError do
    it "error builder preserves policy fields and feedback" do
      error = ToolExecutionError.rate_limited("operator")
        .with_model_feedback("slow down")
        .with_retryable(false)
        .with_code("RATE_42")
        .with_http_status(429)
      error.kind.should eq(ToolErrorKind::RateLimited)
      error.message.should eq("operator")
      error.model_feedback.should eq("slow down")
      error.retryable.should eq(false)
      error.code.should eq("RATE_42")
      error.http_status.should eq(429)
    end

    it "detailed diagnostics are model-visible by default" do
      error = ToolExecutionError.provider("upstream rejected field `region`")
      error.message.should eq("upstream rejected field `region`")
      error.model_feedback.should eq("upstream rejected field `region`")
    end

    it "sensitive diagnostics can be explicitly redacted" do
      error = ToolExecutionError.provider("authorization token expired")
        .redact_model_feedback
      error.message.should eq("authorization token expired")
      error.model_feedback.should eq("the tool provider failed")
    end
  end

  describe ToolResult do
    it "success preserves multiline output verbatim" do
      result = ToolResult.success(ToolOutput.text("hello\nworld"))
      result.success?.should be_true
      result.output.as_text.should eq("hello\nworld")
      result.error.should be_nil
    end

    it "skip refusal and permission failure are distinct" do
      skipped = ToolResult.skipped("policy")
      refused = ToolResult.failed(ToolExecutionError.refused("tool refused"))
      permission_failure = ToolResult.failed(ToolExecutionError.permission_denied("authorization failed"))

      skipped.skipped?.should be_true
      skipped.refused?.should be_false

      refused.refused?.should be_true
      refused.skipped?.should be_false
      refused.error?.should be_false
      refused.error.should be_nil
      refused.refusal.should be_truthy
      refused.refusal.try(&.refusal?).should be_true

      permission_failure.error?.should be_true
      permission_failure.refused?.should be_false
      permission_failure.refusal.should be_nil
    end

    it "result states are mutually distinguishable" do
      success = ToolResult.success(ToolOutput.text("ok"))
      failure = ToolResult.failed(ToolExecutionError.not_found("missing"))
      skipped = ToolResult.skipped("policy")
      refused = ToolResult.failed(ToolExecutionError.refused("denied"))

      success.success?.should be_true
      failure.error?.should be_true
      skipped.skipped?.should be_true
      refused.refused?.should be_true

      refused.error?.should be_false
      skipped.refused?.should be_false
      refused.skipped?.should be_false

      success.status_name.should eq("success")
      failure.status_name.should eq("error")
      skipped.status_name.should eq("skipped")
      refused.status_name.should eq("denied")
    end

    it "is_error_kind matches errors but not refusals" do
      permission_failure = ToolResult.failed(ToolExecutionError.permission_denied("authorization failed"))
      refused = ToolResult.failed(ToolExecutionError.refused("tool refused"))

      permission_failure.is_error_kind(ToolErrorKind::PermissionDenied).should be_true
      refused.is_error_kind(ToolErrorKind::PermissionDenied).should be_false
    end

    it "from_error preserves existing envelope" do
      existing = ToolExecutionError.timeout("slow").with_code("T")
      kept = ToolExecutionError.from_error(existing)
      kept.kind.should eq(ToolErrorKind::Timeout)
      kept.code.should eq("T")
    end

    it "from_error wraps non-ToolExecutionError sources" do
      source = ArgumentError.new("boom")
      wrapped = ToolExecutionError.from_error(source)
      wrapped.kind.should eq(ToolErrorKind::Other)
      wrapped.message.should eq("boom")
      wrapped.model_feedback.should eq("the tool failed")
    end

    it "from_error preserves refusal disposition" do
      refused = ToolExecutionError.from_error(
        ToolExecutionError.refused("declined").with_code("POLICY")
      )
      refused.refusal?.should be_true
      refused.kind.should eq(ToolErrorKind::PermissionDenied)
      refused.code.should eq("POLICY")
    end

    it "errors can expose structured model output" do
      output = ToolOutput.json(JSON.parse(%({"error": "invalid region", "allowed": ["us", "eu"]})))
      result = ToolResult.failed(
        ToolExecutionError.invalid_args("region was invalid")
          .with_model_output(output)
      )

      result.output.should eq(output)
      result.error.should be_truthy
      result.error.try(&.model_output).should eq(output)
      result.error.try(&.model_feedback).should be_nil
    end
  end
end
