require "../src/crig"

module Crig::Examples::AgentParallelization
  struct DocumentScore
    include JSON::Serializable

    # The score of the document
    getter score : Float32

    def initialize(@score : Float32)
    end
  end

  def self.build_manipulation_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore)
    client.extractor(DocumentScore, model)
      .preamble(
        "
        Your role is to score a user's statement on how manipulative it sounds between 0 and 1.
      ")
      .build
  end

  def self.build_depression_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore)
    client.extractor(DocumentScore, model)
      .preamble(
        "
        Your role is to score a user's statement on how depressive it sounds between 0 and 1.
      ")
      .build
  end

  def self.build_intelligent_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore)
    client.extractor(DocumentScore, model)
      .preamble(
        "
        Your role is to score a user's statement on how intelligent it sounds between 0 and 1.
      ")
      .build
  end

  def self.run_parallel_pipeline(
    manipulation_agent : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore),
    depression_agent : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore),
    intelligent_agent : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, DocumentScore),
    statement : String,
  ) : String
    # Create a pipeline with parallel processing
    pipeline = Crig::Pipeline.new
      .chain(Crig::Pipeline.parallel(
        Crig::Pipeline.passthrough(String),
        Crig::Pipeline::AgentOps.extract(manipulation_agent, String),
        Crig::Pipeline::AgentOps.extract(depression_agent, String),
        Crig::Pipeline::AgentOps.extract(intelligent_agent, String)
      ))
      .map do |payload|
        # Unpack the nested tuple: Tuple(Tuple(Tuple(String, Result1), Result2), Result3)
        inner_tuple = payload[0]           # Tuple(Tuple(String, Result1), Result2)
        inner_inner_tuple = inner_tuple[0] # Tuple(String, Result1)
        statement = inner_inner_tuple[0]
        manip_score = inner_inner_tuple[1]
        dep_score = inner_tuple[1]
        int_score = payload[1]

        "
        Original statement: #{statement}
        Manipulation sentiment score: #{manip_score.unwrap.score}
        Depression sentiment score: #{dep_score.unwrap.score}
        Intelligence sentiment score: #{int_score.unwrap.score}
        "
      end

    # Run the pipeline
    pipeline.call(statement)
  end
end

# Main executable code
begin
  # Create OpenAI client
  client = Crig::Providers::OpenAI::Client.from_env

  manipulation_agent = Crig::Examples::AgentParallelization.build_manipulation_agent(client)
  depression_agent = Crig::Examples::AgentParallelization.build_depression_agent(client)
  intelligent_agent = Crig::Examples::AgentParallelization.build_intelligent_agent(client)

  statement = "I hate swimming. The water always gets in my eyes."
  result = Crig::Examples::AgentParallelization.run_parallel_pipeline(
    manipulation_agent, depression_agent, intelligent_agent, statement
  )

  puts "Pipeline run: #{result}"
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
