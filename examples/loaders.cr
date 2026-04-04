require "../src/crig"

module Crig::Examples::Loaders
  def self.read_glob(pattern : String) : Array(String | Crig::Loaders::FileLoaderError)
    Crig::Loaders::FileLoader(String)
      .with_glob(pattern)
      .read
      .to_a
  end
end
