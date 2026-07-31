require "../../spec_helper"

describe Crig::FilterError do
  it "builds parity-style filter errors" do
    Crig::FilterError.expected("json object", "string").message.should eq("Expected: json object, got: string")
    Crig::FilterError.type_error("non-JSON filter value").message.should eq("Cannot compile 'non-JSON filter value' to the backend's filter type")
    Crig::FilterError.missing_field("metadata.topic").message.should eq("Missing field 'metadata.topic'")
    Crig::FilterError.must("samples", "be positive").message.should eq("'samples' must be positive")
    Crig::FilterError.serialization("boom").message.should eq("Filter serialization failed: boom")
  end
end

describe Crig::VectorStoreError do
  it "builds parity-style vector store errors" do
    embedding = Crig::VectorStoreError.embedding_error(Exception.new("embed boom"))
    embedding.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::EmbeddingError)
    embedding.message.should eq("Embedding error: embed boom")
    embedding.source_error.try(&.message).should eq("embed boom")

    datastore = Crig::VectorStoreError.datastore_error(Exception.new("db boom"))
    datastore.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::DatastoreError)
    datastore.message.should eq("Datastore error: db boom")

    filter = Crig::VectorStoreError.filter_error(Crig::FilterError.missing_field("metadata.topic"))
    filter.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::FilterError)
    filter.message.should eq("Filter error: Missing field 'metadata.topic'")

    missing_id = Crig::VectorStoreError.missing_id("doc-1")
    missing_id.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::MissingIdError)
    missing_id.message.should eq("Missing Id: doc-1")

    external = Crig::VectorStoreError.external_api_error(429, "rate limited")
    external.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::ExternalApiError)
    external.status_code.should eq(429)
    external.message.should eq("External call to API returned an error. Error code: 429 Message: rate limited")

    builder = Crig::BuilderError.new("`query` is missing")
    builder.kind.should eq(Crig::VectorStore::VectorStoreError::Kind::BuilderError)
    builder.message.should eq("Error while building VectorSearchRequest: `query` is missing")
  end
end

describe Crig::Filter do
  it "preserves the upstream satisfies semantics" do
    eq_filter = Crig::Filter.eq("topic", JSON.parse(%("crystal")))
    gt_filter = Crig::Filter.gt("score", JSON.parse(%(3)))
    lt_filter = Crig::Filter.lt("score", JSON.parse(%(3)))

    eq_filter.satisfies(JSON.parse(%({"topic":"crystal"}))).should be_true
    eq_filter.satisfies(JSON.parse(%({"topic":"other"}))).should be_false
    gt_filter.satisfies(JSON.parse(%({"score":4}))).should be_false
    lt_filter.satisfies(JSON.parse(%({"score":2}))).should be_false
  end

  it "evaluates composed filters recursively" do
    left = Crig::Filter.eq("topic", JSON.parse(%("crystal")))
    right = Crig::Filter.eq("kind", JSON.parse(%("guide")))

    left.and_(right).satisfies(JSON.parse(%({"topic":"crystal"}))).should be_false
    left.or_(right).satisfies(JSON.parse(%({"topic":"crystal"}))).should be_true
  end
end

describe Crig::IndexStrategy do
  it "defaults to brute force and exposes lsh settings" do
    brute_force = Crig::IndexStrategy.brute_force
    lsh = Crig::IndexStrategy.lsh(5, 10)

    brute_force.brute_force?.should be_true
    brute_force.lsh?.should be_false
    lsh.lsh?.should be_true
    lsh.num_tables.should eq(5)
    lsh.num_hyperplanes.should eq(10)
  end
end

