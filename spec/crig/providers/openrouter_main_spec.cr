require "../../spec_helper"
describe Crig::Providers::OpenRouter::Client do
  it "supports rust-shaped client initialization" do
    client = Crig::Providers::OpenRouter::Client.new("dummy-key")
    builder_client = Crig::Providers::OpenRouter::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
  end
end

describe Crig::Providers::OpenRouter::ProviderPreferences do
  it "matches the routing builder helpers and provider wrapper payload" do
    prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order(["anthropic", "openai"])
      .only(["anthropic", "openai", "google"])
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
      .data_collection(Crig::Providers::OpenRouter::DataCollection::Deny)
      .zdr(true)
      .quantizations([
        Crig::Providers::OpenRouter::Quantization::Int8,
      ])
      .allow_fallbacks(false)

    provider = prefs.to_json_value["provider"]
    provider["order"].as_a.map(&.as_s).should eq(["anthropic", "openai"])
    provider["only"].as_a.map(&.as_s).should eq(["anthropic", "openai", "google"])
    provider["sort"].as_s.should eq("throughput")
    provider["data_collection"].as_s.should eq("deny")
    provider["zdr"].as_bool.should be_true
    provider["quantizations"].as_a.map(&.as_s).should eq(["int8"])
    provider["allow_fallbacks"].as_bool.should be_false
  end

  it "supports convenience methods and percentile thresholds" do
    prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
      .zero_data_retention
      .fastest
      .preferred_min_throughput(
        Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
          Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
        )
      )

    prefs.zdr.should eq(true)
    prefs.sort.not_nil!.kind.simple?.should be_true
    prefs.sort.not_nil!.strategy.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    prefs.to_json_value["provider"]["preferred_min_throughput"]["p90"].as_f.should eq(50.0)
  end

  it "matches the rust serialization and deserialization helper coverage" do
    Crig::Providers::OpenRouter::DataCollection::Allow.to_wire.should eq("allow")
    Crig::Providers::OpenRouter::DataCollection::Deny.to_wire.should eq("deny")
    Crig::Providers::OpenRouter::DataCollection.default.should eq(Crig::Providers::OpenRouter::DataCollection::Allow)

    Crig::Providers::OpenRouter::Quantization::Int4.to_wire.should eq("int4")
    Crig::Providers::OpenRouter::Quantization::Int8.to_wire.should eq("int8")
    Crig::Providers::OpenRouter::Quantization::Fp16.to_wire.should eq("fp16")
    Crig::Providers::OpenRouter::Quantization::Bf16.to_wire.should eq("bf16")
    Crig::Providers::OpenRouter::Quantization::Fp32.to_wire.should eq("fp32")
    Crig::Providers::OpenRouter::Quantization::Fp8.to_wire.should eq("fp8")
    Crig::Providers::OpenRouter::Quantization::Unknown.to_wire.should eq("unknown")

    Crig::Providers::OpenRouter::ProviderSortStrategy::Price.to_wire.should eq("price")
    Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput.to_wire.should eq("throughput")
    Crig::Providers::OpenRouter::ProviderSortStrategy::Latency.to_wire.should eq("latency")
    Crig::Providers::OpenRouter::SortPartition::Model.to_wire.should eq("model")
    Crig::Providers::OpenRouter::SortPartition::None.to_wire.should eq("none")

    simple_sort = Crig::Providers::OpenRouter::ProviderSort.simple(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
    simple_sort.to_json_value.as_s.should eq("latency")

    complex_sort = Crig::Providers::OpenRouter::ProviderSort.complex(
      Crig::Providers::OpenRouter::ProviderSortConfig.new(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
        .partition(Crig::Providers::OpenRouter::SortPartition::None)
    )
    complex_sort.to_json_value["by"].as_s.should eq("price")
    complex_sort.to_json_value["partition"].as_s.should eq("none")

    partitionless = Crig::Providers::OpenRouter::ProviderSort.complex(
      Crig::Providers::OpenRouter::ProviderSortConfig.new(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    )
    partitionless.to_json_value["by"].as_s.should eq("throughput")
    partitionless.to_json_value["partition"]?.should be_nil

    thresholds = Crig::Providers::OpenRouter::PercentileThresholds.new
      .p50(10.0)
      .p75(25.0)
      .p90(50.0)
      .p99(100.0)
    thresholds.p50.should eq(10.0)
    thresholds.p75.should eq(25.0)
    thresholds.p90.should eq(50.0)
    thresholds.p99.should eq(100.0)
    Crig::Providers::OpenRouter::PercentileThresholds.new.p50.should be_nil

    throughput_simple = Crig::Providers::OpenRouter::ThroughputThreshold.simple(50.0)
    throughput_simple.to_json_value.as_f.should eq(50.0)
    throughput_percentile = Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
      Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
    )
    throughput_percentile.to_json_value["p90"].as_f.should eq(50.0)

    latency_simple = Crig::Providers::OpenRouter::LatencyThreshold.simple(0.5)
    latency_simple.to_json_value.as_f.should eq(0.5)
    latency_percentile = Crig::Providers::OpenRouter::LatencyThreshold.percentile(
      Crig::Providers::OpenRouter::PercentileThresholds.new.p50(0.1).p99(1.0)
    )
    latency_percentile.to_json_value["p50"].as_f.should eq(0.1)
    latency_percentile.to_json_value["p99"].as_f.should eq(1.0)

    price = Crig::Providers::OpenRouter::MaxPrice.new.prompt(0.001).completion(0.002)
    price.prompt.should eq(0.001)
    price.completion.should eq(0.002)
    price.request.should be_nil
    price.image.should be_nil
    full_price = price.request(0.01).image(0.05).to_json_value
    full_price["prompt"].as_f.should eq(0.001)
    full_price["completion"].as_f.should eq(0.002)
    full_price["request"].as_f.should eq(0.01)
    full_price["image"].as_f.should eq(0.05)
    Crig::Providers::OpenRouter::MaxPrice.new.prompt.should be_nil

    order_with_fallbacks = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order(["anthropic", "openai"])
      .allow_fallbacks(true)
      .to_json_value["provider"]
    order_with_fallbacks["order"].as_a.map(&.as_s).should eq(["anthropic", "openai"])
    order_with_fallbacks["allow_fallbacks"].as_bool.should be_true

    allowlist = Crig::Providers::OpenRouter::ProviderPreferences.new
      .only(["azure", "together"])
      .allow_fallbacks(false)
      .to_json_value["provider"]
    allowlist["only"].as_a.map(&.as_s).should eq(["azure", "together"])
    allowlist["allow_fallbacks"].as_bool.should be_false

    ignored = Crig::Providers::OpenRouter::ProviderPreferences.new.ignore(["deepinfra"]).to_json_value["provider"]
    ignored["ignore"].as_a.map(&.as_s).should eq(["deepinfra"])

    sorted_latency = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
      .to_json_value["provider"]
    sorted_latency["sort"].as_s.should eq("latency")

    sorted_price = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
      .preferred_min_throughput(
        Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
          Crig::Providers::OpenRouter::PercentileThresholds.new.p90(50.0)
        )
      )
      .to_json_value["provider"]
    sorted_price["sort"].as_s.should eq("price")
    sorted_price["preferred_min_throughput"]["p90"].as_f.should eq(50.0)

    require_params = Crig::Providers::OpenRouter::ProviderPreferences.new
      .require_parameters(true)
      .to_json_value["provider"]
    require_params["require_parameters"].as_bool.should be_true

    policy = Crig::Providers::OpenRouter::ProviderPreferences.new
      .data_collection(Crig::Providers::OpenRouter::DataCollection::Deny)
      .zdr(true)
      .to_json_value["provider"]
    policy["data_collection"].as_s.should eq("deny")
    policy["zdr"].as_bool.should be_true

    quantized = Crig::Providers::OpenRouter::ProviderPreferences.new
      .quantizations([Crig::Providers::OpenRouter::Quantization::Int8, Crig::Providers::OpenRouter::Quantization::Fp16])
      .to_json_value["provider"]
    quantized["quantizations"].as_a.map(&.as_s).should eq(["int8", "fp16"])

    default_prefs = Crig::Providers::OpenRouter::ProviderPreferences.new
    default_prefs.order.should be_nil
    default_prefs.only.should be_nil
    default_prefs.ignore.should be_nil
    default_prefs.allow_fallbacks.should be_nil
    default_prefs.require_parameters.should be_nil
    default_prefs.data_collection.should be_nil
    default_prefs.zdr.should be_nil
    default_prefs.sort.should be_nil
    default_prefs.preferred_min_throughput.should be_nil
    default_prefs.preferred_max_latency.should be_nil
    default_prefs.max_price.should be_nil
    default_prefs.quantizations.should be_nil

    serialized = Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
      .to_json_value["provider"]
    serialized["sort"].as_s.should eq("price")
    serialized["order"]?.should be_nil
    serialized["only"]?.should be_nil
    serialized["ignore"]?.should be_nil
    serialized["zdr"]?.should be_nil

    deserialized = Crig::Providers::OpenRouter::ProviderPreferences.from_json(%({
      "order":["anthropic","openai"],
      "sort":"throughput",
      "data_collection":"deny",
      "zdr":true,
      "quantizations":["int8","fp16"]
    }))
    deserialized.order.should eq(["anthropic", "openai"])
    deserialized.sort.not_nil!.kind.simple?.should be_true
    deserialized.sort.not_nil!.strategy.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
    deserialized.data_collection.should eq(Crig::Providers::OpenRouter::DataCollection::Deny)
    deserialized.zdr.should eq(true)
    deserialized.quantizations.should eq([
      Crig::Providers::OpenRouter::Quantization::Int8,
      Crig::Providers::OpenRouter::Quantization::Fp16,
    ])

    complex_deserialized = Crig::Providers::OpenRouter::ProviderPreferences.from_json(%({
      "sort":{"by":"latency","partition":"model"}
    }))
    complex_deserialized.sort.not_nil!.kind.complex?.should be_true
    complex_deserialized.sort.not_nil!.config.not_nil!.by.should eq(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
    complex_deserialized.sort.not_nil!.config.not_nil!.partition.should eq(Crig::Providers::OpenRouter::SortPartition::Model)

    max_price = Crig::Providers::OpenRouter::ProviderPreferences.new
      .max_price(Crig::Providers::OpenRouter::MaxPrice.new.prompt(0.001).completion(0.002))
      .to_json_value["provider"]
    max_price["max_price"]["prompt"].as_f.should eq(0.001)
    max_price["max_price"]["completion"].as_f.should eq(0.002)

    max_latency = Crig::Providers::OpenRouter::ProviderPreferences.new
      .preferred_max_latency(Crig::Providers::OpenRouter::LatencyThreshold.simple(0.5))
      .to_json_value["provider"]
    max_latency["preferred_max_latency"].as_f.should eq(0.5)

    empty_arrays = Crig::Providers::OpenRouter::ProviderPreferences.new
      .order([] of String)
      .quantizations([] of Crig::Providers::OpenRouter::Quantization)
      .to_json_value["provider"]
    empty_arrays["order"].as_a.should eq([] of JSON::Any)
    empty_arrays["quantizations"].as_a.should eq([] of JSON::Any)
  end
end

describe Crig::Providers::OpenRouter::UserContent do
  it "serializes and deserializes text, file, audio, and video payloads" do
    text = Crig::Providers::OpenRouter::UserContent.text("Hello, world!").to_json_value
    text["type"].as_s.should eq("text")
    text["text"].as_s.should eq("Hello, world!")

    file = Crig::Providers::OpenRouter::UserContent.file_base64("JVBERi0xLjQ=", "application/pdf", "report.pdf").to_json_value
    file["type"].as_s.should eq("file")
    file["file"]["file_data"].as_s.should eq("data:application/pdf;base64,JVBERi0xLjQ=")
    file["file"]["filename"].as_s.should eq("report.pdf")

    audio = Crig::Providers::OpenRouter::UserContent.audio_base64("SGVsbG8=", Crig::Completion::AudioMediaType::WAV).to_json_value
    audio["type"].as_s.should eq("input_audio")
    audio["input_audio"]["format"].as_s.should eq("wav")

    video = Crig::Providers::OpenRouter::UserContent.video_base64("SGVsbG8=", Crig::Completion::VideoMediaType::MP4).to_json_value
    video["type"].as_s.should eq("video_url")
    video["video_url"]["url"].as_s.should eq("data:video/mp4;base64,SGVsbG8=")

    parsed = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"image_url",
      "image_url":{"url":"https://example.com/image.png","detail":"high"}
    })))

    parsed.kind.image_url?.should be_true
    parsed.image_url.not_nil!.url.should eq("https://example.com/image.png")
    parsed.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::High)
  end

  it "converts core rig content and preserves provider-specific errors" do
    image = Crig::Completion::UserContent.image_base64("SGVsbG8=", Crig::Completion::ImageMediaType::JPEG, Crig::Completion::ImageDetail::Low)
    converted = Crig::Providers::OpenRouter::UserContent.from_core(image)
    converted.kind.image_url?.should be_true
    converted.image_url.not_nil!.url.should eq("data:image/jpeg;base64,SGVsbG8=")
    converted.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Low)

    audio = Crig::Completion::UserContent.audio_url("https://example.com/audio.wav", Crig::Completion::AudioMediaType::WAV)
    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(audio)
    end
  end

  it "matches the rust file and conversion coverage" do
    image_url = Crig::Providers::OpenRouter::UserContent.image_url("https://example.com/image.png").to_json_value
    image_url["type"].as_s.should eq("image_url")
    image_url["image_url"]["url"].as_s.should eq("https://example.com/image.png")
    image_url["image_url"]["detail"]?.should be_nil

    image_detail = Crig::Providers::OpenRouter::UserContent
      .image_url_with_detail("https://example.com/image.png", Crig::Completion::ImageDetail::High)
      .to_json_value
    image_detail["image_url"]["detail"].as_s.should eq("high")

    image_base64 = Crig::Providers::OpenRouter::UserContent
      .image_base64("SGVsbG8=", "image/png", Crig::Completion::ImageDetail::Low)
      .to_json_value
    image_base64["image_url"]["url"].as_s.should eq("data:image/png;base64,SGVsbG8=")
    image_base64["image_url"]["detail"].as_s.should eq("low")

    file_url = Crig::Providers::OpenRouter::UserContent
      .file_url("https://example.com/doc.pdf", "document.pdf")
      .to_json_value
    file_url["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")
    file_url["file"]["filename"].as_s.should eq("document.pdf")

    parsed_text = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({"type":"text","text":"Hello!"})))
    parsed_text.kind.text?.should be_true
    parsed_text.text.should eq("Hello!")

    parsed_file = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"file",
      "file":{"filename":"doc.pdf","file_data":"https://example.com/doc.pdf"}
    })))
    parsed_file.kind.file?.should be_true
    parsed_file.file.not_nil!.filename.should eq("doc.pdf")
    parsed_file.file.not_nil!.file_data.should eq("https://example.com/doc.pdf")

    parsed_video = Crig::Providers::OpenRouter::UserContent.from_json_value(JSON.parse(%({
      "type":"video_url",
      "video_url":{"url":"https://example.com/video.mp4"}
    })))
    parsed_video.kind.video_url?.should be_true
    parsed_video.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    from_text = Crig::Providers::OpenRouter::UserContent.from_string("Hello")
    from_text.kind.text?.should be_true
    from_text.text.should eq("Hello")

    Crig::Providers::OpenRouter::UserContent
      .from_core(Crig::Completion::UserContent.text("Hello"))
      .text.should eq("Hello")

    image = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.image_url("https://example.com/img.png", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::High)
    )
    image.kind.image_url?.should be_true
    image.image_url.not_nil!.url.should eq("https://example.com/img.png")
    image.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::High)

    image_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.image_base64("SGVsbG8=", Crig::Completion::ImageMediaType::JPEG, Crig::Completion::ImageDetail::Low)
    )
    image_b64.image_url.not_nil!.url.should eq("data:image/jpeg;base64,SGVsbG8=")
    image_b64.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Low)

    document_url = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.document_url("https://example.com/doc.pdf", Crig::Completion::DocumentMediaType::PDF)
    )
    document_url.kind.file?.should be_true
    document_url.file.not_nil!.file_data.should eq("https://example.com/doc.pdf")
    document_url.file.not_nil!.filename.should eq("document.pdf")

    document_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Document,
        document: Crig::Completion::Document.new(
          Crig::Completion::DocumentSourceKind.base64("JVBERi0xLjQ="),
          Crig::Completion::DocumentMediaType::PDF,
        ),
      )
    )
    document_b64.file.not_nil!.file_data.should eq("data:application/pdf;base64,JVBERi0xLjQ=")
    document_b64.file.not_nil!.filename.should eq("document.pdf")

    document_text = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.document("Plain text document content", Crig::Completion::DocumentMediaType::TXT)
    )
    document_text.kind.text?.should be_true
    document_text.text.should eq("Plain text document content")

    video_url = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          Crig::Completion::VideoMediaType::MP4,
        ),
      )
    )
    video_url.kind.video_url?.should be_true
    video_url.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    video_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
          Crig::Completion::VideoMediaType::MP4,
        ),
      )
    )
    video_b64.video_url.not_nil!.url.should eq("data:video/mp4;base64,SGVsbG8=")

    audio_b64 = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.audio("audiodata", Crig::Completion::AudioMediaType::MP3)
    )
    audio_b64.kind.input_audio?.should be_true
    audio_b64.input_audio.not_nil!.data.should eq("audiodata")
    audio_b64.input_audio.not_nil!.format.should eq("mp3")

    video_url_without_type = Crig::Providers::OpenRouter::UserContent.from_core(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          nil,
        ),
      )
    )
    video_url_without_type.kind.video_url?.should be_true
    video_url_without_type.video_url.not_nil!.url.should eq("https://example.com/video.mp4")

    openai_text = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.text("Hello")
    )
    openai_text.kind.text?.should be_true
    openai_text.text.should eq("Hello")

    openai_image = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/img.png", "auto")
    )
    openai_image.kind.image_url?.should be_true
    openai_image.image_url.not_nil!.url.should eq("https://example.com/img.png")
    openai_image.image_url.not_nil!.detail.should eq(Crig::Completion::ImageDetail::Auto)

    openai_audio = Crig::Providers::OpenRouter::UserContent.from_openai(
      Crig::Providers::OpenAI::Chat::UserContent.audio("audiodata", "flac")
    )
    openai_audio.kind.input_audio?.should be_true
    openai_audio.input_audio.not_nil!.data.should eq("audiodata")
    openai_audio.input_audio.not_nil!.format.should eq("flac")

    expect_raises(Crig::Completion::CompletionError, /media type required/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Image,
          image: Crig::Completion::Image.new(
            Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
            nil,
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Image,
          image: Crig::Completion::Image.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::ImageMediaType::PNG,
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /media type/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Video,
          video: Crig::Completion::Video.new(
            Crig::Completion::DocumentSourceKind.base64("SGVsbG8="),
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Video,
          video: Crig::Completion::Video.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::VideoMediaType::MP4,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /media type required/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Audio,
          audio: Crig::Completion::Audio.new(
            Crig::Completion::DocumentSourceKind.base64("audiodata"),
            nil,
          ),
        )
      )
    end

    expect_raises(Crig::Completion::CompletionError, /base64/) do
      Crig::Providers::OpenRouter::UserContent.from_core(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Audio,
          audio: Crig::Completion::Audio.new(
            Crig::Completion::DocumentSourceKind.raw(Bytes[1, 2, 3]),
            Crig::Completion::AudioMediaType::MP3,
          ),
        )
      )
    end
  end
