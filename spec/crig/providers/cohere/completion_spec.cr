require "../../../spec_helper"

module Crig::Providers::Cohere
  describe "CompletionError error paths" do
    it "non-success status preserves status and body via from_http_response" do
      err = Crig::Completion::CompletionError.from_http_response(503, "service unavailable")
      err.provider_response_status.should eq(503)
      err.provider_response_body.should eq("service unavailable")
    end
  end
end
