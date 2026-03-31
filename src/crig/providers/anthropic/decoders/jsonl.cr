module Crig
  module Providers
    module Anthropic
      module Decoders
        class JSONLDecoderError < Exception
        end

        struct JSONLDecoder(T)
          @line_decoder : LineDecoder
          @buffer : Array(T)

          def initialize
            @line_decoder = LineDecoder.new
            @buffer = [] of T
          end

          def process_chunk(chunk : Bytes) : Array(T)
            process_lines(@line_decoder.decode(chunk))
          end

          def process_chunk(chunk : String) : Array(T)
            process_chunk(chunk.to_slice)
          end

          def flush : Array(T)
            process_lines(@line_decoder.flush)
          end

          private def process_lines(lines : Array(String)) : Array(T)
            results = [] of T
            lines.each do |line|
              next if line.strip.empty?
              results << T.from_json(line)
            rescue ex : JSON::ParseException
              raise JSONLDecoderError.new("Failed to parse JSON: #{ex.message}")
            end
            results
          end
        end
      end
    end
  end
end
