module Crig
  module HttpClient
    struct Part
      enum ContentKind
        Text
        Binary
      end

      getter name : String
      getter filename : String?
      getter content_type : String?
      getter text_value : String?
      getter binary_value : Bytes?
      getter content_kind : ContentKind

      def initialize(
        @name : String,
        @content_kind : ContentKind,
        @text_value : String? = nil,
        @binary_value : Bytes? = nil,
        @filename : String? = nil,
        @content_type : String? = nil,
      )
      end

      def self.text(name : String, value : String) : self
        new(name, ContentKind::Text, text_value: value)
      end

      def self.bytes(name : String, data : Bytes) : self
        new(name, ContentKind::Binary, binary_value: data)
      end

      def filename(filename : String) : self
        self.class.new(@name, @content_kind, @text_value, @binary_value, filename, @content_type)
      end

      def content_type(content_type : String) : self
        self.class.new(@name, @content_kind, @text_value, @binary_value, @filename, content_type)
      end

      # ameba:disable Naming/AccessorMethodName
      def get_filename : String?
        @filename
      end

      # ameba:enable Naming/AccessorMethodName

      # ameba:disable Naming/AccessorMethodName
      def get_content_type : String?
        @content_type
      end
      # ameba:enable Naming/AccessorMethodName
    end

    struct MultipartForm
      getter parts : Array(Part)
      getter boundary : String?

      def initialize(@parts : Array(Part) = [] of Part, @boundary : String? = nil)
      end

      def part(part : Part) : self
        self.class.new(@parts + [part], @boundary)
      end

      def text(name : String, value : String) : self
        part(Part.text(name, value))
      end

      def file(name : String, filename : String, content_type : String, data : Bytes) : self
        part(Part.bytes(name, data).filename(filename).content_type(content_type))
      end

      def boundary(boundary : String) : self
        self.class.new(@parts, boundary)
      end

      def encode : {String, Bytes}
        boundary = @boundary || self.class.generate_boundary
        io = IO::Memory.new

        @parts.each do |part|
          io << "--" << boundary << "\r\n"
          io << "Content-Disposition: form-data; name=\"#{part.name}\""
          if filename = part.filename
            io << "; filename=\"#{filename}\""
          end
          io << "\r\n"

          if content_type = part.content_type
            io << "Content-Type: " << content_type << "\r\n"
          end

          io << "\r\n"

          case part.content_kind
          in .text?
            io << (part.text_value || raise "multipart text part missing value")
          in .binary?
            io.write(part.binary_value || raise "multipart binary part missing value")
          end

          io << "\r\n"
        end

        io << "--" << boundary << "--\r\n"
        {boundary, io.to_s.to_slice}
      end

      def self.generate_boundary : String
        "----boundary#{Time.utc.nanosecond}"
      end
    end
  end
end
