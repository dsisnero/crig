module Crig
  module Providers
    module Anthropic
      module Decoders
        struct LineDecoder
          @buffer : Bytes
          @carriage_return_index : Int32?

          def initialize
            @buffer = Bytes.empty
            @carriage_return_index = nil
          end

          # ameba:disable Metrics/CyclomaticComplexity
          def decode(chunk : Bytes) : Array(String)
            return [] of String if chunk.empty?

            @buffer = Bytes.new(@buffer.size + chunk.size) do |index|
              if index < @buffer.size
                @buffer[index]
              else
                chunk[index - @buffer.size]
              end
            end

            lines = [] of String

            while pattern = self.class.find_newline_index(@buffer, @carriage_return_index)
              if pattern.carriage? && @carriage_return_index.nil?
                @carriage_return_index = pattern.index
                next
              end

              if cr_index = @carriage_return_index
                if pattern.index != cr_index + 1 || pattern.carriage?
                  lines << (cr_index > 0 ? self.class.decode_text(@buffer[0...(cr_index - 1)]) : "")
                  @buffer = cr_index < @buffer.size ? @buffer[cr_index..] : Bytes.empty
                  @carriage_return_index = nil
                  next
                end
              end

              end_index = @carriage_return_index ? pattern.preceding - 1 : pattern.preceding
              lines << (end_index > 0 ? self.class.decode_text(@buffer[0...end_index]) : "")
              @buffer = pattern.index < @buffer.size ? @buffer[pattern.index..] : Bytes.empty
              @carriage_return_index = nil
            end

            lines
          end

          # ameba:enable Metrics/CyclomaticComplexity

          def decode(chunk : String) : Array(String)
            decode(chunk.to_slice)
          end

          def flush : Array(String)
            return [] of String if @buffer.empty?

            decode("\n")
          end

          def self.decode_chunks(chunks : Array(Bytes), flush : Bool) : Array(String)
            decoder = new
            lines = [] of String
            chunks.each do |chunk|
              lines.concat(decoder.decode(chunk))
            end
            lines.concat(decoder.flush) if flush
            lines
          end

          def self.decode_chunks(chunks : Array(String), flush : Bool) : Array(String)
            decode_chunks(chunks.map(&.to_slice), flush)
          end

          def self.find_double_newline_index(buffer : Bytes) : Int32
            newline = '\n'.ord.to_u8
            carriage = '\r'.ord.to_u8

            0.upto(buffer.size - 2) do |i|
              return i + 2 if buffer[i] == newline && buffer[i + 1] == newline
              return i + 2 if buffer[i] == carriage && buffer[i + 1] == carriage
              if i + 3 < buffer.size &&
                 buffer[i] == carriage &&
                 buffer[i + 1] == newline &&
                 buffer[i + 2] == carriage &&
                 buffer[i + 3] == newline
                return i + 4
              end
            end

            -1
          end

          struct NewlineIndex
            getter preceding : Int32
            getter index : Int32
            getter? carriage : Bool

            def initialize(@preceding : Int32, @index : Int32, @carriage : Bool)
            end
          end

          def self.find_newline_index(buffer : Bytes, start_index : Int32?) : NewlineIndex?
            newline = '\n'.ord.to_u8
            carriage = '\r'.ord.to_u8
            start = start_index || 0

            start.upto(buffer.size - 1) do |i|
              byte = buffer[i]
              return NewlineIndex.new(i, i + 1, false) if byte == newline
              return NewlineIndex.new(i, i + 1, true) if byte == carriage
            end

            nil
          end

          def self.decode_text(bytes : Bytes) : String
            String.new(bytes)
          rescue ArgumentError
            String.new(bytes, "UTF-8", invalid: :skip)
          end
        end
      end
    end
  end
end
