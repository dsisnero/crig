require "../spec_helper"

describe Crig::Client::ProviderClientError do
  it "builds an environment variable error" do
    err = Crig::Client::ProviderClientError.environment_variable("API_KEY", "not set")
    err.kind.should eq(Crig::Client::ProviderClientError::Kind::EnvironmentVariable)
    err.var_name.should eq("API_KEY")
    err.message.to_s.includes?("API_KEY").should be_true
  end

  it "builds an http error" do
    http_err = Crig::HttpClient::Error.stream_ended
    err = Crig::Client::ProviderClientError.http(http_err)
    err.kind.should eq(Crig::Client::ProviderClientError::Kind::Http)
    err.http_error.should eq(http_err)
  end

  it "builds an invalid configuration error" do
    err = Crig::Client::ProviderClientError.invalid_configuration("missing base URL")
    err.kind.should eq(Crig::Client::ProviderClientError::Kind::InvalidConfiguration)
    err.message.to_s.includes?("missing base URL").should be_true
  end
end

describe Crig::Client do
  describe ".required_env_var" do
    it "reads an existing environment variable" do
      ENV["CRIG_TEST_REQUIRED_VAR"] = "test-value"
      result = Crig::Client.required_env_var("CRIG_TEST_REQUIRED_VAR")
      result.should be_a(String)
      result.as(String).should eq("test-value")
    ensure
      ENV.delete("CRIG_TEST_REQUIRED_VAR")
    end

    it "returns an error when the variable is not set" do
      ENV.delete("CRIG_TEST_MISSING_VAR")
      result = Crig::Client.required_env_var("CRIG_TEST_MISSING_VAR")
      result.should be_a(Crig::Client::ProviderClientError)
    end
  end

  describe ".optional_env_var" do
    it "reads an existing variable" do
      ENV["CRIG_TEST_OPTIONAL_VAR"] = "opt-value"
      result = Crig::Client.optional_env_var("CRIG_TEST_OPTIONAL_VAR")
      result.should be_a(String)
      result.as(String).should eq("opt-value")
    ensure
      ENV.delete("CRIG_TEST_OPTIONAL_VAR")
    end

    it "returns nil when the variable is absent" do
      ENV.delete("CRIG_TEST_OPTIONAL_MISSING")
      result = Crig::Client.optional_env_var("CRIG_TEST_OPTIONAL_MISSING")
      result.should be_nil
    end
  end
end
