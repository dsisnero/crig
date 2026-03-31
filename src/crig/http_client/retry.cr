module Crig
  module HttpClient
    module RetryPolicy
      abstract def retry(error : Error, last_retry : {Int32, Time::Span}?) : Time::Span?
      # ameba:disable Naming/AccessorMethodName
      abstract def set_reconnection_time(duration : Time::Span) : Nil
      # ameba:enable Naming/AccessorMethodName
    end

    struct ExponentialBackoff
      include RetryPolicy

      property start : Time::Span
      getter factor : Float64
      property max_duration : Time::Span?
      getter max_retries : Int32?

      def initialize(
        @start : Time::Span,
        @factor : Float64,
        @max_duration : Time::Span? = nil,
        @max_retries : Int32? = nil,
      )
      end

      def retry(error : Error, last_retry : {Int32, Time::Span}?) : Time::Span?
        _ = error
        return @start unless last_retry

        retry_num, last_duration = last_retry
        if max_retries = @max_retries
          return if retry_num >= max_retries
        end

        duration = last_duration * @factor
        if max_duration = @max_duration
          duration < max_duration ? duration : max_duration
        else
          duration
        end
      end

      # ameba:disable Naming/AccessorMethodName
      def set_reconnection_time(duration : Time::Span) : Nil
        @start = duration
        if max_duration = @max_duration
          @max_duration = max_duration > duration ? max_duration : duration
        end
      end
      # ameba:enable Naming/AccessorMethodName
    end

    struct Constant
      include RetryPolicy

      property delay : Time::Span
      getter max_retries : Int32?

      def initialize(@delay : Time::Span, @max_retries : Int32? = nil)
      end

      def retry(error : Error, last_retry : {Int32, Time::Span}?) : Time::Span?
        _ = error
        return @delay unless last_retry

        retry_num, _ = last_retry
        if max_retries = @max_retries
          return if retry_num >= max_retries
        end
        @delay
      end

      # ameba:disable Naming/AccessorMethodName
      def set_reconnection_time(duration : Time::Span) : Nil
        @delay = duration
      end
      # ameba:enable Naming/AccessorMethodName
    end

    struct Never
      include RetryPolicy

      def retry(error : Error, last_retry : {Int32, Time::Span}?) : Time::Span?
        _ = error
        _ = last_retry
        nil
      end

      # ameba:disable Naming/AccessorMethodName
      def set_reconnection_time(duration : Time::Span) : Nil
        _ = duration
      end
      # ameba:enable Naming/AccessorMethodName
    end

    DEFAULT_RETRY = ExponentialBackoff.new(
      300.milliseconds,
      2.0,
      5.seconds,
      nil
    )
  end
end
