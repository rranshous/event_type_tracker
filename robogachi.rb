require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'

set :http_port, (ARGV.shift || 8080).to_i
set :hunger_period_seconds, 60

state_field :last_fed_at, nil, lambda { |s,o| [s,o].compact.max }
state_field :hunger_times, []

where "action == 'feed'" do |event, state|
  puts "BEING FED"
  state.last_fed_at = Time.now
end

report 'status' do |state|
  puts "getting status"
  { hunger_times: state.hunger_times.map(&:iso8601) }
end

periodically do |state|
  if Time.now >= hungry_at(state)
    puts "HUNGRY"
    state.hunger_times << Time.now
  else
    puts "NOT HUNGRY"
  end
end

cleanup do |state|
  state.hunger_times = state.hunger_times.uniq.sort
end

def hungry_at state
  if state.last_fed_at.nil?
    Time.now
  else
    state.last_fed_at + Config.get(:hunger_period_seconds)
  end
end