module Crig
  module Loaders
    class FileLoaderError < Exception
      enum Kind
        InvalidGlobPattern
        IoError
        PatternError
        GlobError
        StringUtf8Error
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

      def self.pattern_error(message : String) : self
        new(Kind::PatternError, "Pattern error: #{message}")
      end

      def self.glob_error(message : String) : self
        new(Kind::GlobError, "Glob error: #{message}")
      end

      def self.string_utf8_error(error : Exception) : self
        new(Kind::StringUtf8Error, "String conversion error: #{error.message || error.class.name}")
      end
    end

    struct FileLoader(T)
      include Enumerable(T)

      def initialize(&@next_item : -> T?)
      end

      def self.with_glob(pattern : String) : FileLoader(String | FileLoaderError)
        paths = Dir.glob(pattern)
        index = 0

        FileLoader(String | FileLoaderError).new do
          if index >= paths.size
            nil
          else
            item = paths[index]
            index += 1
            item.as(String | FileLoaderError)
          end
        end
      rescue ex : Exception
        raise FileLoaderError.invalid_glob_pattern(ex.message || pattern)
      end

      def self.with_dir(directory : String) : FileLoader(String | FileLoaderError)
        entries = Dir.children(directory).compact_map do |entry|
          path = File.join(directory, entry)
          next unless File.file?(path)
          path.as(String | FileLoaderError)
        end

        index = 0
        FileLoader(String | FileLoaderError).new do
          if index >= entries.size
            nil
          else
            item = entries[index]
            index += 1
            item
          end
        end
      rescue ex : Exception
        raise FileLoaderError.io_error(ex)
      end

      def self.from_bytes(bytes : Array(UInt8)) : FileLoader(Array(UInt8))
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

      def self.from_bytes_multi(bytes_vec : Array(Array(UInt8))) : FileLoader(Array(UInt8))
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

      def read : FileLoader(String | FileLoaderError)
        source = into_iter
        FileLoader(String | FileLoaderError).new do
          item = source.next
          item ? read_item(item) : nil
        end
      end

      def read_with_path : FileLoader(Tuple(String, String) | FileLoaderError)
        source = into_iter
        FileLoader(Tuple(String, String) | FileLoaderError).new do
          item = source.next
          item ? read_item_with_path(item) : nil
        end
      end

      def ignore_errors
        source = into_iter
        {% if T.union? %}
          {% kept_types = T.union_types.reject { |type| type.resolve == Crig::Loaders::FileLoaderError } %}
          {% if kept_types.size == 1 %}
            FileLoader({{ kept_types.first }}).new do
              loop do
                item = source.next
                break unless item
                next if item.is_a?(FileLoaderError)
                break item.as({{ kept_types.first }})
              end
            end
          {% else %}
            self.class.new do
              loop do
                item = source.next
                break unless item
                next if item.is_a?(FileLoaderError)
                break item
              end
            end
          {% end %}
        {% else %}
          self
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

      private def read_item(item) : String | FileLoaderError
        case item
        when String
          begin
            File.read(item)
          rescue ex : Exception
            FileLoaderError.io_error(ex)
          end
        when Array(UInt8)
          begin
            String.new(Slice.new(item.to_unsafe, item.size))
          rescue ex : Exception
            FileLoaderError.string_utf8_error(ex)
          end
        when FileLoaderError
          item
        else
          FileLoaderError.io_error(Exception.new("Unsupported file loader item"))
        end
      end

      private def read_item_with_path(item) : Tuple(String, String) | FileLoaderError
        case item
        when String
          begin
            {item, File.read(item)}
          rescue ex : Exception
            FileLoaderError.io_error(ex)
          end
        when Array(UInt8)
          begin
            {"<memory>", String.new(Slice.new(item.to_unsafe, item.size))}
          rescue ex : Exception
            FileLoaderError.string_utf8_error(ex)
          end
        when FileLoaderError
          item
        else
          FileLoaderError.io_error(Exception.new("Unsupported file loader item"))
        end
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
