require "../../src/crig"

module Crig::Examples::DeepSeek::AgentOrchestrator
  struct Specification
    include JSON::Serializable

    getter tasks : Array(Task)

    def initialize(@tasks : Array(Task))
    end
  end

  struct Task
    include JSON::Serializable

    getter original_task : String
    getter style : String
    getter guidelines : String

    def initialize(@original_task : String, @style : String, @guidelines : String)
    end
  end

  struct TaskResults
    include JSON::Serializable

    getter style : String
    getter response : String

    def initialize(@style : String, @response : String)
    end
  end

  def self.build_classify_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, Specification)
    client.extractor(Specification, model)
      .preamble("
        Analyze the given task and break it down into 2-3 distinct approaches.

        Provide an Analysis:
        Explain your understanding of the task and which variations would be valuable.
        Focus on how each approach serves different aspects of the task.

        Along with the analysis, provide 2-3 approaches to tackle the task, each with a brief description:

        Formal style: Write technically and precisely, focusing on detailed specifications
        Conversational style: Write in a friendly and engaging way that connects with the reader
        Hybrid style: Tell a story that includes technical details, combining emotional elements with specifications

        Return only JSON output.
      ")
      .build
  end

  def self.build_content_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, TaskResults)
    client.extractor(TaskResults, model)
      .preamble(
        "
          Generate content based on the original task, style, and guidelines.

          Return only your response and the style you used as a JSON object.
        ")
      .build
  end

  def self.build_judge_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, Specification)
    client.extractor(Specification, model)
      .preamble(
        "
        Analyze the given written materials and decide the best one, giving your reasoning.

        Return the style as well as the corresponding material you have chosen as a JSON object.
        ")
      .build
  end

  def self.run_orchestration(
    classify_agent : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, Specification),
    content_agent : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, TaskResults),
    judge_agent : Crig::Extractor(Crig::Providers::DeepSeek::CompletionModel, Specification),
    task_prompt : String,
  ) : Specification
    # Step 1: Classify and break down the task
    specification = classify_agent.extract(task_prompt)

    # Step 2: Generate content for each task variation
    results = [] of TaskResults
    specification.tasks.each do |task|
      task_result = content_agent.extract(
        "
        Task: #{task.original_task},
        Style: #{task.style},
        Guidelines: #{task.guidelines}
        "
      )
      results << task_result
    end

    # Step 3: Judge the results
    task_results_json = results.to_json
    judge_agent.extract(task_results_json)
  end
# Main executable code - always run for examples
# Main executable code - only run when file is executed directly
if PROGRAM_NAME == __FILE__
  begin
  # Create DeepSeek client
  client = Crig::Providers::DeepSeek::Client.from_env

  classify_agent = Crig::Examples::DeepSeek::AgentOrchestrator.build_classify_agent(client)
  content_agent = Crig::Examples::DeepSeek::AgentOrchestrator.build_content_agent(client)
  judge_agent = Crig::Examples::DeepSeek::AgentOrchestrator.build_judge_agent(client)

  task_prompt = "
    Write a product description for a new eco-friendly water bottle.
    The target_audience is environmentally conscious millennials and key product features are: plastic-free, insulated, lifetime warranty
  "

  result = Crig::Examples::DeepSeek::AgentOrchestrator.run_orchestration(classify_agent, content_agent, judge_agent, task_prompt)

  puts "Results: #{result}"
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
  end
