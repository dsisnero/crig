require "file_utils"
require "../spec_helper"
describe Crig::Loaders::FileLoader do
  it "loads files from a glob and reads their contents" do
    dir = File.join(Dir.tempdir, "crig-file-loader-#{Random::Secure.hex(8)}")
    Dir.mkdir(dir)

    begin
      File.write(File.join(dir, "foo.txt"), "foo")
      File.write(File.join(dir, "bar.txt"), "bar")

      glob = File.join(dir, "*.txt")
      loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_glob(glob)
      actual = loader
        .ignore_errors
        .read
        .ignore_errors
        .into_iter

      contents = [] of String
      while item = actual.next
        contents << item.as(String)
      end

      contents.sort!.should eq(["bar", "foo"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "loads text from in-memory bytes and read_with_path uses <memory>" do
    bytes = [
      "foo".bytes.to_a,
      "bar".bytes.to_a,
    ]
    loader = Crig::Loaders::FileLoader(Array(UInt8)).from_bytes_multi(bytes)

    contents = [] of String
    loader.read.ignore_errors.each do |item|
      contents << item.as(String)
    end

    with_path = Crig::Loaders::FileLoader(Array(UInt8)).from_bytes_multi(bytes)
      .read_with_path
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, String)))

    contents.sort!.should eq(["bar", "foo"])
    with_path.map(&.[0]).uniq.should eq(["<memory>"])
    with_path.map(&.[1]).sort!.should eq(["bar", "foo"])
  end

  it "loads only direct files from a directory" do
    dir = File.join(Dir.tempdir, "crig-file-loader-dir-#{Random::Secure.hex(8)}")
    Dir.mkdir(dir)

    begin
      File.write(File.join(dir, "alpha.txt"), "alpha")
      Dir.mkdir(File.join(dir, "nested"))
      File.write(File.join(dir, "nested", "beta.txt"), "beta")

      loader = Crig::Loaders::FileLoader(String | Crig::Loaders::FileLoaderError).with_dir(dir)
      paths = loader.ignore_errors.to_a.map(&.as(String))

      paths.size.should eq(1)
      File.basename(paths.first).should eq("alpha.txt")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe Crig::Loaders::Epub::RawTextProcessor do
  it "returns the input text unchanged" do
    Crig::Loaders::Epub::RawTextProcessor.process("hello <b>world</b>").should eq("hello <b>world</b>")
  end
end

describe Crig::Loaders::Epub::StripXmlProcessor do
  it "strips XML tags and joins adjacent text nodes with spaces" do
    xml = "<chapter><p>Hello</p><p>world</p><![CDATA[!]]></chapter>"

    Crig::Loaders::Epub::StripXmlProcessor.process(xml).should eq("Helloworld!")
  end

  it "raises a wrapped XML processing error for malformed XML" do
    expect_raises(Crig::Loaders::Epub::XmlProcessingError, /XML parsing error:/) do
      Crig::Loaders::Epub::StripXmlProcessor.process("<chapter><p>oops</chapter>")
    end
  end
end

describe Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor) do
  it "loads epub files by chapter with errors preserved" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/tests/data/*.epub")
    actual = loader
      .load_with_path
      .ignore_errors
      .by_chapter
      .to_a
      .map(&.as(Tuple(String, Array(String | Crig::Loaders::Epub::EpubLoaderError))))

    actual.size.should eq(1)
    path, chapters = actual.first
    path.should eq("vendor/rig/tests/data/dummy.epub")
    chapters.size.should eq(3)
    chapters.all? { |chapter| chapter.is_a?(String) }.should be_true
  end

  it "reads a single epub file into concatenated content" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/tests/data/*.epub")
    actual = loader
      .read
      .ignore_errors
      .to_a

    actual.size.should eq(1)
    actual.first.should be_a(String)
  end

  it "reads a single epub file with its path" do
    loader = Crig::Loaders::Epub::EpubFileLoader(Crig::Loaders::Epub::PathResult, Crig::Loaders::Epub::RawTextProcessor)
      .with_glob("vendor/rig/tests/data/*.epub")
    actual = loader
      .read_with_path
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, String)))

    actual.size.should eq(1)
    actual.first[0].should eq("vendor/rig/tests/data/dummy.epub")
  end
end

describe Crig::Loaders::PdfFileLoader do
  it "loads pdf files by page with paths preserved" do
    loader = Crig::Loaders::PdfFileLoader(String | Crig::Loaders::PdfLoaderError)
      .with_glob("vendor/rig/tests/data/*.pdf")
    actual = loader
      .load_with_path
      .ignore_errors
      .by_page
      .ignore_errors
      .to_a
      .map(&.as(Tuple(String, Array(Tuple(Int32, String)))))

    actual.sort_by!(&.[0])
    actual.should eq([
      {
        "vendor/rig/tests/data/dummy.pdf",
        [{0, "Test\nPDF\nDocument\n"}],
      },
      {
        "vendor/rig/tests/data/file-id-verifiers.pdf",
        [{0, ""}, {1, ""}, {2, ""}],
      },
      {
        "vendor/rig/tests/data/pages.pdf",
        [
          {0, "Page\n1\n"},
          {1, "Page\n2\n"},
          {2, "Page\n3\n"},
        ],
      },
    ])
  end

  it "loads pdf content from in-memory bytes by page" do
    dummy_bytes = File.read("vendor/rig/tests/data/dummy.pdf").to_slice.to_a
    pages_bytes = File.read("vendor/rig/tests/data/pages.pdf").to_slice.to_a

    actual = Crig::Loaders::PdfFileLoader(Array(UInt8))
      .from_bytes_multi([dummy_bytes, pages_bytes])
      .load
      .ignore_errors
      .by_page
      .ignore_errors
      .to_a

    actual.should eq([
      "Test\nPDF\nDocument\n",
      "Page\n1\n",
      "Page\n2\n",
      "Page\n3\n",
    ])
  end
end
