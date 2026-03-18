module Crig
  module VectorStore
    struct InMemoryVectorStoreBuilder(D)
      getter embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))
      getter index_strategy_value : IndexStrategy

      def initialize(
        @embeddings : Hash(String, Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding))) = {} of String => Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)),
        @index_strategy_value : IndexStrategy = IndexStrategy.brute_force,
      )
      end

      def index_strategy(index_strategy : IndexStrategy) : self
        self.class.new(@embeddings.dup, index_strategy)
      end

      def documents(documents : Enumerable(Tuple(D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        updated = @embeddings.dup
        offset = updated.size
        documents.each_with_index do |(document, embeddings), index|
          updated["doc#{index + offset}"] = {document, embeddings}
        end
        self.class.new(updated, @index_strategy_value)
      end

      def documents_with_ids(documents : Enumerable(Tuple(String, D, Crig::OneOrMany(Crig::Embeddings::Embedding)))) : self
        updated = @embeddings.dup
        documents.each do |id, document, embeddings|
          updated[id] = {document, embeddings}
        end
        self.class.new(updated, @index_strategy_value)
      end

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

      def build : InMemoryVectorStore(D)
        InMemoryVectorStore(D).from_builder(@embeddings.dup, @index_strategy_value)
      end
    end
  end
end
