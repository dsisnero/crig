module Crig
  module Providers
    module Anthropic
      module Decoders
        class SSEDecoderError < Exception
        end

        struct ServerSentEvent
          getter event : String?
          getter data : String
          getter raw : Array(String)

          def initialize(@data : String, @event : String? = nil, @raw : Array(String) = [] of String)
          end
        end

        struct SSEDecoder
          @data : Array(String)
          @event : String?
          @chunks : Array(String)

          def initialize
            @data = [] of String
            @event = nil
            @chunks = [] of String
          end

          def decode(line : String) : ServerSentEvent?
            normalized = line.ends_with?('\r') ? line[0...-1] : line

            if normalized.empty?
              return if @event.nil? && @data.empty?

              sse = ServerSentEvent.new(@data.join('\n'), @event, @chunks.dup)
              @event = nil
              @data.clear
              @chunks.clear
              return sse
            end

            @chunks << normalized
            return if normalized.starts_with?(':')

            parts = normalized.split(':', limit: 2)
            field_name = parts[0]
            value = parts.size == 2 ? parts[1] : ""
            value = value.starts_with?(' ') ? value[1..] : value

            case field_name
            when "event"
              @event = value
            when "data"
              @data << value
            end

            nil
          end

          def self.extract_sse_chunk(buffer : Bytes) : {Bytes, Bytes}?
            pattern_index = LineDecoder.find_double_newline_index(buffer)
            return unless pattern_index > 0

            {
              buffer[0, pattern_index],
              buffer[pattern_index, buffer.size - pattern_index],
            }
          end

          def self.iter_sse_messages(chunks : Enumerable(Bytes)) : Array(ServerSentEvent)
            sse_decoder = new
            line_decoder = LineDecoder.new
            buffer = Bytes.empty
            events = [] of ServerSentEvent

            chunks.each do |chunk|
              buffer = Bytes.new(buffer.size + chunk.size) do |index|
                if index < buffer.size
                  buffer[index]
                else
                  chunk[index - buffer.size]
                end
              end

              while extracted = extract_sse_chunk(buffer)
                chunk_data, remaining = extracted
                buffer = remaining
                line_decoder.decode(chunk_data).each do |line|
                  if sse = sse_decoder.decode(line)
                    events << sse
                  end
                end
              end
            end

            line_decoder.flush.each do |line|
              if sse = sse_decoder.decode(line)
                events << sse
              end
            end

            if sse = sse_decoder.decode("")
              events << sse
            end

            events
          end
        end
      end
    end
  end
end
