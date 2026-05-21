module Crig
  module Providers
    module OpenRouter
      QWEN_QWQ_32B         = "qwen/qwq-32b"
      CLAUDE_3_7_SONNET    = "anthropic/claude-3.7-sonnet"
      PERPLEXITY_SONAR_PRO = "perplexity/sonar-pro"
      GEMINI_FLASH_2_0     = "google/gemini-2.0-flash-001"

      enum DataCollection
        Allow
        Deny

        def self.default : self
          Allow
        end

        def to_wire : String
          to_s.downcase
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      enum Quantization
        Int4
        Int8
        Fp16
        Bf16
        Fp32
        Fp8
        Unknown

        def to_wire : String
          case self
          in .int4?    then "int4"
          in .int8?    then "int8"
          in .fp16?    then "fp16"
          in .bf16?    then "bf16"
          in .fp32?    then "fp32"
          in .fp8?     then "fp8"
          in .unknown? then "unknown"
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      enum ProviderSortStrategy
        Price
        Throughput
        Latency

        def to_wire : String
          to_s.downcase
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      enum SortPartition
        Model
        None

        def to_wire : String
          to_s.downcase
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      struct ProviderSortConfig
        getter by : ProviderSortStrategy
        getter partition : SortPartition?

        def initialize(@by : ProviderSortStrategy, @partition : SortPartition? = nil)
        end

        def partition(partition : SortPartition) : self
          self.class.new(@by, partition)
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "by", @by.to_wire
              if partition = @partition
                json.field "partition", partition.to_wire
              end
            end
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            ProviderSortStrategy.from_json_value(hash["by"]),
            hash["partition"]?.try { |entry| SortPartition.from_json_value(entry) },
          )
        end
      end

      struct ProviderSort
        enum Kind
          Simple
          Complex
        end

        getter kind : Kind
        getter strategy : ProviderSortStrategy?
        getter config : ProviderSortConfig?

        def initialize(@kind : Kind, @strategy : ProviderSortStrategy? = nil, @config : ProviderSortConfig? = nil)
        end

        def self.simple(strategy : ProviderSortStrategy) : self
          new(Kind::Simple, strategy: strategy)
        end

        def self.complex(config : ProviderSortConfig) : self
          new(Kind::Complex, config: config)
        end

        def self.from_json_value(value : JSON::Any) : self
          if strategy = value.as_s?
            simple(ProviderSortStrategy.parse(strategy))
          else
            complex(
              ProviderSortConfig.new(
                ProviderSortStrategy.parse(value["by"].as_s),
                value["partition"]?.try(&.as_s?).try { |entry| SortPartition.parse(entry) },
              )
            )
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .simple?
            JSON::Any.new((@strategy || raise "Missing provider sort strategy").to_wire)
          in .complex?
            (@config || raise "Missing provider sort config").to_json_value
          end
        end
      end

      struct PercentileThresholds
        getter p50 : Float64?
        getter p75 : Float64?
        getter p90 : Float64?
        getter p99 : Float64?

        def initialize(@p50 : Float64? = nil, @p75 : Float64? = nil, @p90 : Float64? = nil, @p99 : Float64? = nil)
        end

        def p50(value : Float64) : self
          self.class.new(value, @p75, @p90, @p99)
        end

        def p75(value : Float64) : self
          self.class.new(@p50, value, @p90, @p99)
        end

        def p90(value : Float64) : self
          self.class.new(@p50, @p75, value, @p99)
        end

        def p99(value : Float64) : self
          self.class.new(@p50, @p75, @p90, value)
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "p50", @p50 if @p50
              json.field "p75", @p75 if @p75
              json.field "p90", @p90 if @p90
              json.field "p99", @p99 if @p99
            end
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["p50"]?.try { |entry| json_number?(entry) },
            hash["p75"]?.try { |entry| json_number?(entry) },
            hash["p90"]?.try { |entry| json_number?(entry) },
            hash["p99"]?.try { |entry| json_number?(entry) },
          )
        end

        def self.json_number?(value : JSON::Any) : Float64?
          value.as_f? || value.as_i?.try(&.to_f)
        end
      end

      struct ThroughputThreshold
        enum Kind
          Simple
          Percentile
        end

        getter kind : Kind
        getter value : Float64?
        getter percentiles : PercentileThresholds?

        def initialize(@kind : Kind, @value : Float64? = nil, @percentiles : PercentileThresholds? = nil)
        end

        def self.simple(value : Float64) : self
          new(Kind::Simple, value: value)
        end

        def self.percentile(percentiles : PercentileThresholds) : self
          new(Kind::Percentile, percentiles: percentiles)
        end

        def to_json_value : JSON::Any
          @kind.simple? ? JSON::Any.new(@value || 0.0) : (@percentiles || PercentileThresholds.new).to_json_value
        end

        def self.from_json_value(value : JSON::Any) : self
          if simple = value.as_f?
            simple(simple)
          elsif integer = value.as_i?
            simple(integer.to_f)
          else
            percentile(PercentileThresholds.from_json_value(value))
          end
        end
      end

      struct LatencyThreshold
        enum Kind
          Simple
          Percentile
        end

        getter kind : Kind
        getter value : Float64?
        getter percentiles : PercentileThresholds?

        def initialize(@kind : Kind, @value : Float64? = nil, @percentiles : PercentileThresholds? = nil)
        end

        def self.simple(value : Float64) : self
          new(Kind::Simple, value: value)
        end

        def self.percentile(percentiles : PercentileThresholds) : self
          new(Kind::Percentile, percentiles: percentiles)
        end

        def to_json_value : JSON::Any
          @kind.simple? ? JSON::Any.new(@value || 0.0) : (@percentiles || PercentileThresholds.new).to_json_value
        end

        def self.from_json_value(value : JSON::Any) : self
          if simple = value.as_f?
            simple(simple)
          elsif integer = value.as_i?
            simple(integer.to_f)
          else
            percentile(PercentileThresholds.from_json_value(value))
          end
        end
      end

      struct MaxPrice
        getter prompt : Float64?
        getter completion : Float64?
        getter request : Float64?
        getter image : Float64?

        def initialize(@prompt : Float64? = nil, @completion : Float64? = nil, @request : Float64? = nil, @image : Float64? = nil)
        end

        def prompt(price : Float64) : self
          self.class.new(price, @completion, @request, @image)
        end

        def completion(price : Float64) : self
          self.class.new(@prompt, price, @request, @image)
        end

        def request(price : Float64) : self
          self.class.new(@prompt, @completion, price, @image)
        end

        def image(price : Float64) : self
          self.class.new(@prompt, @completion, @request, price)
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "prompt", @prompt if @prompt
              json.field "completion", @completion if @completion
              json.field "request", @request if @request
              json.field "image", @image if @image
            end
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["prompt"]?.try { |entry| PercentileThresholds.json_number?(entry) },
            hash["completion"]?.try { |entry| PercentileThresholds.json_number?(entry) },
            hash["request"]?.try { |entry| PercentileThresholds.json_number?(entry) },
            hash["image"]?.try { |entry| PercentileThresholds.json_number?(entry) },
          )
        end
      end

      struct ProviderPreferences
        getter order : Array(String)?
        getter only : Array(String)?
        getter ignore : Array(String)?
        getter allow_fallbacks : Bool?
        getter require_parameters : Bool?
        getter data_collection : DataCollection?
        getter zdr : Bool?
        getter sort : ProviderSort?
        getter preferred_min_throughput : ThroughputThreshold?
        getter preferred_max_latency : LatencyThreshold?
        getter max_price : MaxPrice?
        getter quantizations : Array(Quantization)?

        def initialize(
          @order : Array(String)? = nil,
          @only : Array(String)? = nil,
          @ignore : Array(String)? = nil,
          @allow_fallbacks : Bool? = nil,
          @require_parameters : Bool? = nil,
          @data_collection : DataCollection? = nil,
          @zdr : Bool? = nil,
          @sort : ProviderSort? = nil,
          @preferred_min_throughput : ThroughputThreshold? = nil,
          @preferred_max_latency : LatencyThreshold? = nil,
          @max_price : MaxPrice? = nil,
          @quantizations : Array(Quantization)? = nil,
        )
        end

        def order(providers : Enumerable(String)) : self
          self.class.new(providers.to_a, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def only(providers : Enumerable(String)) : self
          self.class.new(@order, providers.to_a, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def ignore(providers : Enumerable(String)) : self
          self.class.new(@order, @only, providers.to_a, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def allow_fallbacks(allow : Bool) : self
          self.class.new(@order, @only, @ignore, allow, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def require_parameters(required : Bool) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, required, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def data_collection(policy : DataCollection) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, policy, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def zdr(enable : Bool) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, enable, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def sort(sort : ProviderSortStrategy | ProviderSortConfig | ProviderSort) : self
          value = case sort
                  in ProviderSortStrategy then ProviderSort.simple(sort)
                  in ProviderSortConfig   then ProviderSort.complex(sort)
                  in ProviderSort         then sort
                  end
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, value, @preferred_min_throughput, @preferred_max_latency, @max_price, @quantizations)
        end

        def preferred_min_throughput(threshold : ThroughputThreshold) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, threshold, @preferred_max_latency, @max_price, @quantizations)
        end

        def preferred_max_latency(threshold : LatencyThreshold) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, threshold, @max_price, @quantizations)
        end

        def max_price(price : MaxPrice) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, price, @quantizations)
        end

        def quantizations(values : Enumerable(Quantization)) : self
          self.class.new(@order, @only, @ignore, @allow_fallbacks, @require_parameters, @data_collection, @zdr, @sort, @preferred_min_throughput, @preferred_max_latency, @max_price, values.to_a)
        end

        def zero_data_retention : self
          zdr(true)
        end

        def fastest : self
          sort(ProviderSortStrategy::Throughput)
        end

        def cheapest : self
          sort(ProviderSortStrategy::Price)
        end

        def lowest_latency : self
          sort(ProviderSortStrategy::Latency)
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def to_json_value : JSON::Any
          provider = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "order" { json.array { @order.try(&.each { |value| json.string(value) }) } } if @order
              json.field "only" { json.array { @only.try(&.each { |value| json.string(value) }) } } if @only
              json.field "ignore" { json.array { @ignore.try(&.each { |value| json.string(value) }) } } if @ignore
              json.field "allow_fallbacks", @allow_fallbacks unless @allow_fallbacks.nil?
              json.field "require_parameters", @require_parameters unless @require_parameters.nil?
              if data_collection = @data_collection
                json.field "data_collection", data_collection.to_wire
              end
              json.field "zdr", @zdr unless @zdr.nil?
              if sort = @sort
                json.field "sort" { sort.to_json_value.to_json(json) }
              end
              if threshold = @preferred_min_throughput
                json.field "preferred_min_throughput" { threshold.to_json_value.to_json(json) }
              end
              if threshold = @preferred_max_latency
                json.field "preferred_max_latency" { threshold.to_json_value.to_json(json) }
              end
              if max_price = @max_price
                json.field "max_price" { max_price.to_json_value.to_json(json) }
              end
              if quantizations = @quantizations
                json.field "quantizations" do
                  json.array { quantizations.each { |value| json.string(value.to_wire) } }
                end
              end
            end
          end

          JSON.parse(%({"provider":#{provider.to_json}}))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["order"]?.try(&.as_a.map(&.as_s)),
            hash["only"]?.try(&.as_a.map(&.as_s)),
            hash["ignore"]?.try(&.as_a.map(&.as_s)),
            hash["allow_fallbacks"]?.try(&.as_bool),
            hash["require_parameters"]?.try(&.as_bool),
            hash["data_collection"]?.try { |entry| DataCollection.from_json_value(entry) },
            hash["zdr"]?.try(&.as_bool),
            hash["sort"]?.try { |entry| ProviderSort.from_json_value(entry) },
            hash["preferred_min_throughput"]?.try { |entry| ThroughputThreshold.from_json_value(entry) },
            hash["preferred_max_latency"]?.try { |entry| LatencyThreshold.from_json_value(entry) },
            hash["max_price"]?.try { |entry| MaxPrice.from_json_value(entry) },
            hash["quantizations"]?.try(&.as_a.map { |entry| Quantization.from_json_value(entry) }),
          )
        end

        def self.from_json(value : String) : self
          from_json_value(JSON.parse(value))
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end

      struct ImageUrl
        include JSON::Serializable

        getter url : String
        getter detail : Crig::Completion::ImageDetail?

        def initialize(@url : String, @detail : Crig::Completion::ImageDetail? = nil)
        end
      end

      struct VideoUrlContent
        include JSON::Serializable

        getter url : String

        def initialize(@url : String)
        end
      end

      struct FileContent
        include JSON::Serializable

        getter filename : String?
        @[JSON::Field(key: "file_data")]
        getter file_data : String?

        def initialize(@filename : String? = nil, @file_data : String? = nil)
        end
      end

      struct UserContent
        enum Kind
          Text
          ImageUrl
          File
          InputAudio
          VideoUrl
        end

        getter kind : Kind
        getter text : String?
        getter image_url : ImageUrl?
        getter file : FileContent?
        getter input_audio : Crig::Providers::OpenAI::Chat::InputAudio?
        getter video_url : VideoUrlContent?

        def initialize(
          @kind : Kind,
          @text : String? = nil,
          @image_url : ImageUrl? = nil,
          @file : FileContent? = nil,
          @input_audio : Crig::Providers::OpenAI::Chat::InputAudio? = nil,
          @video_url : VideoUrlContent? = nil,
        )
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.image_url(url : String) : self
          new(Kind::ImageUrl, image_url: ImageUrl.new(url))
        end

        def self.image_url_with_detail(url : String, detail : Crig::Completion::ImageDetail) : self
          new(Kind::ImageUrl, image_url: ImageUrl.new(url, detail))
        end

        def self.image_base64(data : String, mime_type : String, detail : Crig::Completion::ImageDetail? = nil) : self
          image_url = ImageUrl.new("data:#{mime_type};base64,#{data}", detail)
          new(Kind::ImageUrl, image_url: image_url)
        end

        def self.file_url(url : String, filename : String? = nil) : self
          new(Kind::File, file: FileContent.new(filename, url))
        end

        def self.file_base64(data : String, mime_type : String, filename : String? = nil) : self
          new(Kind::File, file: FileContent.new(filename, "data:#{mime_type};base64,#{data}"))
        end

        def self.audio_base64(data : String, format : Crig::Completion::AudioMediaType) : self
          new(Kind::InputAudio, input_audio: Crig::Providers::OpenAI::Chat::InputAudio.new(data, format.to_s.downcase))
        end

        def self.video_url(url : String) : self
          new(Kind::VideoUrl, video_url: VideoUrlContent.new(url))
        end

        def self.video_base64(data : String, media_type : Crig::Completion::VideoMediaType) : self
          new(Kind::VideoUrl, video_url: VideoUrlContent.new("data:#{Crig::Completion::MimeType.video_to_mime_type(media_type)};base64,#{data}"))
        end

        def self.from_string(text : String) : self
          self.text(text)
        end

        def self.from_openai(value : Crig::Providers::OpenAI::Chat::UserContent) : self
          case value.kind
          in .text?
            text(value.text || "")
          in .image?
            image = value.image_url || raise Crig::Completion::CompletionError.new("Missing OpenAI image URL content")
            new(Kind::ImageUrl, image_url: ImageUrl.new(image.url, Crig::Completion::ImageDetail.parse?(image.detail)))
          in .audio?
            audio = value.input_audio || raise Crig::Completion::CompletionError.new("Missing OpenAI input audio content")
            new(Kind::InputAudio, input_audio: audio)
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "text"
            text(hash["text"].as_s)
          when "image_url"
            new(Kind::ImageUrl, image_url: ImageUrl.from_json(hash["image_url"].to_json))
          when "file"
            new(Kind::File, file: FileContent.from_json(hash["file"].to_json))
          when "input_audio"
            new(Kind::InputAudio, input_audio: Crig::Providers::OpenAI::Chat::InputAudio.from_json(hash["input_audio"].to_json))
          when "video_url"
            new(Kind::VideoUrl, video_url: VideoUrlContent.from_json(hash["video_url"].to_json))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenRouter user content type: #{hash["type"].as_s}")
          end
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def self.from_core(value : Crig::Completion::UserContent) : self
          case value.kind
          in .text?
            text(value.text.try(&.text) || "")
          in .image?
            image = value.image || raise Crig::Completion::CompletionError.new("Missing image content")
            url = case image.data.kind
                  in .url?
                    image.data.string_value || raise Crig::Completion::CompletionError.new("Image URL content is missing")
                  in .base64?
                    media_type = image.media_type || raise Crig::Completion::CompletionError.new("Image media type required for base64 encoding")
                    "data:#{Crig::Completion::MimeType.image_to_mime_type(media_type)};base64,#{image.data.string_value}"
                  in .raw?
                    raise Crig::Completion::CompletionError.new("Raw bytes not supported, encode as base64 first")
                  in .string?
                    raise Crig::Completion::CompletionError.new("String source not supported for images")
                  in .file_id?
                    raise Crig::Completion::CompletionError.new("File ID source not supported for images, use URL or base64")
                  in .unknown?
                    raise Crig::Completion::CompletionError.new("Image has no data")
                  end
            new(Kind::ImageUrl, image_url: ImageUrl.new(url, image.detail))
          in .document?
            document = value.document || raise Crig::Completion::CompletionError.new("Missing document content")
            case document.data.kind
            in .url?
              filename = default_document_filename(document.media_type)
              new(Kind::File, file: FileContent.new(filename, document.data.string_value))
            in .base64?
              mime_type = if media_type = document.media_type
                            Crig::Completion::MimeType.document_to_mime_type(media_type)
                          else
                            "application/pdf"
                          end
              filename = default_document_filename(document.media_type)
              new(Kind::File, file: FileContent.new(filename, "data:#{mime_type};base64,#{document.data.string_value}"))
            in .string?
              text(document.data.string_value || "")
            in .raw?
              raise Crig::Completion::CompletionError.new("Raw bytes not supported for documents, encode as base64 first")
            in .file_id?
              raise Crig::Completion::CompletionError.new("File ID source not supported for documents, use URL or base64")
            in .unknown?
              raise Crig::Completion::CompletionError.new("Document has no data")
            end
          in .audio?
            audio = value.audio || raise Crig::Completion::CompletionError.new("Missing audio content")
            case audio.data.kind
            in .base64?
              format = audio.media_type || raise Crig::Completion::CompletionError.new("Audio media type required for base64 encoding")
              audio_base64(audio.data.string_value || "", format)
            in .url?
              raise Crig::Completion::CompletionError.new("OpenRouter does not support audio URLs, encode as base64 first")
            in .raw?
              raise Crig::Completion::CompletionError.new("Raw bytes not supported for audio, encode as base64 first")
            in .string?
              raise Crig::Completion::CompletionError.new("String source not supported for audio")
            in .file_id?
              raise Crig::Completion::CompletionError.new("File ID source not supported for audio, use URL or base64")
            in .unknown?
              raise Crig::Completion::CompletionError.new("Audio has no data")
            end
          in .video?
            video = value.video || raise Crig::Completion::CompletionError.new("Missing video content")
            url = case video.data.kind
                  in .url?
                    video.data.string_value || raise Crig::Completion::CompletionError.new("Video URL content is missing")
                  in .base64?
                    media_type = video.media_type || raise Crig::Completion::CompletionError.new("Video media type required for base64 encoding")
                    "data:#{Crig::Completion::MimeType.video_to_mime_type(media_type)};base64,#{video.data.string_value}"
                  in .raw?
                    raise Crig::Completion::CompletionError.new("Raw bytes not supported for video, encode as base64 first")
                  in .string?
                    raise Crig::Completion::CompletionError.new("String source not supported for video")
                  in .file_id?
                    raise Crig::Completion::CompletionError.new("File ID source not supported for video, use URL or base64")
                  in .unknown?
                    raise Crig::Completion::CompletionError.new("Video has no data")
                  end
            new(Kind::VideoUrl, video_url: VideoUrlContent.new(url))
          in .tool_result?
            raise Crig::Completion::CompletionError.new("Tool results should be handled as separate messages")
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .text?
                json.field "type", "text"
                json.field "text", @text
              in .image_url?
                json.field "type", "image_url"
                json.field "image_url" { (@image_url || raise "Missing OpenRouter image").to_json(json) }
              in .file?
                json.field "type", "file"
                json.field "file" { (@file || raise "Missing OpenRouter file").to_json(json) }
              in .input_audio?
                json.field "type", "input_audio"
                json.field "input_audio" { (@input_audio || raise "Missing OpenRouter audio").to_json(json) }
              in .video_url?
                json.field "type", "video_url"
                json.field "video_url" { (@video_url || raise "Missing OpenRouter video").to_json(json) }
              end
            end
          end
        end

        private def self.default_document_filename(media_type : Crig::Completion::DocumentMediaType?) : String?
          return unless media_type
          if media_type.pdf?
            "document.pdf"
          elsif media_type.txt?
            "document.txt"
          elsif media_type.html?
            "document.html"
          elsif media_type.markdown?
            "document.md"
          elsif media_type.csv?
            "document.csv"
          elsif media_type.xml?
            "document.xml"
          else
            "document"
          end
        end
      end

      struct ReasoningDetails
        enum Kind
          Summary
          Encrypted
          Text
        end

        getter kind : Kind
        getter id : String?
        getter format : String?
        getter index : Int32?
        getter summary : String?
        getter data : String?
        getter text : String?
        getter signature : String?

        def initialize(
          @kind : Kind,
          @id : String? = nil,
          @format : String? = nil,
          @index : Int32? = nil,
          @summary : String? = nil,
          @data : String? = nil,
          @text : String? = nil,
          @signature : String? = nil,
        )
        end

        def self.summary(summary : String, id : String? = nil, format : String? = nil, index : Int32? = nil) : self
          new(Kind::Summary, id: id, format: format, index: index, summary: summary)
        end

        def self.encrypted(data : String, id : String? = nil, format : String? = nil, index : Int32? = nil) : self
          new(Kind::Encrypted, id: id, format: format, index: index, data: data)
        end

        def self.text(text : String?, signature : String? = nil, id : String? = nil, format : String? = nil, index : Int32? = nil) : self
          new(Kind::Text, id: id, format: format, index: index, text: text, signature: signature)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "reasoning.summary"
            summary(hash["summary"].as_s, hash["id"]?.try(&.as_s?), hash["format"]?.try(&.as_s?), hash["index"]?.try(&.as_i))
          when "reasoning.encrypted"
            encrypted(hash["data"].as_s, hash["id"]?.try(&.as_s?), hash["format"]?.try(&.as_s?), hash["index"]?.try(&.as_i))
          when "reasoning.text"
            text(hash["text"]?.try(&.as_s?), hash["signature"]?.try(&.as_s?), hash["id"]?.try(&.as_s?), hash["format"]?.try(&.as_s?), hash["index"]?.try(&.as_i))
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenRouter reasoning detail type: #{hash["type"].as_s}")
          end
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .summary?
                json.field "type", "reasoning.summary"
                json.field "summary", @summary
              in .encrypted?
                json.field "type", "reasoning.encrypted"
                json.field "data", @data
              in .text?
                json.field "type", "reasoning.text"
                json.field "text", @text unless @text.nil?
                json.field "signature", @signature unless @signature.nil?
              end
              json.field "id", @id unless @id.nil?
              json.field "format", @format unless @format.nil?
              json.field "index", @index unless @index.nil?
            end
          end
        end
      end

      struct Message
        enum Kind
          System
          User
          Assistant
          ToolResult
        end

        getter kind : Kind
        getter system_content : Crig::OneOrMany(Crig::Providers::OpenAI::Chat::SystemContent)?
        getter user_content : Crig::OneOrMany(UserContent)?
        getter assistant_content : Array(Crig::Providers::OpenAI::Chat::AssistantContent)
        getter refusal : String?
        getter audio : Crig::Providers::OpenAI::Chat::AudioAssistant?
        getter name : String?
        getter tool_calls : Array(Crig::Providers::OpenAI::Chat::ToolCall)
        getter reasoning : String?
        getter reasoning_details : Array(ReasoningDetails)
        getter tool_call_id : String?
        getter tool_result_content : String?

        def initialize(
          @kind : Kind,
          @system_content : Crig::OneOrMany(Crig::Providers::OpenAI::Chat::SystemContent)? = nil,
          @user_content : Crig::OneOrMany(UserContent)? = nil,
          @assistant_content : Array(Crig::Providers::OpenAI::Chat::AssistantContent) = [] of Crig::Providers::OpenAI::Chat::AssistantContent,
          @refusal : String? = nil,
          @audio : Crig::Providers::OpenAI::Chat::AudioAssistant? = nil,
          @name : String? = nil,
          @tool_calls : Array(Crig::Providers::OpenAI::Chat::ToolCall) = [] of Crig::Providers::OpenAI::Chat::ToolCall,
          @reasoning : String? = nil,
          @reasoning_details : Array(ReasoningDetails) = [] of ReasoningDetails,
          @tool_call_id : String? = nil,
          @tool_result_content : String? = nil,
        )
        end

        def self.system(content : String) : self
          new(Kind::System, system_content: Crig::OneOrMany(Crig::Providers::OpenAI::Chat::SystemContent).one(Crig::Providers::OpenAI::Chat::SystemContent.from_string(content)))
        end

        def self.user(content : Crig::OneOrMany(UserContent), name : String? = nil) : self
          new(Kind::User, user_content: content, name: name)
        end

        def self.assistant(
          content : Array(Crig::Providers::OpenAI::Chat::AssistantContent),
          tool_calls : Array(Crig::Providers::OpenAI::Chat::ToolCall) = [] of Crig::Providers::OpenAI::Chat::ToolCall,
          reasoning : String? = nil,
          reasoning_details : Array(ReasoningDetails) = [] of ReasoningDetails,
        ) : self
          new(Kind::Assistant, assistant_content: content, tool_calls: tool_calls, reasoning: reasoning, reasoning_details: reasoning_details)
        end

        def self.tool_result(tool_call_id : String, content : String) : self
          new(Kind::ToolResult, tool_call_id: tool_call_id, tool_result_content: content)
        end

        def self.from_openai(value : Crig::Providers::OpenAI::Chat::Message) : self
          case value.kind
          in .system?
            new(Kind::System, system_content: value.system_content, name: value.name)
          in .user?
            user_content = value.user_content.try do |content|
              Crig::OneOrMany(UserContent).many(content.to_a.map { |entry| UserContent.from_openai(entry) })
            end
            new(Kind::User, user_content: user_content, name: value.name)
          in .assistant?
            new(
              Kind::Assistant,
              assistant_content: value.assistant_content,
              refusal: value.refusal,
              audio: value.audio,
              name: value.name,
              tool_calls: value.tool_calls,
            )
          in .tool_result?
            tool_call_id = value.tool_call_id || raise Crig::Completion::CompletionError.new("Missing OpenAI tool_call_id")
            tool_result(tool_call_id, value.tool_result_content.try(&.as_text) || "")
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          role = hash["role"].as_s
          case role
          when "system", "developer"
            system_content = if text = hash["content"].as_s?
                               Crig::OneOrMany(Crig::Providers::OpenAI::Chat::SystemContent).one(Crig::Providers::OpenAI::Chat::SystemContent.from_string(text))
                             else
                               Crig::OneOrMany(Crig::Providers::OpenAI::Chat::SystemContent).many(hash["content"].as_a.map { |entry| Crig::Providers::OpenAI::Chat::SystemContent.from_json(entry.to_json) })
                             end
            new(Kind::System, system_content: system_content, name: hash["name"]?.try(&.as_s?))
          when "user"
            user_content = if text = hash["content"].as_s?
                             Crig::OneOrMany(UserContent).one(UserContent.from_string(text))
                           else
                             Crig::OneOrMany(UserContent).many(hash["content"].as_a.map { |entry| UserContent.from_json_value(entry) })
                           end
            new(Kind::User, user_content: user_content, name: hash["name"]?.try(&.as_s?))
          when "assistant"
            assistant_content = if content = hash["content"]?
                                  if text = content.as_s?
                                    [Crig::Providers::OpenAI::Chat::AssistantContent.text(text)]
                                  elsif content.raw.nil?
                                    [] of Crig::Providers::OpenAI::Chat::AssistantContent
                                  else
                                    parse_assistant_content(content)
                                  end
                                else
                                  [] of Crig::Providers::OpenAI::Chat::AssistantContent
                                end
            new(
              Kind::Assistant,
              assistant_content: assistant_content,
              refusal: hash["refusal"]?.try(&.as_s?),
              audio: hash["audio"]?.try(&.as_h?).try { |audio| Crig::Providers::OpenAI::Chat::AudioAssistant.from_json(audio.to_json) },
              name: hash["name"]?.try(&.as_s?),
              tool_calls: hash["tool_calls"]?.try(&.as_a?).try(&.map { |entry| parse_tool_call(entry) }) || [] of Crig::Providers::OpenAI::Chat::ToolCall,
              reasoning: hash["reasoning"]?.try(&.as_s?),
              reasoning_details: hash["reasoning_details"]?.try(&.as_a?).try(&.map { |entry| ReasoningDetails.from_json_value(entry) }) || [] of ReasoningDetails,
            )
          when "tool"
            tool_result(hash["tool_call_id"].as_s, hash["content"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported OpenRouter message role: #{role}")
          end
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          case message.role
          in .user?
            user_items = message.content.compact_map(&.as?(Crig::Completion::UserContent))
            tool_results = [] of self
            other_content = [] of UserContent

            user_items.each do |content|
              if content.kind.tool_result?
                tool_result = content.tool_result || raise Crig::Completion::CompletionError.new("Missing tool result content")
                tool_results << self.tool_result(
                  tool_result.id,
                  tool_result.content.to_a.map { |entry| entry.text.try(&.text) || "[Image content not supported in tool results]" }.join('\n')
                )
              else
                other_content << UserContent.from_core(content)
              end
            end

            return tool_results unless tool_results.empty?

            user_content = Crig::OneOrMany(UserContent).many(other_content)
            [user(user_content)]
          in .assistant?
            text_content = [] of Crig::Providers::OpenAI::Chat::AssistantContent
            tool_calls = [] of Crig::Providers::OpenAI::Chat::ToolCall
            reasoning = nil
            reasoning_details = [] of ReasoningDetails

            message.content.each do |entry|
              next unless assistant_content = entry.as?(Crig::Completion::AssistantContent)
              case assistant_content.kind
              in .text?
                text = assistant_content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
                text_content << Crig::Providers::OpenAI::Chat::AssistantContent.text(text.text)
              in .tool_call?
                tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool call content")
                if additional_params = tool_call.additional_params
                  detail = ReasoningDetails.from_json_value(additional_params)
                  if detail.kind.encrypted?
                    reasoning_details << detail
                  end
                elsif signature = tool_call.signature
                  reasoning_details << ReasoningDetails.encrypted(signature, tool_call.call_id)
                end
                tool_calls << Crig::Providers::OpenAI::Chat::ToolCall.new(
                  tool_call.id,
                  Crig::Providers::OpenAI::Chat::Function.new(tool_call.function.name, tool_call.function.arguments),
                )
              in .reasoning?
                reasoning_block = assistant_content.reasoning || raise Crig::Completion::CompletionError.new("Missing reasoning content")
                if reasoning_block.content.empty?
                  display = reasoning_block.display_text
                  reasoning = display unless display.empty?
                else
                  reasoning_block.content.each_with_index do |block, index|
                    case block.kind
                    in .text?
                      reasoning_details << ReasoningDetails.text(block.text, block.signature, reasoning_block.id, nil, index)
                    in .summary?
                      reasoning_details << ReasoningDetails.summary(block.summary || "", reasoning_block.id, nil, index)
                    in .encrypted?
                      reasoning_details << ReasoningDetails.encrypted(block.data || "", reasoning_block.id, nil, index)
                    in .redacted?
                      reasoning_details << ReasoningDetails.encrypted(block.data || "", reasoning_block.id, nil, index)
                    end
                  end
                end
              in .image?
                raise Crig::Completion::CompletionError.new("OpenRouter currently doesn't support images.")
              end
            end

            [assistant(text_content, tool_calls, reasoning, reasoning_details)]
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        # ameba:disable Metrics/CyclomaticComplexity
        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .system?
                json.field "role", "system"
                json.field "content" do
                  content = @system_content || raise "Missing OpenRouter system content"
                  if content.size == 1
                    json.string(content.first.text)
                  else
                    json.array { content.each(&.to_json(json)) }
                  end
                end
              in .user?
                json.field "role", "user"
                json.field "content" do
                  content = @user_content || raise "Missing OpenRouter user content"
                  if content.size == 1 && content.first.kind.text?
                    json.string(content.first.text || "")
                  else
                    json.array { content.each(&.to_json_value.to_json(json)) }
                  end
                end
              in .assistant?
                json.field "role", "assistant"
                content = @assistant_content
                if content.size == 1 && content.first.kind.text?
                  json.field "content", content.first.text
                else
                  json.field "content" do
                    json.array { content.each(&.to_json_value.to_json(json)) }
                  end
                end
                json.field "refusal", @refusal unless @refusal.nil?
                if audio = @audio
                  json.field "audio" { audio.to_json(json) }
                end
                unless @tool_calls.empty?
                  json.field "tool_calls" { json.array { @tool_calls.each(&.to_json_value.to_json(json)) } }
                end
                json.field "reasoning", @reasoning unless @reasoning.nil?
                unless @reasoning_details.empty?
                  json.field "reasoning_details" { json.array { @reasoning_details.each(&.to_json_value.to_json(json)) } }
                end
              in .tool_result?
                json.field "role", "tool"
                json.field "tool_call_id", @tool_call_id
                json.field "content", @tool_result_content
              end
              json.field "name", @name unless @name.nil?
            end
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        private def self.parse_assistant_content(value : JSON::Any?) : Array(Crig::Providers::OpenAI::Chat::AssistantContent)
          return [] of Crig::Providers::OpenAI::Chat::AssistantContent unless value
          return [] of Crig::Providers::OpenAI::Chat::AssistantContent if value.raw.nil?
          if text = value.as_s?
            [Crig::Providers::OpenAI::Chat::AssistantContent.text(text)]
          else
            value.as_a.map do |entry|
              hash = entry.as_h
              case hash["type"].as_s
              when "text"
                Crig::Providers::OpenAI::Chat::AssistantContent.text(hash["text"].as_s)
              when "refusal"
                Crig::Providers::OpenAI::Chat::AssistantContent.refusal(hash["refusal"].as_s)
              else
                raise Crig::Completion::CompletionError.new("Unsupported OpenRouter assistant content type: #{hash["type"].as_s}")
              end
            end
          end
        end

        private def self.parse_tool_call(value : JSON::Any) : Crig::Providers::OpenAI::Chat::ToolCall
          hash = value.as_h
          function = hash["function"]
          Crig::Providers::OpenAI::Chat::ToolCall.new(
            hash["id"].as_s,
            Crig::Providers::OpenAI::Chat::Function.new(
              function["name"].as_s,
              parse_json_or_string(function["arguments"].as_s),
            ),
          )
        end

        private def self.parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON::Any.new(value)
        end
      end

      struct Choice
        getter index : Int32
        getter native_finish_reason : String?
        getter message : Message
        getter finish_reason : String?

        def initialize(@index : Int32, @message : Message, @native_finish_reason : String? = nil, @finish_reason : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"].as_i,
            Message.from_json_value(hash["message"]),
            hash["native_finish_reason"]?.try(&.as_s?),
            hash["finish_reason"]?.try(&.as_s?),
          )
        end
      end

      struct CompletionResponse
        getter id : String
        getter object : String
        getter created : Int64
        getter model : String
        getter choices : Array(Choice)
        @[JSON::Field(key: "system_fingerprint")]
        getter system_fingerprint : String?
        getter usage : Usage?

        def initialize(
          @id : String,
          @object : String,
          @created : Int64,
          @model : String,
          @choices : Array(Choice),
          @system_fingerprint : String? = nil,
          @usage : Usage? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            hash["object"].as_s,
            hash["created"].as_i64,
            hash["model"].as_s,
            hash["choices"].as_a.map { |entry| Choice.from_json_value(entry) },
            hash["system_fingerprint"]?.try(&.as_s?),
            hash["usage"]?.try(&.as_h?).try { |usage| Usage.from_json(usage.to_json) },
          )
        end

        def self.from_json(value : String) : self
          from_json_value(JSON.parse(value))
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def to_completion_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          message = choice.message
          unless message.kind.assistant?
            raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call")
          end

          content = message.assistant_content.map(&.to_completion_content)
          message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(
              call.id,
              call.function.name,
              call.function.arguments,
            )
          end

          grouped = {} of String? => Array({Int32, Int32, Crig::Completion::ReasoningContent})
          order = [] of String?
          message.reasoning_details.each_with_index do |detail, position|
            parsed = case detail.kind
                     in .summary?
                       Crig::Completion::ReasoningContent.summary(detail.summary || "")
                     in .encrypted?
                       Crig::Completion::ReasoningContent.encrypted(detail.data || "")
                     in .text?
                       text = detail.text
                       next unless text
                       Crig::Completion::ReasoningContent.text(text, detail.signature)
                     end
            unless grouped.has_key?(detail.id)
              order << detail.id
            end
            grouped[detail.id] ||= [] of {Int32, Int32, Crig::Completion::ReasoningContent}
            grouped[detail.id] << {detail.index || position, position, parsed}
          end

          if grouped.empty?
            if reasoning = message.reasoning
              content << Crig::Completion::AssistantContent.reasoning(reasoning)
            end
          else
            order.each do |reasoning_id|
              blocks = grouped[reasoning_id]? || next
              blocks.sort_by! { |entry| {entry[0], entry[1]} }
              content << Crig::Completion::AssistantContent.new(
                Crig::Completion::AssistantContent::Kind::Reasoning,
                reasoning: Crig::Completion::Reasoning.new(
                  blocks.map(&.[2]),
                  reasoning_id,
                ),
              )
            end
          end

          choice_value = Crig::OneOrMany(Crig::Completion::AssistantContent).many(content)
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") unless choice_value

          Crig::Completion::CompletionResponse(self).new(
            choice_value,
            @usage.try(&.token_usage) || Crig::Completion::Usage.new,
            self,
          )
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end

      struct ToolChoiceFunctionKind
        getter name : String

        def initialize(@name : String)
        end

        def to_json_value : JSON::Any
          JSON.parse(%({"type":"function","function":{"name":#{@name.to_json}}}))
        end
      end

      struct ToolChoice
        enum Kind
          None
          Auto
          Required
          Function
        end

        getter kind : Kind
        getter functions : Array(ToolChoiceFunctionKind)

        def initialize(@kind : Kind, @functions : Array(ToolChoiceFunctionKind) = [] of ToolChoiceFunctionKind)
        end

        def self.from_core(value : Crig::Completion::ToolChoice) : self
          case value.kind
          in .none?
            new(Kind::None)
          in .auto?
            new(Kind::Auto)
          in .required?
            new(Kind::Required)
          in .specific?
            new(
              Kind::Function,
              value.function_names.map { |name| ToolChoiceFunctionKind.new(name) }
            )
          end
        end

        def to_json_value : JSON::Any
          case @kind
          in .none?     then JSON::Any.new("none")
          in .auto?     then JSON::Any.new("auto")
          in .required? then JSON::Any.new("required")
          in .function?
            JSON.parse(@functions.map(&.to_json_value).to_json)
          end
        end
      end

      struct OpenrouterCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter temperature : Float64?
        getter tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition)
        getter tool_choice : ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Message),
          @temperature : Float64? = nil,
          @tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition) = [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
          @tool_choice : ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def to_json_value : JSON::Any
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" { json.array { @messages.each(&.to_json_value.to_json(json)) } }
              json.field "temperature", @temperature unless @temperature.nil?
              unless @tools.empty?
                json.field "tools" { json.array { @tools.each(&.to_json_value.to_json(json)) } }
              end
              if tool_choice = @tool_choice
                json.field "tool_choice" { tool_choice.to_json_value.to_json(json) }
              end
            end
          end

          if additional_params = @additional_params
            JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
          else
            payload
          end
        end

        def to_json(json : JSON::Builder) : Nil
          to_json_value.to_json(json)
        end
      end

      struct OpenRouterRequestParams
        getter model : String
        getter request : Crig::Completion::Request::CompletionRequest
        getter? strict_tools : Bool

        def initialize(@model : String, @request : Crig::Completion::Request::CompletionRequest, @strict_tools : Bool = false)
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String
        getter? strict_tools : Bool

        def initialize(@client : Client, @model : String, @strict_tools : Bool = false)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def with_strict_tools : self
          self.class.new(@client, @model, true)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.chat_span("openrouter", @model, request.preamble, nil)

          payload = self.class.build_request(@model, request, @strict_tools)
          response = @client.post_json("/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("OpenRouter response did not include a success payload")
          result = response_body.to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = self.class.build_request(@model, request, @strict_tools)
          params = if additional_params = payload.additional_params
                     Crig::Providers::OpenAI.merge_json_values(additional_params, JSON.parse(%({"stream":true})))
                   else
                     JSON.parse(%({"stream":true}))
                   end
          request_payload = OpenrouterCompletionRequest.new(payload.model, payload.messages, payload.temperature, payload.tools, payload.tool_choice, params)
          Crig::Providers::OpenRouter.send_compatible_streaming_request(@client, request_payload)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        def self.build_request(model : String, req : Crig::Completion::Request::CompletionRequest, strict_tools : Bool) : OpenrouterCompletionRequest
          request_model = req.model || model
          full_history = [] of Message
          if preamble = req.preamble
            full_history << Message.system(preamble)
          end
          if docs = req.normalized_documents
            full_history.concat(Message.from_core_message(docs))
          end
          req.chat_history.each do |entry|
            full_history.concat(Message.from_core_message(entry))
          end

          tool_choice = req.tool_choice.try do |choice|
            ToolChoice.from_core(choice)
          end

          tools = req.tools.map do |tool|
            definition = Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(tool)
            strict_tools ? definition.with_strict : definition
          end

          OpenrouterCompletionRequest.new(
            request_model,
            full_history,
            req.temperature,
            tools,
            tool_choice,
            req.additional_params,
          )
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::OpenRouter::CompletionModel)
      end
    end
  end
end