end

describe Crig::Providers::OpenRouter::Message do
  it "serializes single-text user content as a plain string and mixed content as an array" do
    single = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).one(
        Crig::Providers::OpenRouter::UserContent.text("Hello")
      )
    ).to_json_value
    single["role"].as_s.should eq("user")
    single["content"].as_s.should eq("Hello")

    mixed = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).many([
        Crig::Providers::OpenRouter::UserContent.text("Check this image:"),
        Crig::Providers::OpenRouter::UserContent.image_url("https://example.com/img.png"),
      ])
    ).to_json_value
    mixed["content"].as_a.size.should eq(2)
    mixed["content"].as_a.first["type"].as_s.should eq("text")
    mixed["content"].as_a.last["type"].as_s.should eq("image_url")
  end

  it "emits reasoning details from assistant reasoning content" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.text("step", "sig_step"),
      Crig::Completion::ReasoningContent.summary("summary"),
      Crig::Completion::ReasoningContent.encrypted("enc_blob"),
    ], "rs_2")

    messages = Crig::Providers::OpenRouter::Message.from_core_message(
      Crig::Completion::Message.new(
        Crig::Completion::Message::Role::Assistant,
        Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
          Crig::Completion::AssistantContent.new(
            Crig::Completion::AssistantContent::Kind::Reasoning,
            reasoning: reasoning,
          )
        ),
      )
    )

    assistant = messages.first
    assistant.kind.assistant?.should be_true
    assistant.reasoning.should be_nil
    assistant.reasoning_details.size.should eq(3)
    assistant.reasoning_details.first.kind.text?.should be_true
    assistant.reasoning_details.first.id.should eq("rs_2")
  end

  it "matches the rust message conversion coverage for files and assistant defaults" do
    file_message = Crig::Providers::OpenRouter::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenRouter::UserContent).many([
        Crig::Providers::OpenRouter::UserContent.text("Analyze this PDF:"),
        Crig::Providers::OpenRouter::UserContent.file_url("https://example.com/doc.pdf", "document.pdf"),
      ])
    ).to_json_value
    file_message["role"].as_s.should eq("user")
    file_message["content"].as_a.size.should eq(2)
    file_message["content"][1]["type"].as_s.should eq("file")
    file_message["content"][1]["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")

    assistant = Crig::Providers::OpenRouter::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"Hello world",
      "refusal":null,
      "reasoning":null
    })))
    assistant.kind.assistant?.should be_true
    assistant.assistant_content.size.should eq(1)
    assistant.reasoning_details.should eq([] of Crig::Providers::OpenRouter::ReasoningDetails)

    pdf_message = Crig::Providers::OpenRouter::Message.from_core_message(
      Crig::Completion::Message.new(
        Crig::Completion::Message::Role::User,
        Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
          Crig::Completion::UserContent.text("Analyze this PDF:"),
          Crig::Completion::UserContent.document_url("https://example.com/doc.pdf", Crig::Completion::DocumentMediaType::PDF),
        ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
      )
    ).first
    pdf_json = pdf_message.to_json_value
    pdf_json["content"].as_a[1]["type"].as_s.should eq("file")
    pdf_json["content"].as_a[1]["file"]["file_data"].as_s.should eq("https://example.com/doc.pdf")

    openai_user = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).many([
        Crig::Providers::OpenAI::Chat::UserContent.text("Hello"),
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/img.png"),
      ])
    )
    converted_user = Crig::Providers::OpenRouter::Message.from_openai(openai_user)
    converted_user.kind.user?.should be_true
    converted_user.user_content.not_nil!.size.should eq(2)
  end
