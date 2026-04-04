require "../src/crig"
require "crig-sqlite"

module Crig::Examples::SqliteVectorStore
  struct Document
    include JSON::Serializable
    include Crig::Embeddings::Embed
    include CrigSqlite::SqliteVectorStoreTable

    getter id : String
    getter title : String
    getter content : String
    getter category : String

    def initialize(@id : String, @title : String, @content : String, @category : String)
    end

    # SqliteVectorStoreTable instance methods
    def id : String
      @id
    end

    def column_values : Array(Tuple(String, CrigSqlite::ColumnValue))
      [
        {"id", @id.as(CrigSqlite::ColumnValue)},
        {"title", @title.as(CrigSqlite::ColumnValue)},
        {"content", @content.as(CrigSqlite::ColumnValue)},
        {"category", @category.as(CrigSqlite::ColumnValue)},
      ]
    end

    # SqliteVectorStoreTable class methods
    def self.name : String
      "documents"
    end

    def self.schema : Array(CrigSqlite::Column)
      [
        CrigSqlite::Column.new("id", "TEXT PRIMARY KEY"),
        CrigSqlite::Column.new("title", "TEXT"),
        CrigSqlite::Column.new("content", "TEXT"),
        CrigSqlite::Column.new("category", "TEXT"),
      ]
    end

    def self.from_db_row(row : DB::ResultSet) : self
      id = row.read(String)
      title = row.read(String)
      content = row.read(String)
      category = row.read(String)
      new(id, title, content, category)
    end

    # Embedding support
    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@content)
    end
  end
end

begin
  puts "Setting up SQLite Vector Store example with Ollama embeddings:"
  puts "  - Embeddings: Ollama nomic-embed-text (768 dimensions)"
  puts "  - Storage: SQLite with sqlite-vec extension"
  puts "  - Cost: Free (local Ollama)"
  puts ""

  # Initialize Ollama client
  puts "1. Setting up Ollama client..."
  client = Crig::Providers::Ollama::Client.new
  embedding_model = client.embedding_model("nomic-embed-text")
  puts "   ✓ Ollama client ready"
  puts "   - Model: nomic-embed-text"
  puts "   - Dimensions: #{embedding_model.ndims}"

  # Open SQLite database with vec extension
  puts "\n2. Opening SQLite database with vec extension..."
  db, extension_loaded = CrigSqlite::Extensions.open_with_vec(":memory:")

  unless extension_loaded
    STDERR.puts "   ❌ Failed to load SQLite Vec extension"
    STDERR.puts "   Please ensure vec0.dylib is in the lib/ directory"
    exit 1
  end
  puts "   ✓ Extension loaded successfully"

  # Create vector store
  puts "\n3. Creating vector store..."
  store = CrigSqlite::SqliteVectorStore(
    Crig::Providers::Ollama::EmbeddingModel,
    Crig::Examples::SqliteVectorStore::Document,
  ).new(db, embedding_model)
  store.create_table(embedding_model.ndims)
  puts "   ✓ Tables created with #{embedding_model.ndims} dimensions"

  # Create sample documents
  puts "\n4. Creating sample documents..."
  documents = [
    Crig::Examples::SqliteVectorStore::Document.new("doc1", "AI Research",
      "Recent breakthroughs in artificial intelligence research.", "technology"),
    Crig::Examples::SqliteVectorStore::Document.new("doc2", "Machine Learning",
      "A beginner's guide to machine learning algorithms.", "education"),
    Crig::Examples::SqliteVectorStore::Document.new("doc3", "Climate Change",
      "Latest findings on global climate change impacts.", "science"),
    Crig::Examples::SqliteVectorStore::Document.new("doc4", "Healthy Cooking",
      "Nutritious recipes for a healthy lifestyle.", "lifestyle"),
    Crig::Examples::SqliteVectorStore::Document.new("doc5", "Space Exploration",
      "New discoveries in space exploration missions.", "science"),
  ]
  puts "   ✓ Created #{documents.size} documents"

  # Generate embeddings using crig's EmbeddingsBuilder
  puts "\n5. Generating embeddings with crig's EmbeddingsBuilder..."
  embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
    .document(Crig::Examples::SqliteVectorStore::Document.new("doc1", "AI Research",
      "Recent breakthroughs in artificial intelligence research.", "technology"))
    .document(Crig::Examples::SqliteVectorStore::Document.new("doc2", "Machine Learning",
      "A beginner's guide to machine learning algorithms.", "education"))
    .document(Crig::Examples::SqliteVectorStore::Document.new("doc3", "Climate Change",
      "Latest findings on global climate change impacts.", "science"))
    .document(Crig::Examples::SqliteVectorStore::Document.new("doc4", "Healthy Cooking",
      "Nutritious recipes for a healthy lifestyle.", "lifestyle"))
    .document(Crig::Examples::SqliteVectorStore::Document.new("doc5", "Space Exploration",
      "New discoveries in space exploration missions.", "science"))
    .build

  puts "   ✓ Generated #{embeddings.size} embeddings"

  # Add documents with embeddings to store
  puts "\n6. Adding documents to SQLite vector store..."
  store.add_rows(embeddings)
  puts "   ✓ Documents stored"

  # Create vector index
  puts "\n7. Creating vector index..."
  index = store.index(embedding_model)
  puts "   ✓ Index created"

  # Perform vector search
  puts "\n8. Performing vector search:"
  puts "=" * 60

  query = "scientific discoveries and research"
  puts "Query: \"#{query}\""

  request = Crig::VectorStore::VectorSearchRequest(CrigSqlite::SqliteSearchFilter).builder
    .query(query)
    .samples(3_u64)
    .build

  results = index.top_n(request, Crig::Examples::SqliteVectorStore::Document)

  puts "\nTop #{results.size} results:"
  results.each_with_index do |(score, doc_id, doc), i|
    puts "  #{i + 1}. [#{score.round(4)}] #{doc.title}"
    puts "     Category: #{doc.category}"
    puts "     Content: #{doc.content}"
  end

  # Perform filtered search
  puts "\n9. Performing filtered vector search:"
  puts "=" * 60

  filter = CrigSqlite::SqliteSearchFilter.eq("category", JSON::Any.new("science"))

  filtered_request = Crig::VectorStore::VectorSearchRequest(CrigSqlite::SqliteSearchFilter).builder
    .query(query)
    .samples(3_u64)
    .filter(filter)
    .build

  filtered_results = index.top_n(filtered_request, Crig::Examples::SqliteVectorStore::Document)

  puts "Query: \"#{query}\" (filter: category = 'science')"
  puts "\nResults:"
  if filtered_results.empty?
    puts "  No results matching filter"
  else
    filtered_results.each_with_index do |(score, doc_id, doc), i|
      puts "  #{i + 1}. [#{score.round(4)}] #{doc.title}"
    end
  end

  db.close

  puts "\n" + "=" * 60
  puts "Summary:"
  puts "1. Used crig's EmbeddingsBuilder to generate embeddings with Ollama"
  puts "2. Stored documents with embeddings in SQLite using sqlite-vec"
  puts "3. Performed vector similarity search with filtering"
  puts ""
  puts "Benefits of SQLite vector store:"
  puts "• Persistent storage - data survives process restarts"
  puts "• SQL queries - combine vector search with SQL filters"
  puts "• Lightweight - no separate database server needed"
  puts "• ACID transactions - data integrity guaranteed"
rescue ex : CrigSqlite::SqliteError::DatabaseError
  STDERR.puts "Database error: #{ex.message}"
  STDERR.puts "This usually means the SQLite Vec extension is not loaded."
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
