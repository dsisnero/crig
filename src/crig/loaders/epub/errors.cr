module Crig
  module Loaders
    module Epub
      class EpubLoaderError < Exception
        enum Kind
          EpubError
          FileLoaderError
          TextProcessorError
        end

        getter kind : Kind

        def initialize(@kind : Kind, message : String)
          super(message)
        end

        def self.epub_error(message : String) : self
          new(Kind::EpubError, "IO error: #{message}")
        end

        def self.file_loader_error(error : Crig::Loaders::FileLoaderError) : self
          new(Kind::FileLoaderError, "File loader error: #{error.message}")
        end

        def self.text_processor_error(error : Exception) : self
          new(Kind::TextProcessorError, "Text processor error: #{error.message || error.class.name}")
        end
      end
    end
  end
end
