require "../src/crig"

module Crig::Examples::OpenAIStructuredOutput
  PREAMBLE = "You are a helpful weather assistant. Respond with realistic weather data."
  PROMPT   = "What's the weather forecast for New York City today?"

  struct Wind
    include JSON::Serializable

    getter speed_mph : Float64
    getter direction : String

    def initialize(@speed_mph : Float64, @direction : String)
    end
  end

  struct Conditions
    include JSON::Serializable

    getter temperature_f : Float64
    getter humidity_pct : Int32
    getter description : String
    getter wind : Wind

    def initialize(@temperature_f : Float64, @humidity_pct : Int32, @description : String, @wind : Wind)
    end
  end

  struct DayForecast
    include JSON::Serializable

    getter day : String
    getter high_f : Float64
    getter low_f : Float64
    getter conditions : Conditions

    def initialize(@day : String, @high_f : Float64, @low_f : Float64, @conditions : Conditions)
    end
  end

  struct WeatherForecast
    include JSON::Serializable

    getter city : String
    getter current : Conditions
    getter daily_forecast : Array(DayForecast)

    def initialize(@city : String, @current : Conditions, @daily_forecast : Array(DayForecast))
    end
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.build_schema_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .output_schema(WeatherForecast)
      .build
  end

  def self.run_typed_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : WeatherForecast forall M
    agent.prompt_typed(WeatherForecast, prompt).send
  end

  def self.parse_forecast(response : String) : WeatherForecast
    WeatherForecast.from_json(response)
  end
end
