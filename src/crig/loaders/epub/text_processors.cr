require "xml"

module Crig
  module Loaders
    module Epub
      module TextProcessor
        abstract def process(text : String) : String
      end

      class XmlProcessingError < Exception
        enum Kind
          Xml
          Encoding
          Utf8
        end

        getter kind : Kind

        def initialize(@kind : Kind, message : String)
          super(message)
        end

        def self.xml(error : Exception) : self
          new(Kind::Xml, "XML parsing error: #{error.message || error.class.name}")
        end

        def self.encoding(error : Exception) : self
          new(Kind::Encoding, "Failed to unescape XML entity: #{error.message || error.class.name}")
        end

        def self.utf8(error : Exception) : self
          new(Kind::Utf8, "Invalid UTF-8 sequence: #{error.message || error.class.name}")
        end
      end

      struct RawTextProcessor
        include TextProcessor

        def self.process(text : String) : String
          new.process(text)
        end

        def process(text : String) : String
          text
        end
      end

      struct StripXmlProcessor
        include TextProcessor

        def self.process(text : String) : String
          new.process(text)
        end

        def process(text : String) : String
          reader = XML::Reader.new(text.strip)
          result = String.build do |io|
            last_was_text = false

            while reader.read
              case reader.node_type
              when XML::Reader::Type::TEXT, XML::Reader::Type::CDATA
                text = reader.value
                next if text.strip.empty?

                io << ' ' if last_was_text
                io << text
                last_was_text = true
              else
                last_was_text = false
              end
            end
          end

          unless reader.errors.empty?
            raise XmlProcessingError.xml(reader.errors.first)
          end

          result
        rescue ex : XML::Error
          raise XmlProcessingError.xml(ex)
        end
      end
    end
  end
end
