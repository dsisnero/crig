require "../../../../spec_helper"

describe Crig::Providers::OpenAI::ResponsesWebSocketCreateOptions do
  it "serializes warmup options with generate false" do
    Crig::Providers::OpenAI::ResponsesWebSocketCreateOptions.warmup.to_json.should eq(%({"generate":false}))
  end
end

describe Crig::Providers::OpenAI do
  it "builds websocket urls from http and https base urls" do
    Crig::Providers::OpenAI.websocket_url("https://api.openai.com/v1").should eq("wss://api.openai.com/v1/responses")
    Crig::Providers::OpenAI.websocket_url("http://localhost:8080/v1").should eq("ws://localhost:8080/v1/responses")
    Crig::Providers::OpenAI.websocket_url("https://api.openai.com/v1/").should eq("wss://api.openai.com/v1/responses")

    expect_raises(Crig::Completion::CompletionError, /Unsupported base URL scheme/) do
      Crig::Providers::OpenAI.websocket_url("ftp://example.com/v1")
    end
  end

  it "parses websocket done events and exposes response ids" do
    done_event = Crig::Providers::OpenAI.parse_server_event(%({
      "type":"response.done",
      "response":{"id":"resp_done_1","status":"completed"}
    }))
    done_event.not_nil!.response_id.should eq("resp_done_1")
    done_event.not_nil!.is_terminal.should be_true
  end

  it "parses terminal response events" do
    completed_event = Crig::Providers::OpenAI.parse_server_event(%({
      "type":"response.completed",
      "sequence_number":12,
      "response":{
        "id":"resp_completed_1",
        "object":"response",
        "created_at":0,
        "status":"completed",
        "error":null,
        "incomplete_details":null,
        "instructions":null,
        "max_output_tokens":null,
        "model":"gpt-5.4",
        "usage":null,
        "output":[],
        "tools":[]
      }
    }))
    completed_event.not_nil!.is_terminal.should be_true
    completed_event.not_nil!.response_id.should eq("resp_completed_1")
  end

  it "parses live output item and content events" do
    item_event = Crig::Providers::OpenAI.parse_server_event(%({
      "type":"response.output_item.added",
      "item":{
        "id":"msg_1",
        "type":"message",
        "status":"in_progress",
        "content":[],
        "role":"assistant"
      },
      "output_index":0,
      "sequence_number":2
    }))
    item_event.not_nil!.kind.item?.should be_true

    content_event = Crig::Providers::OpenAI.parse_server_event(%({
      "type":"response.content_part.added",
      "content_index":0,
      "item_id":"msg_1",
      "output_index":0,
      "part":{"type":"output_text","text":""},
      "sequence_number":3
    }))
    content_event.not_nil!.kind.item?.should be_true

    delta_event = Crig::Providers::OpenAI.parse_server_event(%({
      "type":"response.output_text.delta",
      "content_index":0,
      "delta":"Web",
      "item_id":"msg_1",
      "output_index":0,
      "sequence_number":4
    }))
    delta_event.not_nil!.kind.item?.should be_true
  end

  it "skips unknown websocket events" do
    Crig::Providers::OpenAI.parse_server_event(%({"type":"response.some_future_event","data":"hello"})).should be_nil
  end

  it "raises on malformed known websocket events" do
    expect_raises(Exception) do
      Crig::Providers::OpenAI.parse_server_event(%({"type":"response.completed"}))
    end
  end

  it "rejects non-completed terminal responses" do
    failed = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(%({
      "id":"resp_failed_1",
      "object":"response",
      "created_at":0,
      "status":"failed",
      "error":{"code":"server_error","message":"failed response"},
      "incomplete_details":null,
      "instructions":null,
      "max_output_tokens":null,
      "model":"gpt-5.4",
      "usage":null,
      "output":[],
      "tools":[]
    }))

    expect_raises(Crig::Completion::CompletionError, /failed response/) do
      Crig::Providers::OpenAI.terminal_response_result(failed)
    end
  end
end
