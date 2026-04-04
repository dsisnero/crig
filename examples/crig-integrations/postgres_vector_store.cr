require "../../src/crig"
require "crig-postgres"

module Crig::Integrations::PostgresVectorStore
  struct Document
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter title : String
    getter content : String
    getter category : String

    def initialize(@id : String, @title : String, @content : String, @category : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@content)
    end
  end
end

begin
  puts "Setting up PostgreSQL Vector Store example with Ollama embeddings:"
  puts "  - Embeddings: Ollama nomic-embed-text (768 dimensions)"
  puts "  - Storage: PostgreSQL with pgvector extension"
  puts "  - Cost: Free (local Ollama)"
  puts ""

  # Initialize Ollama client
  puts "1. Setting up Ollama client..."
  client = Crig::Providers::Ollama::Client.new
  embedding_model = client.embedding_model("nomic-embed-text")
  puts "   ✓ Ollama client ready"
  puts "   - Model: nomic-embed-text"
  puts "   - Dimensions: #{embedding_model.ndims}"

  # Connect to PostgreSQL
  database_url = ENV["DATABASE_URL"]?
  unless database_url
    STDERR.puts "Error: DATABASE_URL not set"
    STDERR.puts "Usage: DATABASE_URL=postgresql://user:pass@host:port/db crystal run examples/crig-integrations/postgres_vector_store.cr"
    exit 1
  end

  puts "\n2. Connecting to PostgreSQL..."
  db = DB.open(database_url)
  puts "   ✓ Connected"

  # Create vector store
  puts "\n3. Creating vector store..."
  store = CrigPostgres::PostgresVectorStore.new(
    embedding_model: embedding_model,
    db: db,
    documents_table: "documents",
    distance_function: CrigPostgres::PgVectorDistanceFunction::Cosine
  )
  store.create_table(dims: embedding_model.ndims)
  puts "   ✓ Tables created"

  # Create sample documents
  puts "\n4. Creating sample documents..."
  documents = [
    Crig::Integrations::PostgresVectorStore::Document.new("doc1", "AI Research",
      "Recent breakthroughs in artificial intelligence research.", "technology"),
    Crig::Integrations::PostgresVectorStore::Document.new("doc2", "Machine Learning",
      "A beginner's guide to machine learning algorithms.", "education"),
    Crig::Integrations::PostgresVectorStore::Document.new("doc3", "Climate Change",
      "Latest findings on global climate change impacts.", "science"),
    Crig::Integrations::PostgresVectorStore::Document.new("doc4", "Healthy Cooking",
      "Nutritious recipes for a healthy lifestyle.", "lifestyle"),
    Crig::Integrations::PostgresVectorStore::Document.new("doc5", "Space Exploration",
      "New discoveries in space exploration missions.", "science"),
  ]
  puts "   ✓ Created #{documents.size} documents"

  # Generate embeddings using crig's EmbeddingsBuilder
  puts "\n5. Generating embeddings with crig's EmbeddingsBuilder..."
  embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
    .document(documents[0])
    .document(documents[1])
    .document(documents[2])
    .document(documents[3])
    .document(documents[4])
    .build
  puts "   ✓ Generated #{embeddings.size} embeddings"

  # Insert documents with embeddings
  puts "\n6. Adding documents to PostgreSQL vector store..."
  embeddings.each do |doc, embedding_or_many|
    # Convert OneOrMany to Array and Crig::Embedding to CrigPostgres::Embedding
    case embedding_or_many
    when Crig::OneOrMany(Crig::Embeddings::Embedding)
      arr = embedding_or_many.to_a.map { |e| CrigPostgres::Embedding.new(e.document, e.vec) }
      store.insert_documents([{doc, arr}])
    end
  end
  puts "   ✓ Documents stored"

  # Perform vector search
  puts "\n7. Performing vector search:"
  puts "=" * 60

  query = "scientific discoveries and research"
  puts "Query: \"#{query}\""

  req = CrigPostgres::VectorSearchRequest(CrigPostgres::PgSearchFilter).builder
    .query(query)
    .samples(3_u64)
    .build

  results = store.top_n(req, Crig::Integrations::PostgresVectorStore::Document)

  puts "\nTop #{results.size} results:"
  results.each_with_index do |(score, id, doc), i|
    puts "  #{i + 1}. [#{score.round(4)}] #{doc.title}"
    puts "     Category: #{doc.category}"
    puts "     Content: #{doc.content}"
  end

  # Perform filtered search
  puts "\n8. Performing filtered search:"
  puts "=" * 60

  filter = CrigPostgres::PgSearchFilter.eq("category", JSON::Any.new("science"))

  filtered_req = CrigPostgres::VectorSearchRequest(CrigPostgres::PgSearchFilter).builder
    .query(query)
    .samples(3_u64)
    .filter(filter)
    .build

  filtered_results = store.top_n(filtered_req, Crig::Integrations::PostgresVectorStore::Document)

  puts "Query: \"#{query}\" (filter: category = 'science')"
  puts "\nResults:"
  filtered_results.each_with_index do |(score, id, doc), i|
    puts "  #{i + 1}. [#{score.round(4)}] #{doc.title}"
  end

  db.close

  puts "\n" + "=" * 60
  puts "Summary:"
  puts "1. Used crig's EmbeddingsBuilder with Ollama embeddings"
  puts "2. Stored documents with embeddings in PostgreSQL"
  puts "3. Performed vector similarity search"
  puts "4. Demonstrated filtered search with SQL WHERE clauses"
  puts ""
  puts "Benefits of PostgreSQL vector store:"
  puts "• Persistent storage - data survives process restarts"
  puts "• SQL queries - combine vector search with SQL filters"
  puts "• ACID transactions - data integrity guaranteed"
  puts "• Scales to large datasets with proper indexing"
rescue ex : KeyError
  STDERR.puts "Error: Missing API key or configuration"
  STDERR.puts "Please ensure Ollama is running locally"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
