require "../spec_helper"

class FailingEmbeddingModel
  include Crig::Embeddings::EmbeddingModel

  def max_documents : Int32
    2
  end

  def ndims : Int32
    3
  end

  def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
    raise Crig::Embeddings::EmbeddingError.new("embedding provider unavailable for #{texts.first}")
  end
end

module Crig
  describe EvalOutcome, tags: %w[evals] do
    it "tracks pass, fail, and invalid states" do
      pass_outcome = EvalOutcome(SemanticSimilarityMetricScore).pass(
        SemanticSimilarityMetricScore.new(0.95)
      )
      fail_outcome = EvalOutcome(SemanticSimilarityMetricScore).fail(
        SemanticSimilarityMetricScore.new(0.12)
      )
      invalid_outcome = EvalOutcome(SemanticSimilarityMetricScore).invalid("network error")

      pass_outcome.is_pass.should be_true
      pass_score = pass_outcome.score
      pass_score.should_not be_nil
      pass_score.as(SemanticSimilarityMetricScore).score.should eq(0.95)
      fail_outcome.is_pass.should be_false
      fail_score = fail_outcome.score
      fail_score.should_not be_nil
      fail_score.as(SemanticSimilarityMetricScore).score.should eq(0.12)
      invalid_outcome.score.should be_nil
      invalid_outcome.reason.should eq("network error")
    end

    it "round-trips tagged json payloads" do
      outcome = EvalOutcome(SemanticSimilarityMetricScore).pass(
        SemanticSimilarityMetricScore.new(0.81)
      )

      roundtrip = EvalOutcome(SemanticSimilarityMetricScore).from_json(outcome.to_json)

      roundtrip.kind.pass?.should be_true
      score = roundtrip.score
      score.should_not be_nil
      score.as(SemanticSimilarityMetricScore).score.should eq(0.81)
    end
  end

  describe SemanticSimilarityMetricBuilder do
    it "requires threshold and reference answer" do
      expect_raises(Crig::EvalError, "Field must not be null: threshold") do
        SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
          .reference_answer("hello")
          .build
      end

      expect_raises(Crig::EvalError, "Field must not be null: reference_answer") do
        SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
          .threshold(0.5)
          .build
      end
    end

    it "builds a metric with a precomputed reference embedding" do
      metric = SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .threshold(0.8)
        .reference_answer("hello")
        .build

      metric.reference_answer.should eq("hello")
      metric.reference_answer_embedding.document.should eq("hello")
    end

    it "wraps embedding build failures as eval errors" do
      expect_raises(Crig::EvalError, "Eval error: embedding provider unavailable for hello") do
        SemanticSimilarityMetric.builder(FailingEmbeddingModel.new)
          .threshold(0.5)
          .reference_answer("hello")
          .build
      end
    end
  end

  describe SemanticSimilarityMetric, tags: %w[evals semantic] do
    it "passes when cosine similarity clears the threshold" do
      metric = SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .threshold(0.99)
        .reference_answer("hello")
        .build

      outcome = metric.eval("helloo")

      outcome.kind.pass?.should be_true
      outcome.is_pass.should be_true
      score = outcome.score
      score.should_not be_nil
      score.as(SemanticSimilarityMetricScore).score.should be >= 0.99
    end

    it "fails when cosine similarity is below the threshold" do
      metric = SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .threshold(0.9999)
        .reference_answer("hello")
        .build

      outcome = metric.eval("a")

      outcome.kind.fail?.should be_true
      score = outcome.score
      score.should_not be_nil
      score.as(SemanticSimilarityMetricScore).score.should be < 0.9999
    end

    it "returns invalid when embedding the input fails" do
      metric = SemanticSimilarityMetric(FailingEmbeddingModel).new(
        FailingEmbeddingModel.new,
        0.5,
        "hello",
        Crig::Embeddings::Embedding.new("hello", [1.0, 0.0, 1.0])
      )

      outcome = metric.eval("world")

      outcome.kind.invalid?.should be_true
      outcome.reason.should eq("embedding provider unavailable for world")
    end

    it "evaluates batches synchronously through the eval protocol" do
      metric = SemanticSimilarityMetric.builder(FakeEmbeddingModel.new)
        .threshold(0.99)
        .reference_answer("hello")
        .build

      outcomes = metric.eval_batch(["hello", "a"], 4)

      outcomes.size.should eq(2)
      outcomes[0].kind.pass?.should be_true
      outcomes[1].kind.fail?.should be_true
    end
  end

  describe LlmJudgeBuilder do
    it "builds a judgment metric using the extractor runtime" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        class ProbeMetricModel
          include Crig::Completion::CompletionModel

          getter last_request : Crig::Completion::Request::CompletionRequest?

          def initialize(@json : String)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(@json),
                )
              ),
              Crig::Completion::Usage.new,
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        struct ProbeMetricJudgment
          include JSON::Serializable
          include Crig::Judgment

          getter verdict : Bool
          getter explanation : String

          def initialize(@verdict : Bool, @explanation : String)
          end

          def passes : Bool
            @verdict
          end
        end

        model = ProbeMetricModel.new(%({"verdict":true,"explanation":"looks good"}))
        builder = Crig::LlmJudgeBuilder(ProbeMetricModel, ProbeMetricJudgment).new(
          Crig::ExtractorBuilder(ProbeMetricModel, ProbeMetricJudgment).new(model)
        )
        outcome = builder.build.eval("judge this")

        puts(JSON.build do |json|
          json.object do
            json.field "kind", outcome.kind.to_s
            json.field "explanation", outcome.output.not_nil!.explanation
            json.field "preamble", model.last_request.not_nil!.preamble
          end
        end)
      CRYSTAL

      result["kind"].as_s.should eq("Pass")
      result["explanation"].as_s.should eq("looks good")
      result["preamble"].as_s.includes?("Judge the prompt input by the schema given").should be_true
    end

    it "supports custom evaluator functions" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        class ProbeMetricModel
          include Crig::Completion::CompletionModel

          def initialize(@json : String)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(@json),
                )
              ),
              Crig::Completion::Usage.new,
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        struct ProbeMetricJudgment
          include JSON::Serializable
          include Crig::Judgment

          getter verdict : Bool
          getter explanation : String

          def initialize(@verdict : Bool, @explanation : String)
          end

          def passes : Bool
            @verdict
          end
        end

        model = ProbeMetricModel.new(%({"verdict":false,"explanation":"close enough"}))
        metric = Crig::LlmJudgeBuilder(ProbeMetricModel, ProbeMetricJudgment).new(
          Crig::ExtractorBuilder(ProbeMetricModel, ProbeMetricJudgment).new(model)
        ).with_fn { |judgment| judgment.explanation.includes?("close") }.build
        outcome = metric.eval("judge this")

        puts(JSON.build do |json|
          json.object do
            json.field "kind", outcome.kind.to_s
          end
        end)
      CRYSTAL

      result["kind"].as_s.should eq("Pass")
    end
  end

  describe LlmScoreMetricBuilder do
    # FIXME: Crystal 1.20.2 compiler bug triggers codegen crash in probe build
    pending "requires a threshold before building" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        class ProbeMetricModel
          include Crig::Completion::CompletionModel

          def initialize(@json : String)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(@json),
                )
              ),
              Crig::Completion::Usage.new,
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        begin
          Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
            Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(
              ProbeMetricModel.new(%({"score":0.9,"feedback":"great"}))
            )
          ).build
        rescue ex : Crig::EvalError
          puts(JSON.build do |json|
            json.object do
              json.field "kind", ex.kind.to_s
              json.field "message", ex.message
            end
          end)
        end
      CRYSTAL

      result["kind"].as_s.should eq("FieldCannotBeNull")
      result["message"].as_s.should eq("Field must not be null: threshold")
    end

    it "builds a scoring metric and applies threshold/preamble rules" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        class ProbeMetricModel
          include Crig::Completion::CompletionModel

          getter last_request : Crig::Completion::Request::CompletionRequest?

          def initialize(@json : String)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(@json),
                )
              ),
              Crig::Completion::Usage.new,
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            @last_request = request
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        model = ProbeMetricModel.new(%({"score":0.9,"feedback":"great"}))
        metric = Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
          Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(model)
        ).criteria("Be correct")
          .criteria("Be concise")
          .threshold(0.8)
          .build
        outcome = metric.eval("score this")

        puts(JSON.build do |json|
          json.object do
            json.field "kind", outcome.kind.to_s
            json.field "feedback", outcome.output.not_nil!.feedback
            json.field "preamble", model.last_request.not_nil!.preamble
          end
        end)
      CRYSTAL

      result["kind"].as_s.should eq("Pass")
      result["feedback"].as_s.should eq("great")
      result["preamble"].as_s.includes?("Be correct").should be_true
      result["preamble"].as_s.includes?("Be concise").should be_true
    end

    it "invalidates out-of-range scores" do
      result = run_crig_probe <<-'CRYSTAL'
        require "./src/crig"

        class ProbeMetricModel
          include Crig::Completion::CompletionModel

          def initialize(@json : String)
          end

          def completion(request : Crig::Completion::Request::CompletionRequest)
            Crig::Completion::CompletionResponse(String).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                Crig::Completion::AssistantContent.tool_call(
                  "tool_call_submit",
                  "submit",
                  JSON.parse(@json),
                )
              ),
              Crig::Completion::Usage.new,
              "raw",
            )
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            ["streamed"]
          end

          def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
            Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
          end
        end

        metric = Crig::LlmScoreMetricBuilder(ProbeMetricModel).new(
          Crig::ExtractorBuilder(ProbeMetricModel, Crig::LlmScoreMetricScore).new(
            ProbeMetricModel.new(%({"score":1.5,"feedback":"bad range"}))
          )
        ).threshold(0.5)
          .build
        outcome = metric.eval("score this")

        puts(JSON.build do |json|
          json.object do
            json.field "kind", outcome.kind.to_s
            json.field "reason", outcome.reason
          end
        end)
      CRYSTAL

      result["kind"].as_s.should eq("Invalid")
      result["reason"].as_s.should eq("Score 1.5 outside valid range [0.0, 1.0]")
    end
  end
end
