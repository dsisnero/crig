module Crig
  module Concurrency
    struct Result(T)
      getter value : T?
      getter error : Exception?
      getter? has_value : Bool

      def initialize(@value : T? = nil, @error : Exception? = nil, @has_value : Bool = false)
      end

      def self.success(value : T) : self
        new(value: value, has_value: true)
      end

      def self.failure(error : Exception) : self
        new(error: error)
      end

      def success? : Bool
        @error.nil?
      end

      def failure? : Bool
        !success?
      end

      def unwrap : T
        if error = @error
          raise error
        end

        if @has_value
          {% if T == NoReturn %}
            raise "missing concurrency result value"
          {% else %}
            @value.as(T)
          {% end %}
        else
          raise "missing concurrency result value"
        end
      end
    end

    def self.run(&block : -> T) : Channel(Result(T)) forall T
      channel = Channel(Result(T)).new(1)

      spawn do
        begin
          channel.send(Result(T).success(block.call))
        rescue ex : Exception
          channel.send(Result(T).failure(ex))
        ensure
          channel.close
        end
      end

      channel
    end
  end

  alias ConcurrencyResult = Concurrency::Result
end
