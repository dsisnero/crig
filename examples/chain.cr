require "../src/crig"

module Crig::Examples::Chain
  struct DictionaryEntry
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter text : String

    def initialize(@id : String, @text : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@text)
    end
  end

  def self.dictionary_entries : Array(DictionaryEntry)
    [
      DictionaryEntry.new("doc0", "Definition of a *flurbo*: A flurbo is a green alien that lives on cold planets"),
      DictionaryEntry.new("doc1", "Definition of a *glarb-glarb*: A glarb-glarb is a ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land."),
      DictionaryEntry.new("doc2", "Definition of a *linglingdong*: A term used by inhabitants of the far side of the moon to describe humans."),
    ]
  end

  def self.build_store(model) : Crig::InMemoryVectorStore(DictionaryEntry)
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(model), DictionaryEntry).new(model)
      .documents(dictionary_entries)
      .build

    Crig::InMemoryVectorStore(DictionaryEntry).from_documents_with_id_f(embeddings) do |document|
      document.id
    end
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble("You are a dictionary assistant here to assist the user in understanding the meaning of words.")
      .build
  end

  def self.build_chain(index, agent)
    Crig::Pipeline.new
      .chain(
        Crig::Pipeline.parallel(
          Crig::Pipeline.passthrough(String),
          Crig::Pipeline.new.lookup(index, 1, DictionaryEntry),
        )
      )
      .map(->(input : Tuple(String, Crig::Pipeline::Result(Array(Tuple(Float64, String, DictionaryEntry)), Crig::VectorStoreError))) do
        prompt = input[0]
        maybe_docs = input[1]

        if error = maybe_docs.error
          "Error: #{error}! Prompting without additional context\n\n#{prompt}"
        else
          docs = maybe_docs.value || [] of Tuple(Float64, String, DictionaryEntry)
          "Non standard word definitions:\n#{docs.map(&.[2].text).join("\n")}\n\n#{prompt}"
        end
      end)
      .prompt(agent)
  end

  def self.default_prompt : String
    "What does \"glarb-glarb\" mean?"
  end
end