end

describe Crig::Providers::OpenRouter::CompletionResponse do
  it "maps reasoning details back into typed core reasoning content with index ordering" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_ordering",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_order","index":1,"summary":"second"},
            {"type":"reasoning.summary","id":"rs_order","index":0,"summary":"first"}
          ]
        }
      }]
    }))

    converted = response.to_completion_response
    reasoning = converted.choice.to_a.find(&.kind.reasoning?).not_nil!.reasoning.not_nil!
    reasoning.id.should eq("rs_order")
    reasoning.content.map(&.summary).compact.should eq(["first", "second"])
  end

  it "deserializes gemini flash responses" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"gen-AAAAAAAAAA-AAAAAAAAAAAAAAAAAAAA",
      "provider":"Google",
      "model":"google/gemini-2.5-flash",
      "object":"chat.completion",
      "created":1765971703,
      "choices":[{
        "finish_reason":"stop",
        "native_finish_reason":"STOP",
        "index":0,
        "message":{"role":"assistant","content":"CONTENT","refusal":null,"reasoning":null}
      }],
      "usage":{"prompt_tokens":669,"completion_tokens":5,"total_tokens":674}
    }))

    response.id.should eq("gen-AAAAAAAAAA-AAAAAAAAAAAAAAAAAAAA")
    response.model.should eq("google/gemini-2.5-flash")
    response.choices.size.should eq(1)
    response.choices.first.finish_reason.should eq("stop")
  end

  it "matches the rust reasoning detail conversion coverage" do
    response = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_123",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_1","summary":"s1"},
            {"type":"reasoning.text","id":"rs_1","text":"t1","signature":"sig_1"},
            {"type":"reasoning.encrypted","id":"rs_1","data":"enc_1"}
          ]
        }
      }]
    }))
    converted = response.to_completion_response
    reasoning = converted.choice.to_a.find(&.kind.reasoning?).not_nil!.reasoning.not_nil!
    reasoning.id.should eq("rs_1")
    reasoning.content.size.should eq(3)

    multi = Crig::Providers::OpenRouter::CompletionResponse.from_json(%({
      "id":"resp_multi",
      "object":"chat.completion",
      "created":1,
      "model":"openrouter/test-model",
      "choices":[{
        "index":0,
        "finish_reason":"stop",
        "message":{
          "role":"assistant",
          "content":"hello",
          "reasoning":null,
          "reasoning_details":[
            {"type":"reasoning.summary","id":"rs_1","summary":"one"},
            {"type":"reasoning.summary","id":"rs_2","summary":"two"}
          ]
        }
      }]
    })).to_completion_response
    reasoning_items = multi.choice.to_a.select(&.kind.reasoning?).map(&.reasoning.not_nil!)
    reasoning_items.map(&.id).should eq(["rs_1", "rs_2"])
    reasoning_items.map { |item| item.content.first.summary.not_nil! }.should eq(["one", "two"])
  end
