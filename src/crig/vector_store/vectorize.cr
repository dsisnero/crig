require "http/client"
require "json"
require "random/secure"

module Crig
  module VectorStore
    module Vectorize
      CLOUDFLARE_API_BASE_URL = "https://api.cloudflare.com/client/v4"

      # Error types -------------------------------------------------------

      class VectorizeError < Exception
        enum Kind
          HttpError
          ApiError
          SerializationError
          UnsupportedFilterOperation
        end

        getter kind : Kind
        getter api_code : UInt32?
        getter api_message : String?

        def initialize(
          @kind : Kind,
          message : String? = nil,
          @api_code : UInt32? = nil,
          @api_message : String? = nil,
        )
          super(message)
        end

        def self.http_error(error : Exception) : self
          new(Kind::HttpError, "HTTP request failed: #{error.message}")
        end

        def self.api_error(code : UInt32, msg : String) : self
          new(Kind::ApiError, "Vectorize API error (code: #{code}): #{msg}", api_code: code, api_message: msg)
        end

        def self.serialization_error(error : Exception) : self
          new(Kind::SerializationError, "JSON serialization error: #{error.message}")
        end

        def self.unsupported_filter(operation : String) : self
          new(Kind::UnsupportedFilterOperation, "Unsupported filter operation: #{operation}")
        end

        def to_vector_store_error : Crig::VectorStore::VectorStoreError
          Crig::VectorStore::VectorStoreError.datastore_error(self)
        end
      end

      # Request / Response types ------------------------------------------

      enum ReturnMetadata
        None
        Indexed
        All
      end

      struct QueryRequest
        include JSON::Serializable

        property vector : Array(Float64)
        @[JSON::Field(key: "topK")]
        property top_k : UInt64
        @[JSON::Field(key: "returnValues")]
        property return_values : Bool?
        @[JSON::Field(key: "returnMetadata")]
        property return_metadata : ReturnMetadata?
        property filter : JSON::Any?

        def initialize(
          @vector : Array(Float64),
          @top_k : UInt64,
          @return_values : Bool? = nil,
          @return_metadata : ReturnMetadata? = nil,
          @filter : JSON::Any? = nil,
        )
        end
      end

      struct QueryResult
        include JSON::Serializable

        getter count : UInt64
        getter matches : Array(VectorMatch)
        # Crystal's JSON::Serializable ignores unknown fields

        def initialize(@count : UInt64, @matches : Array(VectorMatch))
        end
      end

      struct VectorMatch
        include JSON::Serializable

        getter id : String
        getter score : Float64
        getter values : Array(Float64)?
        getter metadata : JSON::Any?
        getter namespace : String?

        def initialize(
          @id : String,
          @score : Float64,
          @values : Array(Float64)? = nil,
          @metadata : JSON::Any? = nil,
          @namespace : String? = nil,
        )
        end
      end

      struct VectorInput
        include JSON::Serializable

        getter id : String
        getter values : Array(Float64)
        getter metadata : JSON::Any?
        getter namespace : String?

        def initialize(
          @id : String,
          @values : Array(Float64),
          @metadata : JSON::Any? = nil,
          @namespace : String? = nil,
        )
        end
      end

      struct UpsertRequest
        include JSON::Serializable

        getter vectors : Array(VectorInput)

        def initialize(@vectors : Array(VectorInput))
        end
      end

      struct UpsertResult
        include JSON::Serializable

        @[JSON::Field(key: "mutationId")]
        getter mutation_id : String

        def initialize(@mutation_id : String)
        end
      end

      struct DeleteByIdsRequest
        include JSON::Serializable

        getter ids : Array(String)

        def initialize(@ids : Array(String))
        end
      end

      struct DeleteResult
        include JSON::Serializable

        @[JSON::Field(key: "mutationId")]
        getter mutation_id : String

        def initialize(@mutation_id : String)
        end
      end

      struct ListVectorsResult
        include JSON::Serializable

        @[JSON::Field(key: "count")]
        getter count : UInt64
        @[JSON::Field(key: "isTruncated")]
        getter is_truncated : Bool
        @[JSON::Field(key: "totalCount")]
        getter total_count : UInt64
        @[JSON::Field(key: "vectors")]
        getter vectors : Array(VectorIdEntry)
        @[JSON::Field(key: "nextCursor")]
        getter next_cursor : String?

        def initialize(
          @count : UInt64,
          @is_truncated : Bool,
          @total_count : UInt64,
          @vectors : Array(VectorIdEntry),
          @next_cursor : String? = nil,
        )
        end
      end

      struct VectorIdEntry
        include JSON::Serializable

        getter id : String

        def initialize(@id : String)
        end
      end

      # Cloudflare API envelope
      private struct ApiResponse(T)
        include JSON::Serializable

        getter success : Bool
        getter result : T?
        getter errors : Array(ApiErrorDetail)
        getter messages : Array(ApiMessage)

        def initialize(
          @success : Bool,
          @result : T? = nil,
          @errors : Array(ApiErrorDetail) = [] of ApiErrorDetail,
          @messages : Array(ApiMessage) = [] of ApiMessage,
        )
        end
      end

      private struct ApiErrorDetail
        include JSON::Serializable

        getter code : UInt32
        getter message : String

        def initialize(@code : UInt32, @message : String)
        end
      end

      private struct ApiMessage
        include JSON::Serializable

        getter code : UInt32?
        getter message : String

        def initialize(@code : UInt32? = nil, @message : String = "")
        end
      end

      # Filter ------------------------------------------------------------

      struct VectorizeFilter
        include Crig::VectorStore::SearchFilter(JSON::Any)

        getter raw : JSON::Any

        def initialize(@raw : JSON::Any = JSON.parse("{}"))
        end

        def into_inner : JSON::Any
          @raw
        end

        def as_value : JSON::Any
          @raw
        end

        def is_empty : Bool
          !!@raw.as_h?.try(&.empty?)
        end

        def eq(key : String, value : JSON::Any) : self
          add_op("$eq", key, value)
        end

        def ne(key : String, value : JSON::Any) : self
          add_op("$ne", key, value)
        end

        def gt(key : String, value : JSON::Any) : self
          add_op("$gt", key, value)
        end

        def gte(key : String, value : JSON::Any) : self
          add_op("$gte", key, value)
        end

        def lt(key : String, value : JSON::Any) : self
          add_op("$lt", key, value)
        end

        def lte(key : String, value : JSON::Any) : self
          add_op("$lte", key, value)
        end

        def in_values(key : String, values : Array(JSON::Any)) : self
          new_raw = @raw.as_h.dup
          new_raw[key] = JSON.parse("{\"$in\": #{values.to_json}}")
          self.class.new(JSON.parse(new_raw.to_json))
        end

        def nin(key : String, values : Array(JSON::Any)) : self
          new_raw = @raw.as_h.dup
          new_raw[key] = JSON.parse("{\"$nin\": #{values.to_json}}")
          self.class.new(JSON.parse(new_raw.to_json))
        end

        def and(rhs : self) : self
          merged = @raw.as_h.merge(rhs.raw.as_h)
          self.class.new(JSON.parse(merged.to_json))
        end

        def or(rhs : self) : self
          # Vectorize does NOT support OR filters
          self.class.new(JSON.parse("{}"))
        end

        def validate : Nil
          raise VectorizeError.unsupported_filter("OR operations are not supported") if @raw.as_h?.nil?
        end

        private def add_op(op : String, key : String, value : JSON::Any) : self
          new_raw = @raw.as_h.dup
          new_raw[key] = JSON.parse("{\"#{op}\": #{value.to_json}}")
          self.class.new(JSON.parse(new_raw.to_json))
        end
      end

      # HTTP Client -------------------------------------------------------

      class VectorizeClient
        getter account_id : String
        getter index_name : String

        @http_client : HTTP::Client
        @api_token : String

        def initialize(
          @account_id : String,
          @index_name : String,
          @api_token : String,
        )
          @http_client = HTTP::Client.new(URI.parse(CLOUDFLARE_API_BASE_URL))
        end

        private def index_url : String
          "/accounts/#{@account_id}/vectorize/v2/indexes/#{@index_name}"
        end

        private def auth_headers : Hash(String, String)
          {
            "Authorization" => "Bearer #{@api_token}",
            "Content-Type"  => "application/json",
          }
        end

        private def unwrap_envelope(response : HTTP::Client::Response, klass : T.class) : T forall T
          body = response.body
          raise VectorizeError.http_error(Exception.new("HTTP #{response.status_code}: #{body}")) unless response.success?

          begin
            envelope = ApiResponse(T).from_json(body)
          rescue ex : JSON::ParseException
            raise VectorizeError.serialization_error(ex)
          end

          unless envelope.success
            first_error = envelope.errors.first?
            raise VectorizeError.api_error(
              first_error.try(&.code) || 0_u32,
              first_error.try(&.message) || "unknown API error",
            )
          end

          envelope.result || raise VectorizeError.api_error(0_u32, "empty result")
        end

        def query(request : QueryRequest) : QueryResult
          response = @http_client.post(
            "#{index_url}/query",
            headers: auth_headers,
            body: request.to_json,
          )
          unwrap_envelope(response, QueryResult)
        end

        def upsert(request : UpsertRequest) : UpsertResult
          response = @http_client.post(
            "#{index_url}/upsert",
            headers: auth_headers,
            body: request.to_json,
          )
          unwrap_envelope(response, UpsertResult)
        end

        def delete_by_ids(ids : Array(String)) : DeleteResult
          response = @http_client.post(
            "#{index_url}/delete_by_ids",
            headers: auth_headers,
            body: DeleteByIdsRequest.new(ids).to_json,
          )
          unwrap_envelope(response, DeleteResult)
        end

        def list_vectors(limit : UInt32? = nil, cursor : String? = nil) : ListVectorsResult
          params = [] of String
          params << "count=#{limit}" if limit
          params << "cursor=#{cursor}" if cursor
          query_string = params.empty? ? "" : "?#{params.join("&")}"

          response = @http_client.get(
            "#{index_url}/list#{query_string}",
            headers: auth_headers,
          )
          unwrap_envelope(response, ListVectorsResult)
        end
      end

      # Main Store --------------------------------------------------------

      # A vector store backed by Cloudflare Vectorize.
      #
      # Implements vector similarity search via Cloudflare's Vectorize REST API.
      # Embeds queries locally using the provided EmbeddingModel, then sends
      # the resulting vectors to the Vectorize index for ANN search.
      struct VectorizeVectorStore(M)
        @model : M
        @client : VectorizeClient

        def initialize(
          @model : M,
          account_id : String,
          index_name : String,
          api_token : String,
        )
          @client = VectorizeClient.new(account_id, index_name, api_token)
        end

        # Search the Vectorize index and return the top N matches as
        # (score, id, JSON::Any) tuples.
        def top_n(request : Crig::VectorSearchRequest, filter_json : JSON::Any? = nil) : Array({Float64, String, JSON::Any})
          prompt_embedding = @model.embed_text(request.query)

          api_request = QueryRequest.new(
            vector: prompt_embedding.vec,
            top_k: request.samples.to_u64,
            return_values: false,
            return_metadata: ReturnMetadata::All,
            filter: filter_json,
          )

          result = @client.query(api_request)
          result.matches.compact_map do |match|
            metadata = match.metadata || JSON.parse("{}")
            {match.score, match.id, metadata}
          end
        rescue ex : VectorizeError
          raise ex.to_vector_store_error
        end

        # Search the Vectorize index and return the top N match IDs as
        # (score, id) tuples.
        def top_n_ids(request : Crig::VectorSearchRequest, filter_json : JSON::Any? = nil) : Array({Float64, String})
          prompt_embedding = @model.embed_text(request.query)

          api_request = QueryRequest.new(
            vector: prompt_embedding.vec,
            top_k: request.samples.to_u64,
            return_values: false,
            filter: filter_json,
          )

          result = @client.query(api_request)
          result.matches.map do |match|
            {match.score, match.id}
          end
        rescue ex : VectorizeError
          raise ex.to_vector_store_error
        end

        # Upsert documents into the Vectorize index.  Each document's
        # embeddings are sent as individual vectors with auto-generated UUIDs.
        def insert_documents(documents : Array({JSON::Any, Crig::OneOrMany(Crig::Embeddings::Embedding)})) : Nil
          vectors = documents.flat_map do |document, embeddings|
            embeddings.map do |embedding|
              VectorInput.new(
                id: generate_uuid_v4,
                values: embedding.vec,
                metadata: document,
              )
            end
          end

          @client.upsert(UpsertRequest.new(vectors))
        rescue ex : VectorizeError
          raise ex.to_vector_store_error
        end
      end

      # UUID v4 generator using Crystal's Random::Secure.
      def self.generate_uuid_v4 : String
        bytes = Random::Secure.random_bytes(16)
        bytes[6] = (bytes[6] & 0x0f) | 0x40  # version 4
        bytes[8] = (bytes[8] & 0x3f) | 0x80  # variant 1
        String.build(36) do |io|
          bytes.each_with_index do |byte, i|
            io << '-' if {4, 6, 8, 10}.includes?(i)
            io << byte.to_s(16, upcase: true).rjust(2, '0')
          end
        end
      end
    end
  end
end
