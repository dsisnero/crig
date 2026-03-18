require "./vector_store/request"
require "./vector_store/builder"
require "./vector_store/in_memory_store"
require "./vector_store/lsh"

module Crig
  module VectorStore
    alias TopNResults = Array(Tuple(Float64, String, JSON::Any))

    struct IndexStrategy
      enum Kind
        BruteForce
        LSH
      end

      getter kind : Kind
      getter num_tables : Int32?
      getter num_hyperplanes : Int32?

      def initialize(@kind : Kind = Kind::BruteForce, @num_tables : Int32? = nil, @num_hyperplanes : Int32? = nil)
      end

      def self.brute_force : self
        new
      end

      def self.lsh(num_tables : Int32, num_hyperplanes : Int32) : self
        new(Kind::LSH, num_tables, num_hyperplanes)
      end

      def brute_force? : Bool
        @kind.brute_force?
      end

      def lsh? : Bool
        @kind.lsh?
      end
    end

    class VectorStoreError < Exception
    end

    class BuilderError < VectorStoreError
    end

    struct VectorStoreOutput
      include JSON::Serializable

      getter score : Float64
      getter id : String
      getter document : JSON::Any

      def initialize(@score : Float64, @id : String, @document : JSON::Any)
      end
    end

    def self.prune_document(document : JSON::Any) : JSON::Any?
      object = document.as_h?
      array = document.as_a?

      if object
        pruned = {} of String => JSON::Any
        object.each do |key, value|
          candidate = prune_document(value)
          pruned[key] = candidate if candidate
        end
        JSON.parse(pruned.to_json)
      elsif array
        return if array.size > 400

        pruned = array.compact_map do |value|
          prune_document(value)
        end
        JSON.parse(pruned.to_json)
      else
        document
      end
    end
  end

  alias BuilderError = VectorStore::BuilderError
  alias IndexStrategy = VectorStore::IndexStrategy
  alias InMemoryVectorIndex = VectorStore::InMemoryVectorIndex
  alias InMemoryVectorStore = VectorStore::InMemoryVectorStore
  alias InMemoryVectorStoreBuilder = VectorStore::InMemoryVectorStoreBuilder
  alias LSH = VectorStore::LSH
  alias LSHIndex = VectorStore::LSHIndex
  alias TopNResults = VectorStore::TopNResults
  alias VectorSearchRequest = VectorStore::VectorSearchRequest(VectorStore::Filter(JSON::Any))
  alias VectorSearchRequestBuilder = VectorStore::VectorSearchRequestBuilder(VectorStore::Filter(JSON::Any))
  alias VectorStoreOutput = VectorStore::VectorStoreOutput
  alias VectorStoreError = VectorStore::VectorStoreError
  alias Filter = VectorStore::Filter(JSON::Any)
  alias FilterError = VectorStore::FilterError
end
