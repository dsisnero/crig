require "../spec_helper"

def tool_choice_mode_tool(name : String) : Crig::Completion::ToolDefinition
  Crig::Completion::ToolDefinition.new(
    name,
    "Return the supplied integer using #{name}.",
    JSON.parse(%({"type":"object","properties":{"value":{"type":"integer"}},"required":["value"]}))
  )
end

# Mock model that returns text for ToolChoice::None and a tool call otherwise,
# recording the effective request for each completion.
class ToolChoiceModeModel
  include Crig::Completion::CompletionModel

  getter requests = [] of Crig::Completion::Request::CompletionRequest

  def completion(request : Crig::Completion::Request::CompletionRequest)
    @requests << request
    choice = if request.tool_choice.try(&.kind.none?)
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.text("4")
               )
             else
               tool_name = if tc = request.tool_choice
                             if tc.specific?
                               tc.function_names.first
                             else
                               "alpha"
                             end
                           else
                             "alpha"
                           end
               Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                 Crig::Completion::AssistantContent.tool_call(
                   "call_1",
                   tool_name,
                   JSON.parse(%({"value":7}))
                 )
               )
             end
    Crig::Completion::CompletionResponse(String).new(
      choice,
      Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

module Crig
  describe "tool_choice_modes conformance" do
    it "honors ToolChoice::None by emitting no tool call" do
      model = ToolChoiceModeModel.new
      request = model.completion_request("Answer with only the number 4. Do not call a function.")
        .tools([tool_choice_mode_tool("alpha"), tool_choice_mode_tool("beta")])
        .tool_choice(Crig::Completion::ToolChoice.none)
        .temperature(0.0)
        .max_tokens(64)
        .build

      response = model.completion(request)

      response.choice.to_a.none? { |item| item.kind.tool_call? }.should be_true
      response.choice.to_a.first.text.try(&.text).should eq("4")
    end

    it "honors ToolChoice::Required by emitting a tool call" do
      model = ToolChoiceModeModel.new
      request = model.completion_request("Call alpha with value 7.")
        .tools([tool_choice_mode_tool("alpha"), tool_choice_mode_tool("beta")])
        .tool_choice(Crig::Completion::ToolChoice.required)
        .temperature(0.0)
        .max_tokens(96)
        .build

      response = model.completion(request)

      calls = response.choice.to_a.compact_map(&.tool_call)
      calls.size.should be >= 1
    end

    it "honors ToolChoice::Specific by emitting only the named tool" do
      model = ToolChoiceModeModel.new
      request = model.completion_request("Call beta with value 9.")
        .tools([tool_choice_mode_tool("alpha"), tool_choice_mode_tool("beta")])
        .tool_choice(Crig::Completion::ToolChoice.specific(["beta"]))
        .temperature(0.0)
        .max_tokens(96)
        .build

      response = model.completion(request)

      calls = response.choice.to_a.compact_map(&.tool_call)
      calls.empty?.should be_false
      calls.all? { |call| call.function.name == "beta" }.should be_true
    end
  end
end
