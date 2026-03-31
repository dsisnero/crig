require "compress/zip"
require "xml"

module Crig
  module Loaders
    module Epub
      class Document
        getter chapters : Array(String)

        def initialize(@chapters : Array(String), @index : Int32 = 0)
        end

        def current_str : {String, Nil}?
          chapter = @chapters[@index]?
          chapter ? {chapter, nil} : nil
        end

        def go_next : Bool
          @index += 1
          @index < @chapters.size
        end
      end

      struct EpubFileLoader(T, P)
        include Enumerable(T)

        def initialize(&@next_item : -> T?)
        end

        def self.with_glob(pattern : String) : EpubFileLoader(PathResult, P)
          base_loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_glob(pattern)
          source = base_loader.into_iter

          new do
            item = source.next
            next unless item
            case item
            when String
              item
            when Crig::Loaders::FileLoaderError
              EpubLoaderError.file_loader_error(item)
            end
          end
        end

        def self.with_dir(directory : String) : EpubFileLoader(PathResult, P)
          base_loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_dir(directory)
          source = base_loader.into_iter

          new do
            item = source.next
            next unless item
            case item
            when String
              item
            when Crig::Loaders::FileLoaderError
              EpubLoaderError.file_loader_error(item)
            end
          end
        end

        def load : EpubFileLoader(DocumentResult, P)
          source = into_iter
          EpubFileLoader(DocumentResult, P).new do
            item = source.next
            next unless item
            case item
            when String
              begin
                load_document(item)
              rescue ex : EpubLoaderError
                ex
              end
            when EpubLoaderError
              item
            end
          end
        end

        def load_with_path : EpubFileLoader(PathDocumentResult, P)
          source = into_iter
          EpubFileLoader(PathDocumentResult, P).new do
            item = source.next
            next unless item
            case item
            when String
              begin
                {item, load_document(item)}
              rescue ex : EpubLoaderError
                ex
              end
            when EpubLoaderError
              item
            end
          end
        end

        def read : EpubFileLoader(StringResult, P)
          source = load.into_iter
          EpubFileLoader(StringResult, P).new do
            item = source.next
            next unless item
            case item
            when Document
              begin
                read_document(item)
              rescue ex : EpubLoaderError
                ex
              end
            when EpubLoaderError
              item
            end
          end
        end

        def read_with_path : EpubFileLoader(PathStringResult, P)
          source = load_with_path.into_iter
          EpubFileLoader(PathStringResult, P).new do
            item = source.next
            next unless item
            case item
            when Tuple(String, Document)
              begin
                {item[0], read_document(item[1])}
              rescue ex : EpubLoaderError
                ex
              end
            when EpubLoaderError
              item
            end
          end
        end

        def by_chapter : EpubFileLoader(ByChapterResult, P)
          source = into_iter
          EpubFileLoader(ByChapterResult, P).new do
            item = source.next
            next unless item
            case item
            when Document
              by_chapter_document(item)
            when Tuple(String, Document)
              {item[0], by_chapter_document(item[1])}
            when EpubLoaderError
              item
            end
          end
        end

        def ignore_errors : self
          source = into_iter
          self.class.new do
            loop do
              item = source.next
              break unless item
              next if item.is_a?(EpubLoaderError)
              break item
            end
          end
        end

        def each(& : T ->) : Nil
          iterator = into_iter
          while item = iterator.next
            yield item
          end
        end

        def to_a : Array(T)
          items = [] of T
          each { |item| items << item }
          items
        end

        def into_iter : IntoIter(T)
          IntoIter(T).new(@next_item)
        end

        private def load_document(path : String) : Document
          chapters = [] of String

          Compress::Zip::File.open(path) do |zip|
            container = read_zip_entry(zip, "META-INF/container.xml")
            opf_path = package_path_from_container(container)
            opf = read_zip_entry(zip, opf_path)
            manifest, spine = manifest_and_spine_from_package(opf)
            base_dir = File.dirname(opf_path)

            spine.each do |idref|
              href = manifest[idref]? || next
              full_path = normalize_archive_path(base_dir, href)
              chapter = read_zip_entry(zip, full_path)
              chapters << chapter
            end
          end

          Document.new(chapters)
        rescue ex : Compress::Zip::Error
          raise EpubLoaderError.epub_error(ex.message || ex.class.name)
        rescue ex : XML::Error
          raise EpubLoaderError.epub_error(ex.message || ex.class.name)
        rescue ex : KeyError
          raise EpubLoaderError.epub_error(ex.message || ex.class.name)
        end

        private def read_document(document : Document) : String
          by_chapter_document(document).map do |chapter|
            case chapter
            when String
              chapter
            when EpubLoaderError
              raise chapter
            end
          end.join
        end

        private def by_chapter_document(document : Document) : Array(String | EpubLoaderError)
          iterator = EpubChapterIterator(P).new(document)
          chapters = [] of String | EpubLoaderError
          while chapter = iterator.next
            chapters << chapter
          end
          chapters
        end

        private def read_zip_entry(zip : Compress::Zip::File, entry_name : String) : String
          entry = zip[entry_name]
          IO::Memory.new.tap do |io|
            entry.open do |entry_io|
              IO.copy(entry_io, io)
            end
          end.to_s
        end

        private def package_path_from_container(container_xml : String) : String
          document = XML.parse(container_xml)
          rootfile = document.first_element_child
            .try(&.children.select(&.element?))
            .try(&.flat_map(&.children.select(&.element?)))
            .try(&.find { |node| node.name == "rootfile" }) ||
                     raise KeyError.new("Missing rootfile in EPUB container")

          rootfile["full-path"]
        end

        private def manifest_and_spine_from_package(opf_xml : String) : {Hash(String, String), Array(String)}
          document = XML.parse(opf_xml)
          package = document.first_element_child || raise KeyError.new("Missing package root in EPUB")

          manifest_node = package.children.select(&.element?).find { |node| node.name == "manifest" } ||
                          raise KeyError.new("Missing manifest in EPUB package")
          spine_node = package.children.select(&.element?).find { |node| node.name == "spine" } ||
                       raise KeyError.new("Missing spine in EPUB package")

          manifest = {} of String => String
          manifest_node.children.select(&.element?).each do |node|
            next unless node.name == "item"
            id = node["id"]?
            href = node["href"]?
            next unless id && href
            manifest[id] = href
          end

          spine = [] of String
          spine_node.children.select(&.element?).each do |node|
            next unless node.name == "itemref"
            idref = node["idref"]?
            spine << idref if idref
          end

          {manifest, spine}
        end

        private def normalize_archive_path(base_dir : String, href : String) : String
          parts = [] of String
          [base_dir, href].each do |segment|
            next if segment.empty?
            segment.split('/').each do |part|
              next if part.empty? || part == "."
              if part == ".."
                parts.pop?
              else
                parts << part
              end
            end
          end
          parts.join('/')
        end
      end

      class EpubChapterIterator(P)
        def initialize(@document : Document, @finished : Bool = false)
        end

        def next : String | EpubLoaderError | Nil
          return if @finished

          while !@finished
            chapter = @document.current_str
            @finished = true unless @document.go_next
            next unless chapter

            text = chapter[0]
            next if text.empty?

            begin
              return P.process(text)
            rescue ex : Exception
              return EpubLoaderError.text_processor_error(ex)
            end
          end

          nil
        end
      end

      alias PathResult = String | EpubLoaderError
      alias DocumentResult = Document | EpubLoaderError
      alias PathDocumentResult = Tuple(String, Document) | EpubLoaderError
      alias StringResult = String | EpubLoaderError
      alias PathStringResult = Tuple(String, String) | EpubLoaderError
      alias ByChapterValue = Array(String | EpubLoaderError)
      alias ByChapterResult = ByChapterValue | Tuple(String, ByChapterValue) | EpubLoaderError

      struct IntoIter(T)
        def initialize(@next_item : -> T?)
        end

        def next : T?
          @next_item.call
        end
      end
    end
  end
end
