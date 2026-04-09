require "http/web_socket"
require "uri"

module Crig
  module Providers
    module OpenAI
      enum ResponsesWebSocketDoneEventKind
        ResponseDone
      end

      enum ResponsesWebSocketErrorEventKind
        Error
      end

      struct ResponsesWebSocketErrorPayload
        include JSON::Serializable
        getter code : String?
        getter message : String?
        include JSON::Serializable::Unmapped

        def initialize(@code : String? = nil, @message : String? = nil)
        end

        def to_s(io : IO) : Nil
          if code = @code
            if message = @message
              io << code << ": " << message
            else
              io << code
            end
          else
            io << (@message || "OpenAI websocket error")
          end
        end
      end

      struct ResponsesWebSocketErrorEvent
        getter kind : ResponsesWebSocketErrorEventKind
        getter error : ResponsesWebSocketErrorPayload

        def initialize(@kind : ResponsesWebSocketErrorEventKind, @error : ResponsesWebSocketErrorPayload)
        end

        def self.from_json_value(value : JSON::Any) : self
          new(ResponsesWebSocketErrorEventKind::Error, ResponsesWebSocketErrorPayload.from_json(value["error"].to_json))
        end

        def to_s(io : IO) : Nil
          @error.to_s(io)
        end
      end

      struct ResponsesWebSocketDoneEvent
        getter kind : ResponsesWebSocketDoneEventKind
        getter response : JSON::Any

        def initialize(@kind : ResponsesWebSocketDoneEventKind, @response : JSON::Any)
        end

        def self.from_json_value(value : JSON::Any) : self
          new(ResponsesWebSocketDoneEventKind::ResponseDone, value["response"])
        end

        def response_id : String?
          @response["id"]?.try(&.as_s?)
        end

        def as_completion_response : CompletionResponsePayload?
          CompletionResponsePayload.from_json(@response.to_json)
        rescue
          nil
        end
      end

      enum ResponsesWebSocketEventKind
        Response
        Item
        Error
        Done
      end

      struct ResponsesWebSocketEvent
        getter kind : ResponsesWebSocketEventKind
        getter response : ResponseChunk?
        getter item : ItemChunk?
        getter error : ResponsesWebSocketErrorEvent?
        getter done : ResponsesWebSocketDoneEvent?

        def initialize(
          @kind : ResponsesWebSocketEventKind,
          @response : ResponseChunk? = nil,
          @item : ItemChunk? = nil,
          @error : ResponsesWebSocketErrorEvent? = nil,
          @done : ResponsesWebSocketDoneEvent? = nil,
        )
        end

        def self.response(chunk : ResponseChunk) : self
          new(ResponsesWebSocketEventKind::Response, response: chunk)
        end

        def self.item(chunk : ItemChunk) : self
          new(ResponsesWebSocketEventKind::Item, item: chunk)
        end

        def self.error(event : ResponsesWebSocketErrorEvent) : self
          new(ResponsesWebSocketEventKind::Error, error: event)
        end

        def self.done(event : ResponsesWebSocketDoneEvent) : self
          new(ResponsesWebSocketEventKind::Done, done: event)
        end

        def response_id : String?
          @response.try(&.response.id) || @done.try(&.response_id)
        end

        def terminal? : Bool
          case @kind
          when .done?, .error?
            true
          when .response?
            response = @response
            return false unless response
            response.kind.response_completed? || response.kind.response_failed? || response.kind.response_incomplete?
          else
            false
          end
        end

        # ameba:disable Naming/PredicateName
        def is_terminal : Bool
          terminal?
        end
        # ameba:enable Naming/PredicateName
      end

      struct ResponsesWebSocketCreateOptions
        include JSON::Serializable
        getter generate : Bool?

        def initialize(@generate : Bool? = nil)
        end

        def self.warmup : self
          new(false)
        end
      end

      struct ResponsesWebSocketSessionBuilder
        getter model : ResponsesCompletionModel
        getter connect_timeout : Time::Span?
        getter event_timeout : Time::Span?

        def initialize(@model : ResponsesCompletionModel, @connect_timeout : Time::Span? = 30.seconds, @event_timeout : Time::Span? = nil)
        end

        def connect_timeout(timeout : Time::Span) : self
          self.class.new(@model, timeout, @event_timeout)
        end

        def without_connect_timeout : self
          self.class.new(@model, nil, @event_timeout)
        end

        def event_timeout(timeout : Time::Span) : self
          self.class.new(@model, @connect_timeout, timeout)
        end

        def without_event_timeout : self
          self.class.new(@model, @connect_timeout, nil)
        end

        def connect : ResponsesWebSocketSession
          ResponsesWebSocketSession.connect(@model, @event_timeout)
        end
      end

      class ResponsesWebSocketSession
        @previous_response_id : String?
        @pending_done_response_id : String?
        @in_flight = false
        @closed = false
        @failed = false

        def self.connect(model : ResponsesCompletionModel, event_timeout : Time::Span?) : self
          url = websocket_url(model.client.base_url)
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{model.client.api_key.token}",
          }
          new(model, HTTP::WebSocket.new(URI.parse(url), headers), event_timeout)
        end

        def initialize(@model : ResponsesCompletionModel, @socket : HTTP::WebSocket, @event_timeout : Time::Span? = nil)
          @events = Channel(String | Symbol).new
          @socket.on_message { |message| @events.send(message) }
          @socket.on_close { |_code, _reason| @events.send(:closed) rescue nil }
          spawn { @socket.run }
        end

        def previous_response_id : String?
          @previous_response_id
        end

        def clear_previous_response_id : Nil
          @previous_response_id = nil
        end

        def send(completion_request : Crig::Completion::Request::CompletionRequest) : Nil
          send_with_options(completion_request, ResponsesWebSocketCreateOptions.new)
        end

        def send_with_options(completion_request : Crig::Completion::Request::CompletionRequest, options : ResponsesWebSocketCreateOptions) : Nil
          ensure_open
          raise Crig::Completion::CompletionError.new("An OpenAI websocket response is already in flight on this session") if @in_flight
          request = @model.create_completion_request(completion_request)
          request = CompletionRequest.from_json(request.to_json_value.to_json)
          request.additional_parameters.previous_response_id ||= @previous_response_id
          request.stream = nil
          request.additional_parameters.background = nil
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "type", "response.create"
              request.to_json_value.as_h.each do |entry|
                json.field entry[0] { entry[1].to_json(json) }
              end
              if generate = options.generate
                json.field "generate", generate
              end
            end
          end
          @socket.send(payload.to_json)
          @in_flight = true
        end

        def next_event : ResponsesWebSocketEvent
          ensure_open
          raise Crig::Completion::CompletionError.new("No OpenAI websocket response is currently in flight on this session") unless @in_flight
          loop do
            payload = receive_payload
            event = parse_server_event(payload)
            next unless event
            if event.kind.done?
              done = event.done
              if done && @pending_done_response_id == done.response_id
                @pending_done_response_id = nil
                next
              end
            end
            update_state_for_event(event)
            return event
          end
        end

        def warmup(completion_request : Crig::Completion::Request::CompletionRequest) : String
          send_with_options(completion_request, ResponsesWebSocketCreateOptions.warmup)
          wait_for_completed_response.id
        end

        def completion(completion_request : Crig::Completion::Request::CompletionRequest)
          send(completion_request)
          wait_for_completed_response.to_completion_response
        end

        def wait_for_completed_response : CompletionResponsePayload
          loop do
            event = next_event
            case event.kind
            when .response?
              response = event.response
              return terminal_response_result(response) if response
            when .done?
              done = event.done
              response = done.try(&.as_completion_response)
              return response if response
              raise Crig::Completion::CompletionError.new("OpenAI websocket turn ended before a terminal response body was available")
            when .error?
              error = event.error
              raise Crig::Completion::CompletionError.new(error.to_s) if error
              raise Crig::Completion::CompletionError.new("OpenAI websocket turn ended with an empty websocket error payload")
            else
            end
          end
        end

        def close : Nil
          return if @closed
          @closed = true
          @socket.close
        end

        private def receive_payload : String
          if timeout = @event_timeout
            select
            when payload = @events.receive
              payload_to_string(payload)
            when timeout(timeout)
              @failed = true
              raise Crig::Completion::CompletionError.new("Timed out waiting for the next OpenAI websocket event after #{timeout}")
            end
          else
            payload_to_string(@events.receive)
          end
        end

        private def payload_to_string(payload : String | Symbol) : String
          if payload.is_a?(String)
            payload
          else
            @closed = true
            raise Crig::Completion::CompletionError.new("The OpenAI websocket connection closed before the turn finished")
          end
        end

        private def ensure_open : Nil
          raise Crig::Completion::CompletionError.new("The OpenAI websocket session is closed") if @closed || @failed
        end

        private def update_state_for_event(event : ResponsesWebSocketEvent) : Nil
          case event.kind
          when .response?
            response = event.response
            return unless response
            if response.kind.response_completed?
              @previous_response_id = response.response.id
              @pending_done_response_id = response.response.id
              @in_flight = false
            elsif response.kind.response_failed? || response.kind.response_incomplete?
              @previous_response_id = nil
              @pending_done_response_id = response.response.id
              @in_flight = false
            end
          when .done?
            done = event.done
            return unless done
            status = done.response["status"]?.try(&.as_s?)
            @previous_response_id = done.response_id if status == "completed"
            @previous_response_id = nil if {"failed", "incomplete", "cancelled"}.includes?(status)
            @pending_done_response_id = nil
            @in_flight = false
          when .error?
            @previous_response_id = nil
            @pending_done_response_id = nil
            @in_flight = false
          else
          end
        end
      end

      def self.terminal_response_result(response : CompletionResponsePayload) : CompletionResponsePayload
        case response.status
        when .completed?
          response
        when .failed?
          error = response.error
          message = error ? (error.code.empty? ? error.message : "#{error.code}: #{error.message}") : "OpenAI websocket returned a failed response"
          raise Crig::Completion::CompletionError.new(message)
        when .incomplete?
          reason = response.incomplete_details.try(&.reason) || "unknown reason"
          raise Crig::Completion::CompletionError.new("OpenAI websocket response was incomplete: #{reason}")
        else
          raise Crig::Completion::CompletionError.new("OpenAI websocket response ended with status #{response.status}")
        end
      end

      def self.known_streaming_event?(kind : String) : Bool
        {
          "response.created",
          "response.in_progress",
          "response.completed",
          "response.failed",
          "response.incomplete",
          "response.output_item.added",
          "response.output_item.done",
          "response.content_part.added",
          "response.content_part.done",
          "response.output_text.delta",
          "response.output_text.done",
          "response.refusal.delta",
          "response.refusal.done",
          "response.function_call_arguments.delta",
          "response.function_call_arguments.done",
          "response.reasoning_summary_part.added",
          "response.reasoning_summary_part.done",
          "response.reasoning_summary_text.delta",
          "response.reasoning_summary_text.done",
        }.includes?(kind)
      end

      # ameba:disable Naming/PredicateName
      def self.is_known_streaming_event(kind : String) : Bool
        known_streaming_event?(kind)
      end

      # ameba:enable Naming/PredicateName

      def self.parse_server_event(payload : String) : ResponsesWebSocketEvent?
        value = JSON.parse(payload)
        kind = value["type"].as_s
        case kind
        when "error"
          ResponsesWebSocketEvent.error(ResponsesWebSocketErrorEvent.from_json_value(value))
        when "response.done"
          ResponsesWebSocketEvent.done(ResponsesWebSocketDoneEvent.from_json_value(value))
        else
          return unless known_streaming_event?(kind)
          chunk = if value["response"]?
                    StreamingResponseChunk.new(ResponseChunk.from_json(payload))
                  else
                    StreamingDeltaChunk.new(ItemChunk.from_json_value(value))
                  end
          case chunk
          when StreamingResponseChunk
            ResponsesWebSocketEvent.response(chunk.chunk)
          when StreamingDeltaChunk
            ResponsesWebSocketEvent.item(chunk.chunk)
          end
        end
      end

      def self.websocket_url(base_url : String) : String
        uri = URI.parse(base_url)
        scheme = case uri.scheme
                 when "https" then "wss"
                 when "http"  then "ws"
                 else
                   raise Crig::Completion::CompletionError.new("Unsupported base URL scheme for OpenAI websocket mode: #{uri.scheme}")
                 end
        path = "#{uri.path.to_s.rstrip('/')}/responses"
        URI.new(
          scheme: scheme,
          host: uri.host,
          port: uri.port,
          path: path,
          query: uri.query,
        ).to_s
      end
    end
  end
end
