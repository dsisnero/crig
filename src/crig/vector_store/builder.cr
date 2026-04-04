module Crig
  module VectorStore
    # Builder for in-memory vector stores. This mirrors the Rust `builder()`
    # workflow so examples can accumulate embeddings before constructing the store.
    struct InMemoryVectorStoreBuilder(D)
      getter embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))
      getter index_strategy_value : IndexStrategy

      def initialize(
        @embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))) = {} of String => Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)),
        @index_strategy_value : IndexStrategy = IndexStrategy.brute_force,
      )
      end

      # Select the indexing strategy used by the finished store.
      def index_strategy(index_strategy : IndexStrategy) : self
        self.class.new(@embeddings.dup, index_strategy)
      end

      # Add documents and assign generated ids in insertion order.
      def documents(documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        updated = @embeddings.dup
        offset = updated.size
        documents.each_with_index do |(document, embeddings), index|
          updated["doc#{index + offset}"] = {document, embeddings}
        end
        self.class.new(updated, @index_strategy_value)
      end

      # Add documents with explicit ids.
      def documents_with_ids(documents : Enumerable(Tuple(String, D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        updated = @embeddings.dup
        documents.each do |id, document, embeddings|
          updated[id] = {document, embeddings}
        end
        self.class.new(updated, @index_strategy_value)
      end

      # Add documents and derive ids from the provided callback.
      def documents_with_id_f(
        documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))),
        & : D -> String
      ) : self
        updated = @embeddings.dup
        documents.each do |document, embeddings|
          updated[yield document] = {document, embeddings}
        end
        self.class.new(updated, @index_strategy_value)
      end

      # Build the concrete in-memory store.
      def build : InMemoryVectorStore(D)
        InMemoryVectorStore(D).from_builder(@embeddings.dup, @index_strategy_value)
      end
    end
  end
end
