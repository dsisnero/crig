module Crig
  module VectorStore
    module SearchFilter(V)
    end

    class FilterError < Exception
      include JSON::Serializable

      getter kind : String
      getter expected : String?
      getter got : String?
      getter field : String?
      getter condition : String?
      getter detail : String?

      def initialize(
        @kind : String,
        @expected : String? = nil,
        @got : String? = nil,
        @field : String? = nil,
        @condition : String? = nil,
        @detail : String? = nil,
      )
        super(build_message)
      end

      def self.expected(expected : String, got : String) : self
        new("expected", expected: expected, got: got)
      end

      def self.type_error(detail : String) : self
        new("type_error", detail: detail)
      end

      def self.missing_field(field : String) : self
        new("missing_field", field: field)
      end

      def self.must(field : String, condition : String) : self
        new("must", field: field, condition: condition)
      end

      def self.serialization(detail : String) : self
        new("serialization", detail: detail)
      end

      private def build_message : String
        case @kind
        when "expected"
          "Expected: #{@expected}, got: #{@got}"
        when "type_error"
          "Cannot compile '#{@detail}' to the backend's filter type"
        when "missing_field"
          "Missing field '#{@field}'"
        when "must"
          "'#{@field}' must #{@condition}"
        when "serialization"
          "Filter serialization failed: #{@detail}"
        else
          @detail || @kind
        end
      end
    end

    class Filter(V)
      include SearchFilter(V)

      enum Kind
        Eq
        Gt
        Lt
        And
        Or
      end

      getter kind : Kind
      getter key : String?
      getter value : V?
      getter lhs : Filter(V)?
      getter rhs : Filter(V)?

      def initialize(
        @kind : Kind,
        @key : String? = nil,
        @value : V? = nil,
        @lhs : Filter(V)? = nil,
        @rhs : Filter(V)? = nil,
      )
      end

      def self.eq(key : String | Symbol, value : V) : self
        new(Kind::Eq, key: key.to_s, value: value)
      end

      def self.gt(key : String | Symbol, value : V) : self
        new(Kind::Gt, key: key.to_s, value: value)
      end

      def self.lt(key : String | Symbol, value : V) : self
        new(Kind::Lt, key: key.to_s, value: value)
      end

      def and_(rhs : Filter(V)) : self
        self.class.new(Kind::And, lhs: self, rhs: rhs)
      end

      def or_(rhs : Filter(V)) : self
        self.class.new(Kind::Or, lhs: self, rhs: rhs)
      end

      def satisfies(value : JSON::Any) : Bool
        case @kind
        when Kind::Eq
          wrap_key_value(scalar_key, json_value) == value
        when Kind::Gt
          compare_pair(wrap_key_value(scalar_key, json_value), value) == 1
        when Kind::Lt
          compare_pair(wrap_key_value(scalar_key, json_value), value) == -1
        when Kind::And
          left_filter.satisfies(value) && right_filter.satisfies(value)
        when Kind::Or
          left_filter.satisfies(value) || right_filter.satisfies(value)
        else
          false
        end
      end

      private def wrap_key_value(key : String, inner_value : JSON::Any) : JSON::Any
        JSON.parse({key => inner_value.raw}.to_json)
      end

      private def json_value : JSON::Any
        @value.as?(JSON::Any) || raise FilterError.type_error("non-JSON filter value")
      end

      private def scalar_key : String
        @key || raise FilterError.missing_field("key")
      end

      private def left_filter : Filter(V)
        @lhs || raise FilterError.missing_field("lhs")
      end

      private def right_filter : Filter(V)
        @rhs || raise FilterError.missing_field("rhs")
      end

      private def compare_pair(left : JSON::Any, right : JSON::Any) : Int32?
        lraw = left.raw
        rraw = right.raw

        case {lraw, rraw}
        when {Int64, Int64}
          lraw <=> rraw
        when {Float64, Float64}
          lraw <=> rraw
        when {Int64, Float64}
          lraw.to_f64 <=> rraw
        when {Float64, Int64}
          lraw <=> rraw.to_f64
        when {String, String}
          lraw <=> rraw
        when {Bool, Bool}
          (lraw ? 1 : 0) <=> (rraw ? 1 : 0)
        when {Nil, Nil}
          0
        end
      end
    end

    # Request payload for vector search backends.
    # Use `VectorSearchRequest.builder` for the fluent builder-style API.
    struct VectorSearchRequest(F)
      getter query : String
      getter samples : UInt64
      getter threshold : Float64?
      getter additional_params : JSON::Any?
      getter filter : F?

      def initialize(
        @query : String,
        @samples : UInt64,
        @threshold : Float64? = nil,
        @additional_params : JSON::Any? = nil,
        @filter : F? = nil,
      )
      end

      # Create a fluent vector-search request builder.
      def self.builder : VectorSearchRequestBuilder(F)
        VectorSearchRequestBuilder(F).new
      end

      def map_filter(& : F -> T) : VectorSearchRequest(T) forall T
        mapped_filter = @filter.try { |value| yield value }
        VectorSearchRequest(T).new(
          @query,
          @samples,
          threshold: @threshold,
          additional_params: @additional_params,
          filter: mapped_filter,
        )
      end

      def try_map_filter(& : F -> T) : VectorSearchRequest(T) forall T
        mapped_filter = @filter.try { |value| yield value }
        VectorSearchRequest(T).new(
          @query,
          @samples,
          threshold: @threshold,
          additional_params: @additional_params,
          filter: mapped_filter,
        )
      end
    end

    # Builder for vector search requests. This is the standard way retrieval and
    # tool-server code construct top-N search operations.
    struct VectorSearchRequestBuilder(F)
      getter query_value : String?
      getter samples_value : UInt64?
      getter threshold_value : Float64?
      getter additional_params_value : JSON::Any?
      getter filter_value : F?

      def initialize(
        @query_value : String? = nil,
        @samples_value : UInt64? = nil,
        @threshold_value : Float64? = nil,
        @additional_params_value : JSON::Any? = nil,
        @filter_value : F? = nil,
      )
      end

      def query(query : String) : self
        self.class.new(query, @samples_value, @threshold_value, @additional_params_value, @filter_value)
      end

      def samples(samples : UInt64 | Int32 | Int64) : self
        self.class.new(@query_value, samples.to_u64, @threshold_value, @additional_params_value, @filter_value)
      end

      def threshold(threshold : Float32 | Float64) : self
        self.class.new(@query_value, @samples_value, threshold.to_f64, @additional_params_value, @filter_value)
      end

      def additional_params(params : JSON::Any) : self
        self.class.new(@query_value, @samples_value, @threshold_value, params, @filter_value)
      end

      def filter(filter : F) : self
        self.class.new(@query_value, @samples_value, @threshold_value, @additional_params_value, filter)
      end

      def build : VectorSearchRequest(F)
        query = @query_value
        raise BuilderError.new("`query` is a required variable for building a vector search request") unless query

        samples = @samples_value
        raise BuilderError.new("`samples` is a required variable for building a vector search request") unless samples

        additional_params = @additional_params_value
        if additional_params && !additional_params.raw.is_a?(Hash(String, JSON::Any))
          raise BuilderError.new("Expected JSON object for additional params, got something else")
        end

        VectorSearchRequest(F).new(
          query,
          samples,
          threshold: @threshold_value,
          additional_params: additional_params,
          filter: @filter_value,
        )
      end
    end
  end
end
