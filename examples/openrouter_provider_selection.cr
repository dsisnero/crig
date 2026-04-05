require "../src/crig"

module Crig::Examples::OpenRouterProviderSelection
  DEEPSEEK_V3_2 = "deepseek/deepseek-v3.2"

  def self.order_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .order(["DeepInfra", "DeepSeek", "Chutes"])
      .allow_fallbacks(true)
  end

  def self.allowlist_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .only(["DeepInfra", "AtlasCloud"])
      .allow_fallbacks(false)
  end

  def self.blocklist_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new.ignore(["Google Vertex"])
  end

  def self.latency_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Latency)
  end

  def self.price_with_throughput_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Price)
      .preferred_min_throughput(
        Crig::Providers::OpenRouter::ThroughputThreshold.percentile(
          Crig::Providers::OpenRouter::PercentileThresholds.new.p90(15.0)
        )
      )
  end

  def self.require_parameters_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new.require_parameters(true)
  end

  def self.zdr_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .data_collection(Crig::Providers::OpenRouter::DataCollection::Deny)
      .zdr(true)
  end

  def self.quantization_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .quantizations([Crig::Providers::OpenRouter::Quantization::Fp8])
  end

  def self.max_price_preferences : Crig::Providers::OpenRouter::ProviderPreferences
    Crig::Providers::OpenRouter::ProviderPreferences.new
      .max_price(Crig::Providers::OpenRouter::MaxPrice.new.prompt(0.30).completion(0.50))
  end

  def self.combined_params : JSON::Any
    JSON.parse(%({
      "provider": #{Crig::Providers::OpenRouter::ProviderPreferences.new
                      .order(["DeepSeek", "DeepInfra", "Parasail"])
                      .sort(Crig::Providers::OpenRouter::ProviderSortStrategy::Throughput)
                      .to_json_value["provider"].to_json},
      "transforms": ["middle-out"]
    }))
  end

  def self.build_agent(
    client : Crig::Providers::OpenRouter::Client,
    params : JSON::Any,
    model : String = DEEPSEEK_V3_2,
  ) : Crig::Agent(Crig::Providers::OpenRouter::CompletionModel)
    client.agent(model)
      .preamble("You are a helpful assistant.")
      .additional_params(params)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