end

describe Crig::Providers::OpenRouter::CompletionModel do
  it "uses the request model override when present and the default model when absent" do
    override_request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
      model: "google/gemini-2.5-flash",
    )
    default_request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
    )

    override_payload = Crig::Providers::OpenRouter::CompletionModel.build_request("openai/gpt-4o-mini", override_request, false).to_json_value
    default_payload = Crig::Providers::OpenRouter::CompletionModel.build_request("openai/gpt-4o-mini", default_request, false).to_json_value

    override_payload["model"].as_s.should eq("google/gemini-2.5-flash")
    default_payload["model"].as_s.should eq("openai/gpt-4o-mini")
  end

  it "serializes named tool-choice functions using the openrouter wire shape" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .tool_choice(Crig::Completion::ToolChoice.specific(["lookup_weather", "lookup_time"]))
      .build

    payload = Crig::Providers::OpenRouter::CompletionModel
      .build_request("openai/gpt-4o-mini", request, false)
      .to_json_value

    tool_choice = payload["tool_choice"].as_a
    tool_choice.size.should eq(2)
    tool_choice[0]["type"].as_s.should eq("function")
    tool_choice[0]["function"]["name"].as_s.should eq("lookup_weather")
    tool_choice[1]["function"]["name"].as_s.should eq("lookup_time")
  end

  it "posts chat completions requests and returns converted assistant content" do
    server = FakeOpenRouterChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_123",
          "object":"chat.completion",
          "created":1,
          "model":"openrouter/test-model",
          "choices":[{
            "index":0,
            "finish_reason":"stop",
            "message":{"role":"assistant","content":"hello","reasoning":null}
          }],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = client.completion_model(Crig::Providers::OpenRouter::CLAUDE_3_7_SONNET)
    response = model.completion(
      model.completion_request("Hello").build
    )

    response.choice.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(3)
    server.requests.first["model"].as_s.should eq(Crig::Providers::OpenRouter::CLAUDE_3_7_SONNET)

    http_server.close
  end

  it "parses streaming text, reasoning, and tool call deltas" do
    server = FakeOpenRouterChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"gen-1","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"search","arguments":""}}]}}]}

