require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'

set :http_port, (ARGV.shift || 8080).to_i
set :day_length_in_hours, 8
set :meals_per_day, 3
set :playtimes_per_day, 5
set :memory_in_terms_of_meals, 1

set :day_length_in_seconds, Config.get(:day_length_in_hours) * 60 * 60
set :hunger_period_seconds,
  Config.get(:day_length_in_seconds) / Config.get(:meals_per_day)
set :bored_period_seconds,
  Config.get(:day_length_in_seconds) / Config.get(:playtimes_per_day)
set :memory_length_seconds,
  Config.get(:hunger_period_seconds) * Config.get(:memory_in_terms_of_meals)

puts "!Robogatchi!!!"
puts "Day length: #{Config.get(:day_length_in_hours)} hours"
puts "Needs #{Config.get(:meals_per_day)} meals per day"
puts "Wants to play #{Config.get(:playtimes_per_day)} times per day"

state_field :last_fed_at, nil, lambda { |s,o| [s,o].compact.max }
state_field :times_of_hunger, []
state_field :last_played_at, nil, lambda { |s,o| [s,o].compact.max }
state_field :times_of_boredom, []

where "action == 'feed'" do |event, state|
  puts "BEING FED"
  state.last_fed_at = Time.now
end

where "action == 'play'" do |event, state|
  puts "BEING PLAYED WITH"
  state.last_played_at = Time.now
end

report 'status' do |state|
  puts "reporting status"
  { times_of_hunger: state.times_of_hunger.map(&:iso8601),
    times_of_boredom: state.times_of_boredom.map(&:iso8601) }
end

periodically do |state|
  puts "checking status"
  if Time.now >= hungry_at(state)
    puts "HUNGRY"
    state.times_of_hunger << Time.now
  end
  if Time.now >= bored_at(state)
    puts "BORED"
    state.times_of_boredom << Time.now
  end
end

cleanup do |state|
  puts "cleaning up"
  state.times_of_hunger = state.times_of_hunger.uniq.sort.select do |hunger_time|
    hunger_time + Config.get(:hunger_period_seconds) >= Time.now
  end
  state.times_of_boredom = state.times_of_boredom.uniq.sort.select do |bored_time|
    bored_time + Config.get(:bored_period_seconds) >= Time.now
  end
end

def hungry_at state
  if state.last_fed_at.nil?
    Time.now - 1
  else
    state.last_fed_at + Config.get(:hunger_period_seconds)
  end
end

def bored_at state
  if state.last_played_at.nil?
    Time.now - 1
  else
    state.last_played_at + Config.get(:bored_period_seconds)
  end
end
