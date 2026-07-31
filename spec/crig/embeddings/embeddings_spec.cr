require "../../spec_helper"
describe Crig::Embeddings do
  it "wraps embed errors with the original message" do
    Crig::Embeddings::EmbedError.new(Exception.new("boom")).message.should eq("boom")
  end

  it "builds parity-style embedding errors" do
    http = Crig::Embeddings::EmbeddingError.http_error(Exception.new("timeout"))
    http.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::HttpError)
    http.message.should eq("HttpError: timeout")
    http.source_error.try(&.message).should eq("timeout")

    json = Crig::Embeddings::EmbeddingError.json_error(Exception.new("bad json"))
    json.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::JsonError)
    json.message.should eq("JsonError: bad json")

    url = Crig::Embeddings::EmbeddingError.url_error(Exception.new("bad url"))
    url.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::UrlError)
    url.message.should eq("UrlError: bad url")

    document = Crig::Embeddings::EmbeddingError.document_error(Exception.new("bad document"))
    document.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::DocumentError)
    document.message.should eq("DocumentError: bad document")

    response = Crig::Embeddings::EmbeddingError.response_error("missing vector")
    response.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::ResponseError)
    response.message.should eq("ResponseError: missing vector")

    provider = Crig::Embeddings::EmbeddingError.provider_error("rate limited")
    provider.kind.should eq(Crig::Embeddings::EmbeddingError::Kind::ProviderError)
    provider.message.should eq("ProviderError: rate limited")
  end

  it "collects texts from embeddable values" do
    Crig::Embeddings.to_texts(ExampleEmbedding.new(["hello", "world"])).should eq(["hello", "world"])
  end

  it "wraps embed failures as embed errors during text extraction" do
    error = expect_raises(Crig::Embeddings::EmbedError, "embed exploded") do
      Crig::Embeddings.to_texts(FailingExampleEmbedding.new)
    end

    error.message.should eq("embed exploded")
  end

  it "ports test_custom_embed" do
    definition = DerivedWordDefinitionCustom.new(
      "doc1",
      "house",
      DerivedDefinition.new(
        "a building in which people live; residence for human beings.",
        "https://www.dictionary.com/browse/house",
        "noun"
      )
    )

    Crig::Embeddings.to_texts(definition).should eq([
      %({"word":"a building in which people live; residence for human beings.","link":"https://www.dictionary.com/browse/house","speech":"noun"}),
    ])
  end

  it "ports test_custom_and_basic_embed" do
    definition = DerivedWordDefinitionCustomAndBasic.new(
      "doc1",
      "house",
      DerivedDefinition.new(
        "a building in which people live; residence for human beings.",
        "https://www.dictionary.com/browse/house",
        "noun"
      )
    )

    Crig::Embeddings.to_texts(definition).should eq([
      "house",
      %({"word":"a building in which people live; residence for human beings.","link":"https://www.dictionary.com/browse/house","speech":"noun"}),
    ])
  end

  it "ports test_single_embed" do
    definition = "a building in which people live; residence for human beings."
    word_definition = DerivedWordDefinitionSingle.new("doc1", "house", definition)

    Crig::Embeddings.to_texts(word_definition).should eq([definition])
  end

  it "ports test_embed_vec_non_string" do
    company = DerivedCompanyAges.new("doc1", "Google", [25, 30, 35, 40])

    Crig::Embeddings.to_texts(company).should eq(["25", "30", "35", "40"])
  end

  it "ports test_embed_vec_string" do
    company = DerivedCompanyNames.new("doc1", "Google", ["Alice", "Bob", "Charlie", "David"])

    Crig::Embeddings.to_texts(company).should eq(["Alice", "Bob", "Charlie", "David"])
  end

  it "ports test_multiple_embed_tags" do
    company = DerivedCompanyMultiple.new("doc1", "Google", [25, 30, 35, 40])

    Crig::Embeddings.to_texts(company).should eq(["Google", "25", "30", "35", "40"])
  end

  it "collects texts from primitives" do
    Crig::Embeddings.to_texts(42).should eq(["42"])
    Crig::Embeddings.to_texts(true).should eq(["true"])
  end

  it "collects texts from json and hash-like values" do
    json = JSON.parse(%({"hello":"world"}))

    Crig::Embeddings.to_texts(json).should eq([%({"hello":"world"})])
    Crig::Embeddings.to_texts({"hello" => "world"}).should eq([%({"hello":"world"})])
    Crig::Embeddings.to_texts({"hello", 42}).should eq(["hello", "42"])
  end

  it "stores embeddings and compares them by document" do
    left = Crig::Embeddings::Embedding.new("doc", [1.0, 2.0])
    right = Crig::Embeddings::Embedding.new("doc", [9.0])

    left.should eq(right)
    left.vec.should eq([1.0, 2.0])
  end

  it "supports single-text embedding through the model helper" do
    embedding = FakeEmbeddingModel.new.embed_text("hello")

    embedding.document.should eq("hello")
    embedding.vec.should eq([5.0, 0.0, 1.0])
  end

  it "supports single-image embedding through the image model helper" do
    embedding = FakeImageEmbeddingModel.new.embed_image(Bytes[1_u8, 2_u8, 3_u8])

    embedding.document.should eq("image:3")
    embedding.vec.should eq([3.0, 1.0])
  end

  it "computes dot product" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.dot_product(embedding_2).should eq(32.0)
  end

  it "computes cosine similarity" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.cosine_similarity(embedding_2, false).should eq(0.9875414397573881)
  end

  it "computes angular distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.angular_distance(embedding_2, false).should eq(0.0502980301830343)
  end

  it "computes euclidean distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.euclidean_distance(embedding_2).should eq(5.0)
  end

  it "computes manhattan distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.manhattan_distance(embedding_2).should eq(7.0)
  end

  it "computes chebyshev distance" do
    embedding_1 = Crig::Embeddings::Embedding.new("test", [1.0, 2.0, 3.0])
    embedding_2 = Crig::Embeddings::Embedding.new("test", [1.0, 5.0, 7.0])

    embedding_1.chebyshev_distance(embedding_2).should eq(4.0)
  end

  it "builds a tool schema from a dynamic tool embedding" do
    schema = Crig::Embeddings::ToolSchema.try_from(FakeToolEmbedding.new)

    schema.name.should eq("nothing")
    schema.context["category"].as_s.should eq("utility")
    schema.embedding_docs.should eq(["Do nothing."])
    Crig::Embeddings.to_texts(schema).should eq(["Do nothing."])
  end

  it "builds embeddings for a single document" do
    results = Crig::Embeddings::EmbeddingsBuilder(FakeEmbeddingModel, ExampleMultiEmbedding)
      .new(FakeEmbeddingModel.new)
      .document(ExampleMultiEmbedding.new("doc0", ["alpha", "beta"]))
      .build

    results.size.should eq(1)
    results[0][0].id.should eq("doc0")
    results[0][1].to_a.map(&.document).should eq(["alpha", "beta"])
  end

  it "wraps embed failures as embed errors during builder document collection" do
    expect_raises(Crig::Embeddings::EmbedError, "embed exploded") do
      Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
        .document(FailingExampleEmbedding.new)
    end
  end

  it "builds embeddings from chained simple documents" do
    results = Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
      .simple_document("doc0", "alpha")
      .simple_document("doc1", "beta")
      .build

    results.map(&.[0].id).should eq(["doc0", "doc1"])
    results.map { |entry| entry[1].first.document }.should eq(["alpha", "beta"])
  end

  it "builds embeddings from all simple documents at once" do
    results = Crig::Embeddings::EmbeddingsBuilder.new(FakeEmbeddingModel.new)
      .all_simple_documents([{"doc0", "alpha"}, {"doc1", "beta"}])
      .build

    results.map(&.[0].id).should eq(["doc0", "doc1"])
    results.map { |entry| entry[1].first.document }.should eq(["alpha", "beta"])
  end

  it "builds embeddings for one or many documents" do
    results = Crig::Embeddings::EmbeddingsBuilder(FakeEmbeddingModel, ExampleMultiEmbedding)
      .new(FakeEmbeddingModel.new)
      .documents([
        ExampleMultiEmbedding.new("doc0", ["alpha", "beta"]),
        ExampleMultiEmbedding.new("doc1", ["gamma"]),
      ])
      .build

    results.size.should eq(2)
    results[0][0].id.should eq("doc0")
    results[0][1].to_a.map(&.document).should eq(["alpha", "beta"])
    results[1][0].id.should eq("doc1")
    results[1][1].to_a.map(&.document).should eq(["gamma"])
  end
end