describe Crig::InMemoryVectorStoreBuilder(String) do
  it "builds stores with explicit ids and a custom strategy" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {"doc-a", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc-b", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
      ])
      .build

    store.index_strategy.lsh?.should be_true
    store.len.should eq(2)
    store.embeddings["doc-a"][0].should eq("glarb-garb")
    store.embeddings["doc-b"][1].first.document.should eq("marble-marble")
  end

  it "assigns auto ids using the current builder size" do
    store = Crig::InMemoryVectorStore(String).builder
      .documents([
        {"glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
        {"flumb-flumb", vector_embedding("flumb-flumb", [0.3, 0.7, 0.1])},
      ])
      .build

    store.add_documents([
      {"brotato", vector_embedding("brotato", [0.3, 0.7, 0.1])},
      {"ping-pong", vector_embedding("ping-pong", [0.7, -0.3, 0.0])},
    ])

    store.embeddings.keys.sort!.should eq(["doc0", "doc1", "doc2", "doc3", "doc4"])
    store.embeddings["doc3"][0].should eq("brotato")
    store.embeddings["doc4"][0].should eq("ping-pong")
  end

  it "supports ids generated from documents" do
    store = Crig::InMemoryVectorStore(String).builder
      .documents_with_id_f([
        {"first", vector_embedding("first", [1.0, 0.0])},
        {"second", vector_embedding("second", [0.0, 1.0])},
      ]) { |document| "id-#{document}" }
      .build

    store.embeddings.keys.sort!.should eq(["id-first", "id-second"])
  end
end

describe Crig::InMemoryVectorStore(String) do
  it "builds from document helpers and exposes collection accessors" do
    store = Crig::InMemoryVectorStore(String).from_documents_with_ids([
      {"doc-1", "first", vector_embedding("first", [1.0, 0.0])},
      {"doc-2", "second", vector_embedding("second", [0.0, 1.0])},
    ])

    iterated_ids = store.iter.map(&.[0]).to_a.sort!

    store.empty?.should be_false
    store.len.should eq(2)
    iterated_ids.should eq(["doc-1", "doc-2"])
  end

  it "matches the upstream single-embedding ranking behavior" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {"doc1", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc2", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
        {"doc3", "flumb-flumb", vector_embedding("flumb-flumb", [0.3, 0.7, 0.1])},
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6]),
      1,
    )

    ranking.map { |result| {result.score, result.id, result.document} }.should eq([
      {0.9807965956109156, "doc1", "glarb-garb"},
    ])
  end

  it "uses the best embedding per document when ranking" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {
          "doc1",
          "glarb-garb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
            Crig::Embeddings::Embedding.new("don't-choose-me", [-0.5, 0.9, 0.1]),
          ]),
        },
        {
          "doc2",
          "marble-marble",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("marble-marble", [0.7, -0.3, 0.0]),
            Crig::Embeddings::Embedding.new("sandwich", [0.5, 0.5, -0.7]),
          ]),
        },
        {
          "doc3",
          "flumb-flumb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).many([
            Crig::Embeddings::Embedding.new("flumb-flumb", [0.3, 0.7, 0.1]),
            Crig::Embeddings::Embedding.new("banana", [0.1, -0.5, -0.5]),
          ]),
        },
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6]),
      1,
    )

    ranking.map { |result| {result.score, result.id, result.document, result.embedding_document} }.should eq([
      {0.9807965956109156, "doc1", "glarb-garb", "glarb-garb"},
    ])
  end

  it "uses the configured lsh index when the strategy requests it" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(3, 5))
      .documents_with_ids([
        {"doc1", "glarb-garb", vector_embedding("glarb-garb", [0.1, 0.1, 0.5])},
        {"doc2", "marble-marble", vector_embedding("marble-marble", [0.7, -0.3, 0.0])},
      ])
      .build

    ranking = store.vector_search(
      Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
      1,
    )

    ranking.size.should eq(1)
    ranking[0].id.should eq("doc1")
  end
end

