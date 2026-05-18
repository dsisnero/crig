module Crig
  module HttpClient
    alias BoxedStream = StreamingResponse
    alias RetryPolicyCarrier = ExponentialBackoff | Constant | Never

    struct MessageEvent
      getter data : String
      getter event : String
      getter id : String
      getter retry : Time::Span?

      def initialize(
        @data : String,
        @event : String = "message",
        @id : String = "",
        @retry : Time::Span? = nil,
      )
      end
    end

    struct Event
      enum Kind
        Open
        Message
      end

      getter kind : Kind
      getter message : MessageEvent?

      def initialize(@kind : Kind, @message : MessageEvent? = nil)
      end

      def self.open : self
        new(Kind::Open)
      end

      def self.message(message : MessageEvent) : self
        new(Kind::Message, message)
      end
    end

    class GenericEventSource(HttpClientType)
      getter last_event_id : String?

      def initialize(@client : HttpClientType, @req : HTTP::Request)
        @retry_policy = DEFAULT_RETRY.as(RetryPolicyCarrier)
        @events = Channel(Result(Event, Error)).new
        @closed = Atomic(Bool).new(false)
        @last_event_id = nil
        @allow_missing_content_type = false
        spawn { run }
      end

      def initialize(
        @client : HttpClientType,
        @req : HTTP::Request,
        @retry_policy : RetryPolicyCarrier,
      )
        @events = Channel(Result(Event, Error)).new
        @closed = Atomic(Bool).new(false)
        @last_event_id = nil
        @allow_missing_content_type = false
        spawn { run }
      end

      def receive? : Result(Event, Error)?
        @events.receive?
      end

      # When set, missing or empty Content-Type headers are accepted.
      # By default, only text/event-stream is accepted.
      def allow_missing_content_type : self
        @allow_missing_content_type = true
        self
      end

      def self.with_retry_policy(
        client : HttpClientType,
        req : HTTP::Request,
        retry_policy : RetryPolicyCarrier,
      ) : GenericEventSource(HttpClientType) forall HttpClientType
        new(client, req, retry_policy)
      end

      def close : Nil
        @closed.set(true)
      end

      private def run : Nil
        retry_state = nil.as({Int32, Time::Span}?)

        until @closed.get
          stream_result = @client.send_streaming(build_request)
          if error = stream_result.error
            should_reconnect, retry_state = handle_stream_error(error, retry_state)
            break unless should_reconnect
            next
          end

          stream = stream_result.unwrap
          unless error = validate_response(stream)
            @events.send(Result(Event, Error).ok(Event.open))
            should_reconnect, retry_state = consume_stream(stream, retry_state)
            break unless should_reconnect
            next
          end

          @events.send(Result(Event, Error).err(error))
          break
        end
      ensure
        @events.close
      end

      private def consume_stream(
        stream : StreamingResponse,
        retry_state : {Int32, Time::Span}?,
      ) : {Bool, {Int32, Time::Span}?}
        buffer = ""

        until @closed.get
          chunk = stream.receive?
          return {false, retry_state} unless chunk

          if error = chunk.error
            return handle_stream_error(error, retry_state)
          end

          if chunk_string = decode_chunk(chunk.value || raise "stream chunk missing bytes")
            buffer += chunk_string
          else
            next
          end
          buffer = emit_buffered_events(buffer)
        end

        {false, retry_state}
      end

      private def handle_stream_error(
        error : Error,
        retry_state : {Int32, Time::Span}?,
      ) : {Bool, {Int32, Time::Span}?}
        @events.send(Result(Event, Error).err(error))
        return {false, retry_state} unless delay = @retry_policy.retry(error, retry_state)

        retry_number = retry_state ? retry_state[0] + 1 : 1
        next_retry_state = {retry_number, delay}
        sleep(delay)
        {true, next_retry_state}
      end

      private def emit_buffered_events(buffer : String) : String
        while separator = buffer.index("\n\n")
          raw_event = buffer[0, separator]
          buffer = buffer[(separator + 2)..] || ""
          emit_message(parse_message(raw_event))
        end

        buffer
      end

      private def emit_message(message : MessageEvent) : Nil
        if !message.id.empty?
          @last_event_id = message.id
        end
        if retry = message.retry
          @retry_policy.set_reconnection_time(retry)
        end
        @events.send(Result(Event, Error).ok(Event.message(message)))
      end

      private def decode_chunk(bytes : Bytes) : String?
        string = String.new(bytes)
        string if string.valid_encoding?
      end

      private def build_request : HTTP::Request
        request = HTTP::Request.new(@req.method, @req.resource, @req.headers, @req.body, @req.version)
        request.headers["Accept"] = "text/event-stream"
        if last_event_id = @last_event_id
          request.headers["Last-Event-ID"] = last_event_id
        end
        request
      end

      private def parse_message(raw_event : String) : MessageEvent
        data_lines = [] of String
        event_name = "message"
        event_id = ""
        retry = nil.as(Time::Span?)

        raw_event.each_line(chomp: true) do |line|
          next if line.empty? || line.starts_with?(":")

          name, value = if index = line.index(':')
                          {line[0, index], line[(index + 1)..].to_s.lstrip}
                        else
                          {line, ""}
                        end

          case name
          when "data"
            data_lines << value
          when "event"
            event_name = value
          when "id"
            event_id = value
          when "retry"
            millis = value.to_i64?
            retry = millis.milliseconds if millis
          end
        end

        MessageEvent.new(data_lines.join("\n"), event_name, event_id, retry)
      end

      private def validate_response(response : StreamingResponse) : Error?
        return Error.invalid_status_code(response.status_code) unless response.status_code == 200

        content_type = response.headers["Content-Type"]?
        return if @allow_missing_content_type && content_type.nil?
        return Error.invalid_content_type("") unless content_type
        return if event_stream_content_type?(content_type)

        Error.invalid_content_type(content_type)
      end

      private def event_stream_content_type?(content_type : String) : Bool
        media_type = content_type.split(';', 2).first.strip.downcase
        media_type == "text/event-stream"
      end
    end
  end
end
