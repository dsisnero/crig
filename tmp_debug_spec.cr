require "spec"
require "./src/crig"

run = Crig::AgentRun.new("hello").max_turns(5)
json = run.to_json
puts "JSON: #{json}"

# Parse manually
pull = JSON::PullParser.new(json)
pull.read_object do |key|
  case key
  when "max_turns"      then puts "max_turns_val=#{pull.read_int}"
  when "current_turn"   then puts "current_turn_val=#{pull.read_int}"
  when "state"          then puts "state=#{pull.read_string}"
  when "pending"        then pull.read_begin_array; pull.read_end_array
  when "new_messages"   then pull.read_begin_array; pull.read_end_array
  when "completion_calls" then pull.read_begin_array; pull.read_end_array
  else puts "unknown=#{key}"; pull.skip
  end
end

restored = Crig::AgentRun.from_json(json)
puts "restored.max_turns=#{restored.max_turns}"