describe Crig::InMemoryVectorStore(StoredDoc) do
  it "returns stored documents by id with typed deserialization" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0])},
      {"doc-2", StoredDoc.new("doc-2", "second"), vector_embedding("second", [0.0, 1.0])},
    ])

    document = store.get_document("doc-2", StoredDoc)

    document.should_not be_nil
    document = document.as(StoredDoc)
    document.id.should eq("doc-2")
    document.name.should eq("second")
    store.get_document("missing", StoredDoc).should be_nil
  end

  it "wraps the store in an index facade" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0])},
    ])

    index = store.index(FakeEmbeddingModel.new)

    index.model.should be_a(FakeEmbeddingModel)
    index.store.len.should eq(1)
    index.len.should eq(1)
    index.empty?.should be_false
    index.iter.map(&.[0]).to_a.should eq(["doc-1"])
  end

  it "returns typed top-n results through the index facade" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
      {"doc-2", StoredDoc.new("doc-2", "second"), vector_embedding("second", [0.0, 1.0, 0.0])},
    ])
    index = store.index(FakeEmbeddingModel.new)
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    results = index.top_n(request, StoredDoc)

    results.size.should eq(1)
    results[0][1].should eq("doc-1")
    results[0][2].name.should eq("first")
    index.top_n_ids(request).should eq([{results[0][0], "doc-1"}])
  end

  it "builds vector-store output payloads from index calls" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])
    index = store.index(FakeEmbeddingModel.new)
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    outputs = index.call(request)

    outputs.size.should eq(1)
    outputs[0].id.should eq("doc-1")
    outputs[0].document["name"].as_s.should eq("first")
  end

  it "exposes a tool definition for vector-store calls" do
    store = Crig::InMemoryVectorStore(StoredDoc).from_documents_with_ids([
      {"doc-1", StoredDoc.new("doc-1", "first"), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])

    definition = Crig.tool_definition(store.index(FakeEmbeddingModel.new))

    definition.name.should eq("search_vector_store")
    definition.parameters["required"].as_a.map(&.as_s).should eq(["query", "samples"])
  end
end

describe Crig::InMemoryVectorStore(JSON::Any) do
  it "prunes oversized arrays from dynamic vector-store output" do
    large_array = Array.new(401) { 1 }
    document = JSON.parse({"name" => "first", "huge" => large_array}.to_json)
    store = Crig::InMemoryVectorStore(JSON::Any).from_documents_with_ids([
      {"doc-1", document, vector_embedding("first", [1.0, 0.0, 0.0])},
    ])
    request = Crig::VectorSearchRequest.builder.query("first").samples(1).build

    outputs = store.index(FakeEmbeddingModel.new).call(request)

    outputs[0].document["name"].as_s.should eq("first")
    outputs[0].document["huge"]?.should be_nil
  end

  it "supports insert_documents as a store helper" do
    store = Crig::InMemoryVectorStore(JSON::Any).new
    store.insert_documents([
      {JSON.parse(%({"name":"first"})), vector_embedding("first", [1.0, 0.0, 0.0])},
    ])

    store.len.should eq(1)
    store.embeddings["doc0"][0]["name"].as_s.should eq("first")
  end
end

describe Crig::LSH do
  it "builds deterministic hyperplanes for the same shape" do
    left = Crig::LSH.new(3, 2, 4)
    right = Crig::LSH.new(3, 2, 4)

    left.hyperplanes.should eq(right.hyperplanes)
    left.hash([0.1, 0.2, 0.3], 0).should eq(right.hash([0.1, 0.2, 0.3], 0))
  end

  it "hashes vectors per table into bitsets" do
    lsh = Crig::LSH.new(3, 2, 4)
    hash = lsh.hash([0.1, 0.2, 0.3], 1)

    hash.should be_a(UInt64)
    hash.should be >= 0_u64
  end
end

describe Crig::LSHIndex do
  it "returns inserted ids for matching query buckets" do
    index = Crig::LSHIndex.new(3, 3, 5)
    embedding = [0.1, 0.2, 0.3]

    index.insert("doc-1", embedding)
    index.insert("doc-1", embedding)
    index.insert("doc-2", [-0.1, 0.4, 0.3])

    candidates = index.query(embedding)

    candidates.includes?("doc-1").should be_true
    candidates.count("doc-1").should eq(1)
  end

  it "clears all tables" do
    index = Crig::LSHIndex.new(3, 2, 4)
    embedding = [0.1, 0.2, 0.3]

    index.insert("doc-1", embedding)
    index.clear

    index.query(embedding).should eq([] of String)
  end
end
