require "../../../../spec_helper"

describe Crig::Providers::OpenAI::ItemChunk do
  it "deserializes content part added and done events with snake_case part types" do
    added = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.content_part.added",
      "item_id":"msg_1",
      "output_index":0,
      "content_index":0,
      "sequence_number":3,
      "part":{"type":"output_text","text":"hello"}
    }))
    done = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.content_part.done",
      "item_id":"msg_1",
      "output_index":0,
      "content_index":0,
      "sequence_number":4,
      "part":{"type":"summary_text","text":"done"}
    }))

    added.data.should be_a(Crig::Providers::OpenAI::ContentPartAdded)
    done.data.should be_a(Crig::Providers::OpenAI::ContentPartDone)
  end

  it "deserializes reasoning summary part added and done events with snake_case part types" do
    added = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.reasoning_summary_part.added",
      "item_id":"rs_1",
      "output_index":0,
      "summary_index":0,
      "sequence_number":5,
      "part":{"type":"summary_text","text":"hello"}
    }))
    done = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.reasoning_summary_part.done",
      "item_id":"rs_1",
      "output_index":0,
      "summary_index":0,
      "sequence_number":6,
      "part":{"type":"summary_text","text":"done"}
    }))

    added.data.should be_a(Crig::Providers::OpenAI::ReasoningSummaryPartAdded)
    done.data.should be_a(Crig::Providers::OpenAI::ReasoningSummaryPartDone)
  end
end
