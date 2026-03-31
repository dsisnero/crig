require "../src/crig"

module Crig::Examples::GeminiStructuredOutput
  MODEL    = "gemini-3-flash-preview"
  PREAMBLE = "You are a professional chef. Provide detailed and accurate recipes."
  PROMPT   = "Give me a recipe for spaghetti carbonara."

  enum Difficulty
    Easy
    Medium
    Hard
  end

  struct Timing
    include JSON::Serializable

    getter prep_minutes : Int32
    getter cook_minutes : Int32
    getter total_minutes : Int32

    def initialize(@prep_minutes : Int32, @cook_minutes : Int32, @total_minutes : Int32)
    end
  end

  struct Ingredient
    include JSON::Serializable

    getter name : String
    getter quantity : String
    getter optional : Bool

    def initialize(@name : String, @quantity : String, @optional : Bool)
    end
  end

  struct Step
    include JSON::Serializable

    getter number : Int32
    getter instruction : String
    getter duration_minutes : Int32

    def initialize(@number : Int32, @instruction : String, @duration_minutes : Int32)
    end
  end

  struct Nutrition
    include JSON::Serializable

    getter servings : Int32
    getter calories : Int32
    getter protein_g : Float64
    getter fat_g : Float64
    getter carbs_g : Float64

    def initialize(@servings : Int32, @calories : Int32, @protein_g : Float64, @fat_g : Float64, @carbs_g : Float64)
    end
  end

  struct RecipeInfo
    include JSON::Serializable

    getter name : String
    getter cuisine : String
    getter timing : Timing
    getter ingredients : Array(Ingredient)
    getter steps : Array(Step)
    getter nutrition : Nutrition
    getter difficulty : Difficulty

    def initialize(
      @name : String,
      @cuisine : String,
      @timing : Timing,
      @ingredients : Array(Ingredient),
      @steps : Array(Step),
      @nutrition : Nutrition,
      @difficulty : Difficulty,
    )
    end
  end

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .output_schema(RecipeInfo)
      .build
  end

  def self.parse_recipe(response : String) : RecipeInfo
    RecipeInfo.from_json(response)
  end
end
