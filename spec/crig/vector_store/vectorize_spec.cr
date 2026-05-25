require "../../spec_helper"

module Crig::VectorStore::Vectorize
  describe VectorizeError do
    it "builds HTTP errors" do
      err = VectorizeError.http_error(Exception.new("connection refused"))
      err.kind.http_error?.should be_true
      err.to_vector_store_error.kind.datastore_error?.should be_true
    end

    it "builds API errors with code and message" do
      err = VectorizeError.api_error(404_u32, "index not found")
      err.kind.api_error?.should be_true
      err.api_code.should eq(404)
      err.api_message.should eq("index not found")
    end

    it "builds serialization errors" do
      err = VectorizeError.serialization_error(JSON::ParseException.new("oops", 1, 1))
      err.kind.serialization_error?.should be_true
    end

    it "builds unsupported filter operation errors" do
      err = VectorizeError.unsupported_filter("$or")
      err.kind.unsupported_filter_operation?.should be_true
    end
  end

  describe VectorizeFilter do
    it "starts empty" do
      filter = VectorizeFilter.new
      filter.is_empty.should be_true
    end

    it "adds $eq operator" do
      filter = VectorizeFilter.new.eq("color", JSON.parse(%("red")))
      filter.is_empty.should be_false
      filter.raw["color"]["$eq"].as_s.should eq("red")
    end

    it "adds $ne operator" do
      filter = VectorizeFilter.new.ne("color", JSON.parse(%("red")))
      filter.raw["color"]["$ne"].as_s.should eq("red")
    end

    it "adds $gt operator" do
      filter = VectorizeFilter.new.gt("score", JSON.parse("10"))
      filter.raw["score"]["$gt"].as_i.should eq(10)
    end

    it "adds $gte operator" do
      filter = VectorizeFilter.new.gte("score", JSON.parse("10"))
      filter.raw["score"]["$gte"].as_i.should eq(10)
    end

    it "adds $lt operator" do
      filter = VectorizeFilter.new.lt("score", JSON.parse("100"))
      filter.raw["score"]["$lt"].as_i.should eq(100)
    end

    it "adds $lte operator" do
      filter = VectorizeFilter.new.lte("score", JSON.parse("100"))
      filter.raw["score"]["$lte"].as_i.should eq(100)
    end

    it "adds $in operator" do
      filter = VectorizeFilter.new.in_values("color", [
        JSON.parse(%("red")), JSON.parse(%("blue")),
      ])
      filter.raw["color"]["$in"].as_a.map(&.as_s).should eq(["red", "blue"])
    end

    it "adds $nin operator" do
      filter = VectorizeFilter.new.nin("color", [
        JSON.parse(%("green")),
      ])
      filter.raw["color"]["$nin"].as_a.map(&.as_s).should eq(["green"])
    end

    it "combines with AND (merges JSON objects)" do
      f = VectorizeFilter.new.eq("color", JSON.parse(%("red")))
        .and(VectorizeFilter.new.gt("score", JSON.parse("5")))
      f.raw["color"]["$eq"].as_s.should eq("red")
      f.raw["score"]["$gt"].as_i.should eq(5)
    end

    it "OR returns empty filter (not supported)" do
      f = VectorizeFilter.new.eq("color", JSON.parse(%("red")))
        .or(VectorizeFilter.new.gt("score", JSON.parse("5")))
      f.is_empty.should be_true
    end

    it "returns inner JSON with into_inner" do
      filter = VectorizeFilter.new.eq("color", JSON.parse(%("red")))
      filter.into_inner["color"]["$eq"].as_s.should eq("red")
    end

    it "exposes raw value via as_value" do
      filter = VectorizeFilter.new.eq("color", JSON.parse(%("red")))
      filter.as_value["color"]["$eq"].as_s.should eq("red")
    end
  end

  describe "generate_uuid_v4" do
    it "produces valid UUID v4 format" do
      uuid = Crig::VectorStore::Vectorize.generate_uuid_v4
      uuid.size.should eq(36)
      uuid[14].should eq('4')  # version nibble
      %w[8 9 A B].should contain(uuid[19].to_s)  # variant
      uuid.count('-').should eq(4)
    end

    it "produces unique values" do
      uuids = 10.times.map { Crig::VectorStore::Vectorize.generate_uuid_v4 }.to_a
      uuids.uniq.size.should eq(10)
    end
  end

  describe VectorizeClient do
    it "initializes with account, index, and token" do
      client = VectorizeClient.new("my-account", "my-index", "token-123")
      client.account_id.should eq("my-account")
      client.index_name.should eq("my-index")
    end
  end

  describe VectorizeVectorStore do
    it "initializes with model and credentials" do
      model = FakeEmbeddingsModel.new
      store = VectorizeVectorStore(FakeEmbeddingsModel).new(
        model, "account", "index", "token",
      )
      store.should be_a(VectorizeVectorStore(FakeEmbeddingsModel))
    end
  end

  describe QueryRequest do
    it "serializes to camelCase JSON" do
      req = QueryRequest.new(
        vector: [1.0, 2.0],
        top_k: 5_u64,
        return_metadata: ReturnMetadata::All,
      )
      json = req.to_json
      json.should contain(%("topK":5))
      json.should contain(%("returnMetadata":"all"))
    end
  end

  describe VectorInput do
    it "serializes for upsert" do
      input = VectorInput.new(
        id: "vec-1",
        values: [0.1, 0.2],
        metadata: JSON.parse(%({"key":"value"})),
      )
      json = input.to_json
      json.should contain(%("id":"vec-1"))
      json.should contain(%("values":[0.1,0.2]))
    end
  end
end

private class FakeEmbeddingsModel
  include Crig::Embeddings::EmbeddingModel

  def max_documents : Int32
    10
  end

  def ndims : Int32
    3
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    texts.map do |text|
      Crig::Embeddings::Embedding.new(text, [0.1, 0.2, 0.3])
    end.to_a
  end
end
