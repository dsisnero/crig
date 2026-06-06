require "./spec_helper"

describe "OpenRouter prompt caching" do
  it "adds cache_control to string system message" do
    body = JSON.parse(%({
      "model": "test-model",
      "messages": [
        {"role": "system", "content": "You are helpful."},
        {"role": "user", "content": "hello"}
      ]
    }))

    Crig::Providers::OpenRouter.apply_prompt_caching(body)

    system_msg = body["messages"].as_a[0]
    content = system_msg["content"].as_a[0]
    content["type"].as_s.should eq("text")
    content["text"].as_s.should eq("You are helpful.")
    content["cache_control"]["type"].as_s.should eq("ephemeral")
  end

  it "adds cache_control to last block of array system message" do
    body = JSON.parse(%({
      "model": "test-model",
      "messages": [
        {"role": "system", "content": [
          {"type": "text", "text": "first"},
          {"type": "text", "text": "second"}
        ]},
        {"role": "user", "content": "hello"}
      ]
    }))

    Crig::Providers::OpenRouter.apply_prompt_caching(body)

    content = body["messages"].as_a[0]["content"].as_a
    content[0].as_h.has_key?("cache_control").should be_false
    content[1]["cache_control"]["type"].as_s.should eq("ephemeral")
    content[1]["text"].as_s.should eq("second")
  end

  it "no-ops when no system message present" do
    body = JSON.parse(%({
      "model": "test-model",
      "messages": [
        {"role": "user", "content": "hello"}
      ]
    }))

    Crig::Providers::OpenRouter.apply_prompt_caching(body)

    body["messages"].as_a[0]["role"].as_s.should eq("user")
  end
end
