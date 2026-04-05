require "../src/crig"

module Crig::Examples::ComplexAgenticLoopClaude
  ANTHROPIC_BETA = "token-efficient-tools-2025-02-19"
  MODEL          = Crig::Providers::Anthropic::CLAUDE_3_7_SONNET
  QUERY          = <<-TEXT
                   I'm a small business owner looking to reduce my company's carbon footprint.
                   We have 25 employees in a 5000 sq ft office space and a small fleet of 5 delivery vehicles.
                   What are the most cost-effective sustainability measures we could implement in the next 6-12 months? Try to stay concise.
                   TEXT

  RESEARCH_PREAMBLE = <<-TEXT
                      You are a specialized research agent focused on environmental science and sustainability.
                      Your role is to provide detailed, accurate information about climate change, renewable energy,
                      sustainable practices, and related topics. Always cite your sources when possible and
                      maintain scientific accuracy in your responses.
                      TEXT

  ANALYSIS_PREAMBLE = <<-TEXT
                      You are a data analysis agent specialized in interpreting environmental and sustainability data.
                      When given data or statistics, you analyze trends, identify patterns, and draw meaningful conclusions.
                      You're skilled at explaining complex data in accessible terms while maintaining scientific accuracy.
                      Always note limitations in the data and avoid overextending conclusions beyond what the evidence supports.
                      TEXT

  RECOMMENDATION_PREAMBLE = <<-TEXT
                            You are a recommendation agent specialized in suggesting practical sustainability solutions.
                            Based on research findings and analysis, you provide actionable recommendations for individuals,
                            organizations, or policymakers. Your suggestions should be specific, feasible, and tailored to
                            the context. Consider factors like cost, implementation difficulty, and potential impact when
                            making recommendations.
                            TEXT

  ORCHESTRATOR_PREAMBLE = <<-TEXT
                          You are an environmental sustainability advisor that helps users understand complex environmental issues
                          and find practical solutions. You have access to several specialized tools:

                          1. A knowledge base with information on climate change, renewable energy, sustainable agriculture, and carbon capture.
                          2. A research agent that can provide detailed information on environmental science topics.
                          3. A data analysis agent that can interpret environmental data and statistics.
                          4. A recommendation agent that can suggest practical sustainability solutions.
                          5. A think tool that allows you to reason through complex problems step by step.

                          Your workflow:
                          1. Use the knowledge base to retrieve relevant background information
                          2. Use the research agent to gather detailed information on specific topics
                          3. Use the data analysis agent to interpret any data or statistics
                          4. Use the think tool to reason through the problem and plan your approach
                          5. Use the recommendation agent to generate practical solutions

                          Combine these tools effectively to provide comprehensive, accurate, and actionable advice on
                          environmental sustainability issues.
                          TEXT

  struct KnowledgeEntry
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter title : String
    getter content : String

    def initialize(@id : String, @title : String, @content : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@content)
    end
  end

  def self.knowledge_entries : Array(KnowledgeEntry)
    [
      KnowledgeEntry.new(
        "kb1",
        "Climate Change Effects",
        "Climate change is causing rising sea levels, increased frequency of extreme weather events, and disruptions to ecosystems worldwide. The IPCC has projected that global temperatures could rise by 1.5°C to 4.5°C by 2100, depending on emission scenarios."
      ),
      KnowledgeEntry.new(
        "kb2",
        "Renewable Energy Technologies",
        "Solar photovoltaic technology converts sunlight directly into electricity using semiconductor materials. Wind turbines convert kinetic energy from wind into mechanical power, which generators then convert to electricity. Hydroelectric power generates electricity by using flowing water to turn turbines connected to generators."
      ),
      KnowledgeEntry.new(
        "kb3",
        "Sustainable Agriculture Practices",
        "Crop rotation improves soil health by alternating different crops in the same area across seasons. Agroforestry integrates trees with crop or livestock systems, enhancing biodiversity and resilience. Precision agriculture uses technology to optimize field-level management, reducing resource use while maximizing yields."
      ),
      KnowledgeEntry.new(
        "kb4",
        "Carbon Capture Methods",
        "Direct air capture extracts CO2 directly from the atmosphere using chemical processes. Bioenergy with carbon capture and storage combines biomass energy with geological CO2 storage. Enhanced weathering accelerates natural geological processes that remove CO2 from the atmosphere."
      ),
    ]
  end

  def self.build_anthropic_client(api_key : String, base_url : String = Crig::Providers::Anthropic::ANTHROPIC_API_BASE_URL)
    Crig::Providers::Anthropic::Client.builder
      .api_key(api_key)
      .base_url(base_url)
      .anthropic_beta(ANTHROPIC_BETA)
      .build
  end

  def self.build_vector_index(embedding_model : M) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
      .documents(knowledge_entries)
      .build
    store = Crig::InMemoryVectorStore(KnowledgeEntry).from_documents_with_id_f(embeddings, &.id)
    store.index(embedding_model)
  end

  def self.build_research_agent(client : Crig::Providers::Anthropic::Client, model : String = MODEL)
    client.agent(model)
      .preamble(RESEARCH_PREAMBLE)
      .name("research_agent")
      .build
  end

  def self.build_analysis_agent(client : Crig::Providers::Anthropic::Client, model : String = MODEL)
    client.agent(model)
      .preamble(ANALYSIS_PREAMBLE)
      .name("data_analysis_agent")
      .build
  end

  def self.build_recommendation_agent(client : Crig::Providers::Anthropic::Client, model : String = MODEL)
    client.agent(model)
      .preamble(RECOMMENDATION_PREAMBLE)
      .name("recommendation_agent")
      .build
  end

  def self.build_orchestrator_agent(
    client : Crig::Providers::Anthropic::Client,
    vector_index,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(ORCHESTRATOR_PREAMBLE)
      .tool(Crig::ThinkTool.new)
      .tool(vector_index)
      .tool(build_research_agent(client, model))
      .tool(build_analysis_agent(client, model))
      .tool(build_recommendation_agent(client, model))
      .name("orchestrator_agent")
      .build
  end

  def self.run_prompt(
    agent : Crig::Agent(M),
    query : String = QUERY,
    max_turns : Int32 = 15,
    history : Array(Crig::Completion::Message)? = nil,
  ) : String forall M
    request = agent.prompt(query).max_turns(max_turns)
    request = request.with_history(history.not_nil!) if history
    request.send
  end
end