data: {"id":"gen-2","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}],"reasoning":"step"}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}

data: {"id":"gen-3","model":"openrouter/test-model","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"Rust\\"}"}}],"content":"done"},"finish_reason":"tool_calls"}]}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    response = client.completion_model(Crig::Providers::OpenRouter::QWEN_QWQ_32B).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Search").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::OpenRouter::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "step" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "done" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "search" }.should be_true
    items.last.kind.final?.should be_true
    response.message_id.should eq("gen-1")

    http_server.close
  end
end

describe Crig::Providers::OpenRouter::EmbeddingModel do
  it "posts embeddings requests with dimensions, encoding format, and user" do
    server = FakeOpenRouterEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],
          "model":"openrouter/embed",
          "usage":{"prompt_tokens":2,"completion_tokens":0,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = Crig::Providers::OpenRouter::EmbeddingModel
      .with_encoding_format(client, "openrouter/embed", 2, Crig::Providers::OpenRouter::EncodingFormat::Float)
      .user("user-1")

    embeddings = model.embed_texts(["hello"])

    embeddings.first.document.should eq("hello")
    embeddings.first.vec.should eq([0.1, 0.2])
    posted = server.requests.first
    posted["model"].as_s.should eq("openrouter/embed")
    posted["dimensions"].as_i.should eq(2)
    posted["encoding_format"].as_s.should eq("float")
    posted["user"].as_s.should eq("user-1")

    http_server.close
  end

  it "surfaces provider-reported usage from embed_texts_with_usage" do
    server = FakeOpenRouterEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1],"index":0}],
          "model":"openrouter/embed",
          "usage":{"prompt_tokens":2,"completion_tokens":0,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = Crig::Providers::OpenRouter::EmbeddingModel.new(client, "openrouter/embed", 0)

    response = model.embed_texts_with_usage(["hello"])

    response.embeddings.size.should eq(1)
    response.usage.total_tokens.should eq(2)
    response.usage.input_tokens.should eq(2)

    http_server.close
  end

  it "returns zero usage when the provider omits it" do
    server = FakeOpenRouterEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1],"index":0}],
          "model":"openrouter/embed"
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenRouter::Client.new("test-key", "http://127.0.0.1:#{address.port}/api/v1")
    model = Crig::Providers::OpenRouter::EmbeddingModel.new(client, "openrouter/embed", 0)

    response = model.embed_texts_with_usage(["hello"])

    response.usage.total_tokens.should eq(0)

    http_server.close
  end
