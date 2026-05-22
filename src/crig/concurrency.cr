module Crig
  module Concurrency
    class TimeoutError < Exception
    end

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

    def self.run(timeout : Time::Span? = nil, &block : -> T) : Channel(Result(T)) forall T
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

    # Run an ordered fan-out over independent inputs and join the results.
    # This preserves input ordering while allowing each branch to execute in
    # its own Crystal fiber.
    def self.map_ordered(items : Enumerable(A), timeout : Time::Span? = nil, &block : A -> T) : Array(T) forall A, T
      inputs = items.to_a
      return [] of T if inputs.empty?

      channels = inputs.map do |item|
        run(timeout) { block.call(item) }
      end

      channels.map do |channel|
        if t = timeout
          select
          when result = channel.receive
            result.unwrap
          when timeout(t)
            raise TimeoutError.new("concurrent operation timed out after #{t}")
          end
        else
          channel.receive.unwrap
        end
      end
    end

    def self.flat_map_ordered(items : Enumerable(A), timeout : Time::Span? = nil, &block : A -> Enumerable(T)) : Array(T) forall A, T
      map_ordered(items, timeout) { |item| block.call(item).to_a }.flat_map(&.itself)
    end
  end

  alias ConcurrencyResult = Concurrency::Result
end
