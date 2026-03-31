require "pdfbox"

module Crig
  module Loaders
    class PdfLoaderError < Exception
      enum Kind
        InvalidGlobPattern
        IoError
        PdfError
      end

      getter kind : Kind

      def initialize(@kind : Kind, message : String)
        super(message)
      end

      def self.invalid_glob_pattern(message : String) : self
        new(Kind::InvalidGlobPattern, "Invalid glob pattern: #{message}")
      end

      def self.io_error(error : Exception) : self
        new(Kind::IoError, "IO error: #{error.message || error.class.name}")
      end

      def self.pdf_error(error : Exception) : self
        new(Kind::PdfError, "PDF error: #{error.message || error.class.name}")
      end
    end

    alias PdfDocument = Pdfbox::Pdmodel::Document
    alias PathDocument = Tuple(String, PdfDocument)
    alias PdfPageResult = Tuple(String, Array(Tuple(Int32, String | PdfLoaderError)))
    alias PdfPageSuccess = Tuple(String, Array(Tuple(Int32, String)))

    struct PdfFileLoader(T)
      include Enumerable(T)

      def initialize(&@next_item : -> T?)
      end

      def self.with_glob(pattern : String) : PdfFileLoader(String | PdfLoaderError)
        paths = Dir.glob(pattern)
        index = 0

        new do
          if index >= paths.size
            nil
          else
            item = paths[index]
            index += 1
            item.as(String | PdfLoaderError)
          end
        end
      rescue ex : Exception
        raise PdfLoaderError.invalid_glob_pattern(ex.message || pattern)
      end

      def self.with_dir(directory : String) : PdfFileLoader(String | PdfLoaderError)
        entries = Dir.children(directory).compact_map do |entry|
          path = File.join(directory, entry)
          next unless File.file?(path)
          path.as(String | PdfLoaderError)
        end

        index = 0
        new do
          if index >= entries.size
            nil
          else
            item = entries[index]
            index += 1
            item
          end
        end
      rescue ex : Exception
        raise PdfLoaderError.io_error(ex)
      end

      def self.from_bytes(bytes : Array(UInt8)) : PdfFileLoader(Array(UInt8))
        yielded = false
        new do
          if yielded
            nil
          else
            yielded = true
            bytes
          end
        end
      end

      def self.from_bytes_multi(bytes_vec : Array(Array(UInt8))) : PdfFileLoader(Array(UInt8))
        index = 0
        new do
          if index >= bytes_vec.size
            nil
          else
            item = bytes_vec[index]
            index += 1
            item
          end
        end
      end

      def load : PdfFileLoader(PdfDocument | PdfLoaderError)
        source = into_iter
        PdfFileLoader(PdfDocument | PdfLoaderError).new do
          item = source.next
          item ? load_item(item) : nil
        end
      end

      def load_with_path : PdfFileLoader(Tuple(String, PdfDocument) | PdfLoaderError)
        source = into_iter
        PdfFileLoader(Tuple(String, PdfDocument) | PdfLoaderError).new do
          item = source.next
          item ? load_item_with_path(item) : nil
        end
      end

      def read : PdfFileLoader(String | PdfLoaderError)
        source = into_iter
        PdfFileLoader(String | PdfLoaderError).new do
          item = source.next
          item ? read_item(item) : nil
        end
      end

      def read_with_path : PdfFileLoader(Tuple(String, String) | PdfLoaderError)
        source = into_iter
        PdfFileLoader(Tuple(String, String) | PdfLoaderError).new do
          item = source.next
          item ? read_item_with_path(item) : nil
        end
      end

      def by_page
        {% if T == PdfDocument || T.union_types.any? { |type| type == PdfDocument } %}
          source = into_iter
          pending = [] of String | PdfLoaderError
          PdfFileLoader(String | PdfLoaderError).new do
            loop do
              if pending.size > 0
                break pending.shift?
              end

              item = source.next
              break nil unless item

              case item
              when PdfDocument
                pending.concat(pages_for_document(item))
              when PdfLoaderError
                pending << item
              else
                pending << PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader item for by_page"))
              end
            end
          end
        {% elsif T == PathDocument || T.union_types.any? { |type| type == PathDocument } %}
          source = into_iter
          PdfFileLoader(PdfPageResult).new do
            loop do
              item = source.next
              break nil unless item

              case item
              when PdfLoaderError
                next
              when PathDocument
                path = item[0]
                document = item[1]
                pages = [] of Tuple(Int32, String | PdfLoaderError)
                document.pages.each_with_index do |page, index|
                  begin
                    pages << {index, extract_page_text(page)}
                  rescue ex : Exception
                    pages << {index, PdfLoaderError.pdf_error(ex)}
                  end
                end
                break {path, pages}
              end
            end
          end
        {% else %}
          raise PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader state for by_page"))
        {% end %}
      end

      def ignore_errors
        {% if T == PdfPageResult %}
          source = into_iter
          PdfFileLoader(PdfPageSuccess).new do
            item = source.next
            next unless item

            path = item[0]
            pages = item[1].compact_map do |page|
              content = page[1]
              next if content.is_a?(PdfLoaderError)
              {page[0], content.as(String)}
            end
            {path, pages}
          end
        {% else %}
          source = into_iter
          self.class.new do
            loop do
              item = source.next
              break unless item
              next if item.is_a?(PdfLoaderError)
              break item
            end
          end
        {% end %}
      end

      def each(& : T ->) : Nil
        iterator = into_iter
        while item = iterator.next
          yield item
        end
      end

      def into_iter : IntoIter(T)
        IntoIter(T).new(@next_item)
      end

      def to_a : Array(T)
        items = [] of T
        each { |item| items << item }
        items
      end

      private def load_item(item) : PdfDocument | PdfLoaderError
        case item
        when String
          begin
            Pdfbox::Loader.load_pdf(item)
          rescue ex : Exception
            PdfLoaderError.pdf_error(ex)
          end
        when Array(UInt8)
          begin
            slice = Slice(UInt8).new(item.size) { |index| item[index] }
            Pdfbox::Loader.load_pdf(slice)
          rescue ex : Exception
            PdfLoaderError.pdf_error(ex)
          end
        when PdfLoaderError
          item
        else
          PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader item"))
        end
      end

      private def load_item_with_path(item) : Tuple(String, PdfDocument) | PdfLoaderError
        case item
        when String
          loaded = load_item(item)
          loaded.is_a?(PdfDocument) ? {item, loaded} : loaded
        when Array(UInt8)
          loaded = load_item(item)
          loaded.is_a?(PdfDocument) ? {"<memory>", loaded} : loaded
        when PdfLoaderError
          item
        else
          PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader item"))
        end
      end

      private def read_item(item) : String | PdfLoaderError
        case item
        when String, Array(UInt8)
          loaded = load_item(item)
          return loaded unless loaded.is_a?(PdfDocument)
          document_text(loaded)
        when Tuple(String, PdfDocument)
          document_text(item[1])
        when PdfDocument
          document_text(item)
        when PdfLoaderError
          item
        else
          PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader item"))
        end
      end

      private def read_item_with_path(item) : Tuple(String, String) | PdfLoaderError
        case item
        when String, Array(UInt8)
          loaded = load_item_with_path(item)
          return loaded unless loaded.is_a?(Tuple(String, PdfDocument))
          {loaded[0], document_text(loaded[1])}
        when Tuple(String, PdfDocument)
          {item[0], document_text(item[1])}
        when PdfLoaderError
          item
        else
          PdfLoaderError.pdf_error(Exception.new("Unsupported PDF loader item"))
        end
      end

      private def document_text(document : PdfDocument) : String
        pages = pages_for_document(document)
        text = String.build do |io|
          pages.each do |page|
            next unless page.is_a?(String)
            io << page
          end
        end
        text
      rescue ex : Exception
        raise PdfLoaderError.pdf_error(ex)
      end

      private def pages_for_document(document : PdfDocument) : Array(String | PdfLoaderError)
        pages = [] of String | PdfLoaderError
        document.pages.each do |page|
          begin
            pages << extract_page_text(page)
          rescue ex : Exception
            pages << PdfLoaderError.pdf_error(ex)
          end
        end
        pages
      end

      private def extract_page_text(page : Pdfbox::Pdmodel::Page) : String
        content_stream = page.contents
        return "" unless content_stream

        stream = content_stream.create_input_stream.gets_to_end
        font_maps = extract_font_maps(page)
        current_font = ""
        blocks = [] of String
        current_block = ""
        in_text_block = false

        stream.each_line do |line|
          stripped = line.strip
          case stripped
          when "BT"
            in_text_block = true
            current_block = ""
          when "ET"
            if in_text_block && !current_block.empty?
              blocks << current_block
            end
            in_text_block = false
          else
            if match = stripped.match(/\/([^\s]+)\s+[-\d.]+\s+Tf/)
              current_font = match[1]
            end

            next unless in_text_block

            if stripped.ends_with?("TJ")
              current_block += decode_text_array(stripped, font_maps[current_font]?)
            elsif stripped.ends_with?("Tj")
              current_block += decode_text_operand(stripped, font_maps[current_font]?)
            end
          end
        end

        return "" if blocks.empty?
        "#{blocks.join("\n")}\n"
      end

      private def extract_font_maps(page : Pdfbox::Pdmodel::Page) : Hash(String, Hash(String, String))
        maps = {} of String => Hash(String, String)
        resources = page.resources
        return maps unless resources

        font_dict = resources.cos_object[Pdfbox::Cos::Name.new("Font")]?
        if font_dict.is_a?(Pdfbox::Cos::Object)
          font_dict = font_dict.object
        end
        return maps unless font_dict.is_a?(Pdfbox::Cos::Dictionary)

        font_dict.entries.each do |name, value|
          font = value
          if font.is_a?(Pdfbox::Cos::Object)
            font = font.object
          end
          next unless font.is_a?(Pdfbox::Cos::Dictionary)

          to_unicode = font[Pdfbox::Cos::Name.new("ToUnicode")]?
          if to_unicode.is_a?(Pdfbox::Cos::Object)
            to_unicode = to_unicode.object
          end
          next unless to_unicode.is_a?(Pdfbox::Cos::Stream)

          maps[name.value] = parse_tounicode_map(to_unicode.create_input_stream.gets_to_end)
        end

        maps
      end

      private def parse_tounicode_map(cmap : String) : Hash(String, String)
        mappings = {} of String => String
        in_bfchar = false
        in_bfrange = false

        cmap.each_line do |line|
          stripped = line.strip
          case stripped
          when .ends_with?("beginbfchar")
            in_bfchar = true
            in_bfrange = false
          when .ends_with?("beginbfrange")
            in_bfrange = true
            in_bfchar = false
          when "endbfchar", "endbfrange"
            in_bfchar = false
            in_bfrange = false
          else
            if in_bfchar
              if match = stripped.match(/^<([0-9A-Fa-f]+)>\s+<([0-9A-Fa-f]+)>$/)
                mappings[match[1].upcase] = unicode_from_hex(match[2])
              end
            elsif in_bfrange
              if match = stripped.match(/^<([0-9A-Fa-f]+)>\s+<([0-9A-Fa-f]+)>\s+<([0-9A-Fa-f]+)>$/)
                start_code = match[1].to_i(16)
                end_code = match[2].to_i(16)
                start_target = match[3].to_i(16)

                (start_code..end_code).each_with_index do |code, offset|
                  mappings[code.to_s(16).upcase.rjust(match[1].size, '0')] = unicode_from_codepoint(start_target + offset)
                end
              end
            end
          end
        end

        mappings
      end

      private def decode_text_array(line : String, map : Hash(String, String)?) : String
        String.build do |io|
          line.scan(/<([0-9A-Fa-f]+)>/) do |match|
            io << decode_hex_text(match[1], map)
          end
        end
      end

      private def decode_text_operand(line : String, map : Hash(String, String)?) : String
        if match = line.match(/<([0-9A-Fa-f]+)>\s*Tj$/)
          decode_hex_text(match[1], map)
        else
          ""
        end
      end

      private def decode_hex_text(hex : String, map : Hash(String, String)?) : String
        return fallback_hex_text(hex) if map.nil? || map.empty?

        key_length = map.keys.first?.try(&.size) || 4
        String.build do |io|
          index = 0
          while index < hex.size
            remaining = hex.size - index
            break if remaining < key_length

            code = hex[index, key_length].upcase
            io << (map[code]? || fallback_hex_text(code))
            index += key_length
          end
        end
      end

      private def fallback_hex_text(hex : String) : String
        if hex.size % 4 == 0
          String.build do |io|
            index = 0
            while index < hex.size
              io << unicode_from_hex(hex[index, 4])
              index += 4
            end
          end
        else
          ""
        end
      end

      private def unicode_from_hex(hex : String) : String
        unicode_from_codepoint(hex.to_i(16))
      end

      private def unicode_from_codepoint(codepoint : Int32) : String
        codepoint.chr.to_s
      rescue ex : ArgumentError
        ""
      end
    end

    struct IntoIter(T)
      def initialize(@next_item : -> T?)
      end

      def next : T?
        @next_item.call
      end
    end
  end
end