end

describe Crig::Providers::OpenRouter::StreamingCompletionChunk do
  it "deserializes streaming chunks, tool call deltas, and usage" do
    chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-abc123",
      "choices":[{
        "index":0,
        "delta":{
          "role":"assistant",
          "tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":"{\\"location\\":"}}]
        }
      }],
      "model":"gpt-4",
      "usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}
    })))

    chunk.id.should eq("gen-abc123")
    chunk.choices.first.delta.tool_calls.first.id.should eq("call_abc")
    chunk.usage.not_nil!.total_tokens.should eq(150)
    Crig::Providers::OpenRouter::FinishReason.from_string("tool_calls").tool_calls?.should be_true
  end

  it "matches the rust multiple tool-call delta and error parsing coverage" do
    start_chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-1",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_123","type":"function","function":{"name":"search","arguments":""}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))
    delta1 = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-2",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))
    delta2 = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"gen-3",
      "choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"Rust programming\\"}"}}]}}],
      "created":1234567890,
      "model":"gpt-4",
      "object":"chat.completion.chunk"
    })))

    start_chunk.choices.first.delta.tool_calls.first.id.should eq("call_123")
    delta1.choices.first.delta.tool_calls.first.function.arguments.should eq(%({"query":))
    delta2.choices.first.delta.tool_calls.first.function.arguments.should eq(%("Rust programming"}))

    error_chunk = Crig::Providers::OpenRouter::StreamingCompletionChunk.from_json_value(JSON.parse(%({
      "id":"cmpl-abc123",
      "object":"chat.completion.chunk",
      "created":1234567890,
      "model":"gpt-3.5-turbo",
      "provider":"openai",
      "error":{"code":500,"message":"Provider disconnected"},
      "choices":[{"index":0,"delta":{"content":""},"finish_reason":"error"}]
    })))
    error_chunk.error.not_nil!.code.should eq(500)
    error_chunk.error.not_nil!.message.should eq("Provider disconnected")
  end
end
