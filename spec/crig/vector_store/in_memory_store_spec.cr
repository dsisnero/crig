require "../../spec_helper"

describe Crig::InMemoryVectorStore do
  it "auto generates document ids in insertion order" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents([
        {
          "glarb-garb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
          ),
        },
        {
          "marble-marble",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("marble-marble", [0.7, -0.3, 0.0]),
          ),
        },
        {
          "flumb-flumb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("flumb-flumb", [0.3, 0.7, 0.1]),
          ),
        },
      ])
      .build

    store.add_documents([
      {
        "brotato",
        Crig::OneOrMany(Crig::Embeddings::Embedding).one(
          Crig::Embeddings::Embedding.new("brotato", [0.3, 0.7, 0.1]),
        ),
      },
      {
        "ping-pong",
        Crig::OneOrMany(Crig::Embeddings::Embedding).one(
          Crig::Embeddings::Embedding.new("ping-pong", [0.7, -0.3, 0.0]),
        ),
      },
    ])

    entries = store.embeddings.to_a.sort_by!(&.[0])
    ids = entries.map(&.[0])

    ids.should eq(["doc0", "doc1", "doc2", "doc3", "doc4"])
  end

  it "ranks a single embedding search correctly" do
    store = Crig::InMemoryVectorStore(String).builder
      .index_strategy(Crig::IndexStrategy.lsh(5, 10))
      .documents_with_ids([
        {
          "doc1",
          "glarb-garb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("glarb-garb", [0.1, 0.1, 0.5]),
          ),
        },
        {
          "doc2",
          "marble-marble",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("marble-marble", [0.7, -0.3, 0.0]),
          ),
        },
        {
          "doc3",
          "flumb-flumb",
          Crig::OneOrMany(Crig::Embeddings::Embedding).one(
            Crig::Embeddings::Embedding.new("flumb-flumb", [0.3, 0.7, 0.1]),
          ),
        },
      ])
      .build

    query = Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6])
    results = store.vector_search(query, 1)

    results.size.should eq(1)
    results[0].id.should eq("doc1")
    results[0].document.should eq("glarb-garb")
    results[0].score.should be_close(0.9807965956109156, 1e-10)
  end

  it "picks the best embedding when multiple embeddings exist per document" do
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

    query = Crig::Embeddings::Embedding.new("glarby-glarble", [0.0, 0.1, 0.6])
    results = store.vector_search(query, 1)

    results.size.should eq(1)
    results[0].id.should eq("doc1")
    results[0].document.should eq("glarb-garb")
    results[0].score.should be_close(0.9807965956109156, 1e-10)
  end
end
