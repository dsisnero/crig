require "../src/crig"

module Crig::Examples::RagOllama
  struct WordDefinition
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter word : String
    getter definitions : Array(String)

    def initialize(@id : String, @word : String, @definitions : Array(String))
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      @definitions.each { |definition| embedder.embed(definition) }
    end
  end

  BASE_URL         = "http://localhost:11434"
  EMBEDDING_MODEL  = "nomic-embed-text"
  COMPLETION_MODEL = "qwen2.5:14b"
  DEFAULT_PROMPT   = "What does \"glarb-glarb\" mean?"
  PREAMBLE         = <<-TEXT
                      You are a dictionary assistant here to assist the user in understanding the meaning of words.
                      You will find additional non-standard word definitions that could be useful below.
                    TEXT

  def self.build_client(base_url : String = BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.new(Crig::Nothing.new, base_url)
  end

  def self.word_definitions : Array(WordDefinition)
    [
      WordDefinition.new(
        "doc0",
        "flurbo",
        [
          "1. *flurbo* (name): A flurbo is a green alien that lives on cold planets.",
          "2. *flurbo* (name): A fictional digital currency that originated in the animated series Rick and Morty.",
        ]
      ),
      WordDefinition.new(
        "doc1",
        "glarb-glarb",
        [
          "1. *glarb-glarb* (noun): A glarb-glarb is a ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
          "2. *glarb-glarb* (noun): A fictional creature found in the distant, swampy marshlands of the planet Glibbo in the Andromeda galaxy.",
        ]
      ),
      WordDefinition.new(
        "doc2",
        "linglingdong",
        [
          "1. *linglingdong* (noun): A term used by inhabitants of the far side of the moon to describe humans.",
          "2. *linglingdong* (noun): A rare, mystical instrument crafted by the ancient monks of the Nebulon Mountain Ranges on the planet Quarm.",
        ]
      ),
    ]
  end

  def self.build_store(model : M) : Crig::InMemoryVectorStore(WordDefinition) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder(M, WordDefinition).new(model)
      .documents(word_definitions)
      .build

    Crig::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(embeddings, &.id)
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    index,
    model : String = COMPLETION_MODEL,
  ) : Crig::Agent(Crig::Providers::Ollama::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .dynamic_context(1, index)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = DEFAULT_PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
