module Crig
  module Model
    struct Model
      include JSON::Serializable

      getter id : String
      getter name : String?
      getter description : String?
      @[JSON::Field(key: "type")]
      getter type : String?
      getter created_at : Int64?
      getter owned_by : String?
      getter context_length : Int32?

      def initialize(
        @id : String,
        @name : String? = nil,
        @description : String? = nil,
        @type : String? = nil,
        @created_at : Int64? = nil,
        @owned_by : String? = nil,
        @context_length : Int32? = nil,
      )
      end

      def self.from_id(id : String) : self
        new(id)
      end

      def display_name : String
        @name || @id
      end

      def to_s(io : IO) : Nil
        io << display_name
      end
    end

    struct ModelList
      include JSON::Serializable
      include Enumerable(Model)

      getter data : Array(Model)

      def initialize(@data : Array(Model))
      end

      def empty? : Bool
        @data.empty?
      end

      # ameba:disable Naming/PredicateName
      def is_empty : Bool
        empty?
      end

      # ameba:enable Naming/PredicateName

      def len : Int32
        @data.size
      end

      def iter : ModelIter
        ModelIter.new(@data)
      end

      def into_iter : ModelIntoIter
        ModelIntoIter.new(@data)
      end

      def each(& : Model ->) : Nil
        @data.each do |model|
          yield model
        end
      end
    end

    struct ModelIter
      include Iterator(Model)

      def initialize(@data : Array(Model), @index : Int32 = 0)
      end

      def next : Model | Iterator::Stop
        model = @data[@index]?
        return stop unless model

        @index += 1
        model
      end
    end

    struct ModelIntoIter
      include Iterator(Model)

      def initialize(data : Array(Model))
        @data = data.dup
        @index = 0
      end

      def next : Model | Iterator::Stop
        model = @data[@index]?
        return stop unless model

        @index += 1
        model
      end
    end

    struct ModelListingError
      include JSON::Serializable

      enum Kind
        ApiError
        RequestError
        ParseError
        AuthError
        RateLimitError
        ServiceUnavailable
        UnknownError
      end

      getter kind : Kind
      getter status_code : Int32?
      getter message : String

      def initialize(@kind : Kind, @message : String, @status_code : Int32? = nil)
      end

      def self.api_error(status_code : Int32, message : String) : self
        new(Kind::ApiError, message, status_code)
      end

      def self.request_error(message : String) : self
        new(Kind::RequestError, message)
      end

      def self.parse_error(message : String) : self
        new(Kind::ParseError, message)
      end

      def self.auth_error(message : String) : self
        new(Kind::AuthError, message)
      end

      def self.rate_limit_error(message : String) : self
        new(Kind::RateLimitError, message)
      end

      def self.service_unavailable(message : String) : self
        new(Kind::ServiceUnavailable, message)
      end

      def self.unknown_error(message : String) : self
        new(Kind::UnknownError, message)
      end

      def to_s(io : IO) : Nil
        case @kind
        in .api_error?
          io << "API error (status " << @status_code << "): " << @message
        in .request_error?
          io << "Request error: " << @message
        in .parse_error?
          io << "Parse error: " << @message
        in .auth_error?
          io << "Authentication error: " << @message
        in .rate_limit_error?
          io << "Rate limit error: " << @message
        in .service_unavailable?
          io << "Service unavailable: " << @message
        in .unknown_error?
          io << "Unknown error: " << @message
        end
      end
    end
  end

  alias ModelInfo = Model::Model
  alias ModelList = Model::ModelList
  alias ModelListingError = Model::ModelListingError
end
