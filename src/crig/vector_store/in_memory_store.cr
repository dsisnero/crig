module Crig
  module VectorStore
    record SearchResult(D), score : Float64, id : String, document : D, embedding_document : String
    alias TopNResults = Array(Tuple(Float64, String, JSON::Any))

    # Interface for vector store indices
    # Types implementing this interface can be used with Agent.dynamic_context
    module VectorStoreIndex(M, D)
      # Returns the top N most similar documents as (score, id, JSON::Any) tuples
      abstract def top_n_results(request : Crig::VectorSearchRequest) : TopNResults
    end

    struct InMemoryVectorIndex(M, D)
      include VectorStoreIndex(M, D)

      getter model : M
      getter store : InMemoryVectorStore(D)

      def initialize(@model : M, @store : InMemoryVectorStore(D))
      end

      def iter
        @store.iter
      end

      def len : Int32
        @store.len
      end

      def empty? : Bool
        @store.empty?
      end

      def top_n(request : Crig::VectorSearchRequest, type : T.class) : Array(Tuple(Float64, String, T)) forall T
        prompt_embedding = @model.embed_text(request.query)
        @store.vector_search(prompt_embedding, request.samples.to_i).map do |result|
          {
            result.score,
            result.id,
            T.from_json(result.document.to_json),
          }
        end
      end

      def top_n_ids(request : Crig::VectorSearchRequest) : Array(Tuple(Float64, String))
        prompt_embedding = @model.embed_text(request.query)
        @store.vector_search(prompt_embedding, request.samples.to_i).map do |result|
          {result.score, result.id}
        end
      end

      def top_n_results(request : Crig::VectorSearchRequest) : TopNResults
        prompt_embedding = @model.embed_text(request.query)
        @store.vector_search(prompt_embedding, request.samples.to_i).map do |result|
          {
            result.score,
            result.id,
            JSON.parse(result.document.to_json),
          }
        end
      end

      def dynamic_top_n(request : Crig::VectorSearchRequest) : TopNResults
        top_n_results(request).map do |score, id, document|
          {score, id, Crig::VectorStore.prune_document(document) || JSON.parse(%({}))}
        end
      end

      def dynamic_top_n_ids(request : Crig::VectorSearchRequest) : Array(Tuple(Float64, String))
        top_n_ids(request)
      end

      def definition : Crig::Completion::ToolDefinition
        Crig::Completion::ToolDefinition.new(
          "search_vector_store",
          "Retrieves the most relevant documents from a vector store based on a query.",
          JSON.parse(%({"type":"object","properties":{"query":{"type":"string","description":"The query string to search for relevant documents in the vector store."},"samples":{"type":"integer","description":"The maxinum number of samples / documents to retrieve.","default":5,"minimum":1},"threshold":{"type":"number","description":"Similarity search threshold. If present, any result with a distance less than this may be omitted from the final result."}},"required":["query","samples"]})),
        )
      end

      def call(request : Crig::VectorSearchRequest) : Array(VectorStoreOutput)
        dynamic_top_n(request).map do |score, id, document|
          VectorStoreOutput.new(score, id, document)
        end
      end
    end

    # In-memory vector store with the same builder-oriented workflow as upstream:
    # accumulate documents, choose an index strategy, then build the store.
    struct InMemoryVectorStore(D)
      getter embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))
      getter index_strategy : IndexStrategy
      @lsh_index : LSHIndex?

      def initialize(
        @embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))) = {} of String => Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)),
        @index_strategy : IndexStrategy = IndexStrategy.brute_force,
      )
        @lsh_index = nil
        initialize_lsh_index
      end

      # Create a fluent builder for an in-memory vector store.
      def self.builder : InMemoryVectorStoreBuilder(D)
        InMemoryVectorStoreBuilder(D).new
      end

      def self.from_builder(
        embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))),
        index_strategy : IndexStrategy,
      ) : self
        new(embeddings, index_strategy)
      end

      def self.from_documents(documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        builder.documents(documents).build
      end

      def self.from_documents_with_ids(
        documents : Enumerable(Tuple(String, D, Crig::OneOrMany(Crig::Embeddings::Embedding))),
      ) : self
        builder.documents_with_ids(documents).build
      end

      def self.from_documents_with_id_f(
        documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))),
        & : D -> String
      ) : self
        builder.documents_with_id_f(documents) { |document| yield document }.build
      end

      def add_documents(documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        offset = @embeddings.size
        documents.each_with_index do |(document, embeddings), index|
          id = "doc#{index + offset}"
          @embeddings[id] = {document, embeddings}
          update_lsh_index(id, embeddings)
        end
        self
      end

      def insert_documents(documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        add_documents(documents)
      end

      def add_documents_with_ids(documents : Enumerable(Tuple(String, D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        documents.each do |id, document, embeddings|
          @embeddings[id] = {document, embeddings}
          update_lsh_index(id, embeddings)
        end
        self
      end

      def add_documents_with_id_f(
        documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))),
        & : D -> String
      ) : self
        documents.each do |document, embeddings|
          id = yield document
          @embeddings[id] = {document, embeddings}
          update_lsh_index(id, embeddings)
        end
        self
      end

      def vector_search(
        prompt_embedding : Crig::Embeddings::Embedding,
        n : Int,
      ) : Array(SearchResult(D))
        case @index_strategy.kind
        when IndexStrategy::Kind::BruteForce
          vector_search_brute_force(prompt_embedding, n)
        when IndexStrategy::Kind::LSH
          vector_search_lsh(prompt_embedding, n)
        else
          vector_search_brute_force(prompt_embedding, n)
        end
      end

      private def vector_search_brute_force(
        prompt_embedding : Crig::Embeddings::Embedding,
        n : Int,
      ) : Array(SearchResult(D))
        results = ranked_results(@embeddings.each, prompt_embedding)
        results.sort_by! { |result| -result.score }
        results.first(n)
      end

      private def vector_search_lsh(
        prompt_embedding : Crig::Embeddings::Embedding,
        n : Int,
      ) : Array(SearchResult(D))
        index = @lsh_index
        return vector_search_brute_force(prompt_embedding, n) unless index

        candidate_ids = index.query(prompt_embedding.vec)
        candidates = candidate_ids.compact_map do |candidate_id|
          entry = @embeddings[candidate_id]?
          entry ? {candidate_id, entry} : nil
        end

        results = ranked_results(candidates.each, prompt_embedding)
        results.sort_by! { |result| -result.score }
        results.first(n)
      end

      private def ranked_results(
        entries,
        prompt_embedding : Crig::Embeddings::Embedding,
      ) : Array(SearchResult(D))
        entries.compact_map do |id, (document, embeddings)|
          best_embedding = embeddings.max_by do |embedding|
            embedding.cosine_similarity(prompt_embedding, false)
          end
          next unless best_embedding

          SearchResult(D).new(
            best_embedding.cosine_similarity(prompt_embedding, false),
            id,
            document,
            best_embedding.document,
          )
        end.to_a
      end

      def get_document(id : String, type : T.class) : T? forall T
        entry = @embeddings[id]?
        entry ? T.from_json(entry[0].to_json) : nil
      end

      def index(model : M) : InMemoryVectorIndex(M, D) forall M
        InMemoryVectorIndex(M, D).new(model, self)
      end

      def iter
        @embeddings.each
      end

      def len : Int32
        @embeddings.size.to_i32
      end

      def empty? : Bool
        @embeddings.empty?
      end

      private def initialize_lsh_index : Nil
        return unless @index_strategy.lsh?

        num_tables = @index_strategy.num_tables
        num_hyperplanes = @index_strategy.num_hyperplanes
        return unless num_tables && num_hyperplanes

        first_entry = @embeddings.values.first?
        return unless first_entry
        first_embedding = first_entry[1].first

        index = LSHIndex.new(first_embedding.vec.size, num_tables, num_hyperplanes)
        @embeddings.each do |id, (_, embeddings)|
          update_lsh_index(id, embeddings, index)
        end
        @lsh_index = index
      end

      private def update_lsh_index(
        id : String,
        embeddings : Crig::OneOrMany(Crig::Embeddings::Embedding),
        index : LSHIndex? = @lsh_index,
      ) : Nil
        return unless index

        embeddings.each do |embedding|
          index.insert(id, embedding.vec)
        end
      end
    end
  end
end
