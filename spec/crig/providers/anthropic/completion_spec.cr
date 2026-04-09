require "../../../spec_helper"

describe Crig::Providers::Anthropic::CacheControl do
  it "serializes ephemeral cache controls with and without ttl" do
    Crig::Providers::Anthropic::CacheControl.ephemeral.to_json.should eq(%({"type":"ephemeral"}))
    Crig::Providers::Anthropic::CacheControl.ephemeral_1h.to_json.should eq(%({"type":"ephemeral","ttl":"1h"}))
  end
end

describe Crig::Providers::Anthropic::CompletionModel do
  it "supports automatic caching helpers" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    model = Crig::Providers::Anthropic::CompletionModel.new(client, Crig::Providers::Anthropic::CLAUDE_3_5_HAIKU)

    cached = model.with_automatic_caching
    cached.prompt_caching?.should be_true
    cached.automatic_caching_ttl.should be_nil

    cached_1h = model.with_automatic_caching_1h
    cached_1h.prompt_caching?.should be_true
    cached_1h.automatic_caching_ttl.should eq(Crig::Providers::Anthropic::CacheTtl::OneHour)
  end
end
