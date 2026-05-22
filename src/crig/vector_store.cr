require "./vector_store/request"
require "./vector_store/builder"
require "./vector_store/in_memory_store"
require "./vector_store/lsh"
require "./vector_store/vectorize"

module Crig
  module VectorStore
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
      enum Kind
        EmbeddingError
        JsonError
        DatastoreError
        FilterError
        MissingIdError
        HttpError
        ExternalApiError
        BuilderError
        Other
      end

      getter kind : Kind
      getter source_error : Exception?
      getter status_code : Int32?
      getter detail : String?

      def initialize(
        @kind : Kind = Kind::Other,
        message : String? = nil,
        @source_error : Exception? = nil,
        @status_code : Int32? = nil,
        @detail : String? = nil,
      )
        super(message || build_message)
      end

      def self.embedding_error(error : Exception) : self
        new(Kind::EmbeddingError, source_error: error)
      end

      def self.json_error(error : Exception) : self
        new(Kind::JsonError, source_error: error)
      end

      def self.datastore_error(error : Exception) : self
        new(Kind::DatastoreError, source_error: error)
      end

      def self.filter_error(error : Exception) : self
        new(Kind::FilterError, source_error: error)
      end

      def self.missing_id(id : String) : self
        new(Kind::MissingIdError, detail: id)
      end

      def self.http_error(error : Exception) : self
        new(Kind::HttpError, source_error: error)
      end

      def self.external_api_error(status_code : Int32, detail : String) : self
        new(Kind::ExternalApiError, status_code: status_code, detail: detail)
      end

      def self.builder_error(detail : String) : self
        new(Kind::BuilderError, detail: detail)
      end

      private def build_message : String
        case @kind
        when Kind::EmbeddingError
          "Embedding error: #{source_message}"
        when Kind::JsonError
          "Json error: #{source_message}"
        when Kind::DatastoreError
          "Datastore error: #{source_message}"
        when Kind::FilterError
          "Filter error: #{source_message}"
        when Kind::MissingIdError
          "Missing Id: #{@detail}"
        when Kind::HttpError
          "HTTP request error: #{source_message}"
        when Kind::ExternalApiError
          "External call to API returned an error. Error code: #{@status_code} Message: #{@detail}"
        when Kind::BuilderError
          "Error while building VectorSearchRequest: #{@detail}"
        else
          @detail || source_message
        end
      end

      private def source_message : String
        @source_error.try(&.message) || @source_error.to_s
      end
    end

    class BuilderError < VectorStoreError
      def initialize(detail : String)
        super(Kind::BuilderError, detail: detail)
      end
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
  alias VectorStoreIndex = VectorStore::VectorStoreIndex
  alias Filter = VectorStore::Filter(JSON::Any)
  alias FilterError = VectorStore::FilterError
end
