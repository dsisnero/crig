module Crig
  class EvalError < Exception
    enum Kind
      FieldCannotBeNull
      Custom
    end

    getter kind : Kind
    getter field : String?

    def initialize(@kind : Kind, message : String, @field : String? = nil)
      super(message)
    end

    def self.field_cannot_be_null(field : String) : self
      new(Kind::FieldCannotBeNull, "Field must not be null: #{field}", field)
    end

    def self.custom(message : String) : self
      new(Kind::Custom, "Eval error: #{message}")
    end
  end

  struct EvalOutcome(Output)
    enum Kind
      Pass
      Fail
      Invalid
    end

    getter kind : Kind
    getter output : Output?
    getter reason : String?

    def initialize(@kind : Kind, @output : Output? = nil, @reason : String? = nil)
    end

    def self.pass(output : Output) : self
      new(Kind::Pass, output: output)
    end

    def self.fail(output : Output) : self
      new(Kind::Fail, output: output)
    end

    def self.invalid(reason : String) : self
      new(Kind::Invalid, reason: reason)
    end

    # ameba:disable Naming/PredicateName
    def is_pass : Bool
      @kind.pass?
    end

    # ameba:enable Naming/PredicateName

    def score : Output?
      return if @kind.invalid?

      @output
    end

    def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "outcome", @kind.to_s.downcase
        if value = @output
          json.field "data", value
        elsif value = @reason
          json.field "data", value
        end
      end
    end

    def self.from_json(string : String) : self
      from_json(JSON::PullParser.new(string))
    end

    def self.from_json(pull : JSON::PullParser) : self
      outcome = nil.as(String?)
      output = nil.as(Output?)
      reason = nil.as(String?)

      pull.read_begin_object
      until pull.kind.end_object?
        key = pull.read_object_key
        case key
        when "outcome"
          outcome = pull.read_string
        when "data"
          case outcome
          when "pass", "fail"
            output = Output.from_json(pull.read_raw)
          when "invalid"
            reason = pull.read_string
          else
            pull.skip
          end
        else
          pull.skip
        end
      end
      pull.read_end_object

      case outcome
      when "pass"
        pass(output.as(Output))
      when "fail"
        fail(output.as(Output))
      when "invalid"
        invalid(reason || "")
      else
        raise JSON::ParseException.new("Unknown eval outcome: #{outcome}", 0, 0)
      end
    end
  end

  module Eval(Output)
    abstract def eval(input : String) : EvalOutcome(Output)

    def eval_batch(input : Enumerable(String), _concurrency_limit : Int32) : Array(EvalOutcome(Output))
      input.map { |item| eval(item) }.to_a
    end
  end

  module Judgment
    abstract def passes : Bool
  end

  struct LlmJudgeMetric(M, T)
    include Eval(T)

    getter ext : Extractor(M, T)

    def initialize(@ext : Extractor(M, T))
    end

    def eval(input : String) : EvalOutcome(T)
      judgment = @ext.extract(input)
      judgment.passes ? EvalOutcome(T).pass(judgment) : EvalOutcome(T).fail(judgment)
    rescue ex
      EvalOutcome(T).invalid(ex.message || ex.class.name)
    end
  end

  struct LlmJudgeMetricWithFn(M, T)
    include Eval(T)

    getter ext : Extractor(M, T)

    def initialize(@ext : Extractor(M, T), &@evaluator : T -> Bool)
    end

    def eval(input : String) : EvalOutcome(T)
      judgment = @ext.extract(input)
      @evaluator.call(judgment) ? EvalOutcome(T).pass(judgment) : EvalOutcome(T).fail(judgment)
    rescue ex
      EvalOutcome(T).invalid(ex.message || ex.class.name)
    end
  end

  struct LlmJudgeBuilder(M, T)
    getter ext : ExtractorBuilder(M, T)

    def initialize(@ext : ExtractorBuilder(M, T))
    end

    def with_fn(&evaluator : T -> Bool) : LlmJudgeBuilderWithFn(M, T)
      LlmJudgeBuilderWithFn(M, T).new(@ext, &evaluator)
    end

    def build : LlmJudgeMetric(M, T)
      ext = @ext
        .preamble("Judge the prompt input by the schema given and return it as a JSON tool result")
        .build
      LlmJudgeMetric(M, T).new(ext)
    end
  end

  struct LlmJudgeBuilderWithFn(M, T)
    getter ext : ExtractorBuilder(M, T)

    def initialize(@ext : ExtractorBuilder(M, T), &@evaluator : T -> Bool)
    end

    def with_fn(&evaluator : T -> Bool) : self
      self.class.new(@ext, &evaluator)
    end

    def build : LlmJudgeMetricWithFn(M, T)
      ext = @ext
        .preamble("Judge the prompt input by the schema given and return it as a JSON tool result")
        .build
      LlmJudgeMetricWithFn(M, T).new(ext, &@evaluator)
    end
  end

  struct LlmScoreMetricScore
    include JSON::Serializable

    getter score : Float64
    getter feedback : String

    def initialize(@score : Float64, @feedback : String)
    end
  end

  struct LlmScoreMetric(M)
    include Eval(LlmScoreMetricScore)

    getter agent : Extractor(M, LlmScoreMetricScore)
    getter threshold : Float64

    def initialize(@agent : Extractor(M, LlmScoreMetricScore), @threshold : Float64)
    end

    def eval(input : String) : EvalOutcome(LlmScoreMetricScore)
      res = @agent.extract(input)
      return EvalOutcome(LlmScoreMetricScore).invalid("Score #{res.score} outside valid range [0.0, 1.0]") unless (0.0..1.0).includes?(res.score)

      if res.score >= @threshold
        EvalOutcome(LlmScoreMetricScore).pass(res)
      else
        EvalOutcome(LlmScoreMetricScore).fail(res)
      end
    rescue ex
      EvalOutcome(LlmScoreMetricScore).invalid(ex.message || ex.class.name)
    end
  end

  struct LlmScoreMetricBuilder(M)
    getter agent : ExtractorBuilder(M, LlmScoreMetricScore)
    getter criteria_values : Array(String)
    getter threshold_value : Float64?

    def initialize(
      @agent : ExtractorBuilder(M, LlmScoreMetricScore),
      @criteria_values : Array(String) = [] of String,
      @threshold_value : Float64? = nil,
    )
    end

    def threshold(threshold : Float64) : self
      self.class.new(@agent, @criteria_values, threshold)
    end

    def criteria(criteria : String) : self
      self.class.new(@agent, @criteria_values + [criteria], @threshold_value)
    end

    def build : LlmScoreMetric(M)
      threshold = @threshold_value || raise EvalError.field_cannot_be_null("threshold")
      preamble = "You are an evaluation model. Score the input based on these criteria:\n#{@criteria_values.join("\n")}\n\n" \
                 "Provide a score between 0.0 and 1.0 (where 1.0 is best) and explain your reasoning."

      agent = @agent.preamble(preamble).build
      LlmScoreMetric(M).new(agent, threshold)
    end
  end

  struct SemanticSimilarityMetricScore
    include JSON::Serializable

    getter score : Float64

    def initialize(@score : Float64)
    end
  end

  struct SemanticSimilarityMetric(E)
    include Eval(SemanticSimilarityMetricScore)

    getter embedding_model : E
    getter threshold : Float64
    getter reference_answer : String
    getter reference_answer_embedding : Crig::Embeddings::Embedding

    def initialize(
      @embedding_model : E,
      @threshold : Float64,
      @reference_answer : String,
      @reference_answer_embedding : Crig::Embeddings::Embedding,
    )
    end

    def self.builder(embedding_model : E) : SemanticSimilarityMetricBuilder(E)
      SemanticSimilarityMetricBuilder(E).new(embedding_model)
    end

    def eval(input : String) : EvalOutcome(SemanticSimilarityMetricScore)
      input_embedding = @embedding_model.embed_text(input)
      cosine_sim = input_embedding.cosine_similarity(@reference_answer_embedding, false)
      score = SemanticSimilarityMetricScore.new(cosine_sim)

      if cosine_sim >= @threshold
        EvalOutcome(SemanticSimilarityMetricScore).pass(score)
      else
        EvalOutcome(SemanticSimilarityMetricScore).fail(score)
      end
    rescue ex
      EvalOutcome(SemanticSimilarityMetricScore).invalid(ex.message || ex.class.name)
    end
  end

  struct SemanticSimilarityMetricBuilder(E)
    getter embedding_model : E
    getter threshold_value : Float64?
    getter reference_answer_value : String?

    def initialize(
      @embedding_model : E,
      @threshold_value : Float64? = nil,
      @reference_answer_value : String? = nil,
    )
    end

    def threshold(threshold : Float64) : self
      self.class.new(
        @embedding_model,
        threshold_value: threshold,
        reference_answer_value: @reference_answer_value
      )
    end

    def reference_answer(reference_answer : String) : self
      self.class.new(
        @embedding_model,
        threshold_value: @threshold_value,
        reference_answer_value: reference_answer
      )
    end

    def build : SemanticSimilarityMetric(E)
      threshold = @threshold_value || raise EvalError.field_cannot_be_null("threshold")
      reference_answer = @reference_answer_value || raise EvalError.field_cannot_be_null("reference_answer")
      reference_answer_embedding = @embedding_model.embed_text(reference_answer)

      SemanticSimilarityMetric(E).new(
        @embedding_model,
        threshold,
        reference_answer,
        reference_answer_embedding
      )
    rescue ex : Crig::Embeddings::EmbeddingError
      raise EvalError.custom(ex.message || ex.class.name)
    end
  end
end
