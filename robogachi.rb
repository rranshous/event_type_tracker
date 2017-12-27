require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'

set :http_port, (ARGV.shift || 8080).to_i
set :hunger_period_seconds, 60
set :memory_length_seconds, Config.get(:hunger_period_seconds) * 1

state_field :last_fed_at, nil, lambda { |s,o| [s,o].compact.max }
state_field :times_of_hunger, []

where "action == 'feed'" do |event, state|
  puts "BEING FED"
  state.last_fed_at = Time.now
end

report 'status' do |state|
  puts "getting status"
  { times_of_hunger: state.times_of_hunger.map(&:iso8601) }
end

periodically do |state|
  if Time.now >= hungry_at(state)
    puts "HUNGRY"
    state.times_of_hunger << Time.now
  else
    puts "NOT HUNGRY"
  end
end

cleanup do |state|
  state.times_of_hunger = state.times_of_hunger.uniq.sort.select do |hunger_time|
    hunger_time + Config.get(:hunger_period_seconds) >= Time.now
  end
end

def hungry_at state
  if state.last_fed_at.nil?
    Time.now - 1
  else
    state.last_fed_at + Config.get(:hunger_period_seconds)
  end
end
