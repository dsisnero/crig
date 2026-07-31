require "../../spec_helper"
describe Crig::Providers::Hyperbolic do
  it "supports client initialization" do
    client = Crig::Providers::Hyperbolic::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Hyperbolic::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Hyperbolic::HYPERBOLIC_API_BASE_URL)
  end
end
