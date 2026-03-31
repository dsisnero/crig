require "../src/crig"

module Crig::Examples::OllamaStructuredOutput
  PREAMBLE = "You are a creative fiction writer. Create detailed characters."
  PROMPT   = "Create a protagonist for a sci-fi novel set on Mars."
  MODEL    = "qwen3:4b"

  struct Character
    include JSON::Serializable

    getter name : String
    getter age : Int32
    getter bio : String
    getter traits : Array(String)

    def initialize(@name : String, @age : Int32, @bio : String, @traits : Array(String))
    end
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .output_schema(Character)
      .build
  end

  def self.parse_character(response : String) : Character
    Character.from_json(response)
  end
end
