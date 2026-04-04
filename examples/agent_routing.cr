require "../src/crig"

module Crig::Examples::AgentRouting
  def self.build_animal_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble("
        Your role is to categorise the user's statement using the following values: [sheep, cow, dog]

        Return only the value.
      ")
      .build
  end

  def self.build_default_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model).build
  end

  def self.run_routing_pipeline(
    animal_agent : Crig::Agent(Crig::Providers::OpenAI::CompletionModel),
    default_agent : Crig::Agent(Crig::Providers::OpenAI::CompletionModel),
    statement : String,
  ) : Crig::Pipeline::Result(String, Crig::Completion::PromptError)
    # Create a pipeline with routing logic
    chain = Crig::Pipeline.new
      # Use our classifier agent to classify the agent under a number of fixed topics
      .prompt(animal_agent)
      # Change the prompt depending on the output from the prompt
      .map_ok do |x|
        case x.strip
        when "cow"
          "Tell me a fact about the United States of America."
        when "sheep"
          "Calculate 5+5 for me. Return only the number."
        when "dog"
          "Write me a poem about cashews"
        else
          raise "Could not process - received category: #{x}"
        end
      end
      # Send the prompt back into another agent with no pre-amble
      .prompt(default_agent)

    # Run the pipeline
    chain.call(statement)
  end

  # Main executable code
  # Main executable code - only run when file is executed directly
  if PROGRAM_NAME == __FILE__
    begin
      # Create OpenAI client
      client = Crig::Providers::OpenAI::CompletionsClient.from_env

      animal_agent = Crig::Examples::AgentRouting.build_animal_agent(client)
      default_agent = Crig::Examples::AgentRouting.build_default_agent(client)

      statement = "Sheep can self-medicate"
      result = Crig::Examples::AgentRouting.run_routing_pipeline(animal_agent, default_agent, statement)

      puts "Pipeline result: #{result.unwrap}"
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      exit 1
    end
  end
end
