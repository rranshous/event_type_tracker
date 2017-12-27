require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'

set :http_port, (ARGV.shift || 8080).to_i
set :day_length_in_hours, 8
set :meals_per_day, 3
set :playtimes_per_day, 5
set :memory_in_terms_of_meals, 1

#####################################
puts "!Robogatchi!!!"
puts "Day length: #{Config.get(:day_length_in_hours)} hours"
puts "Needs #{Config.get(:meals_per_day)} meals per day"
puts "Wants to play #{Config.get(:playtimes_per_day)} times per day"
#####################################

set :day_length_in_seconds, Config.get(:day_length_in_hours) * 60 * 60
set :hunger_period_seconds,
  Config.get(:day_length_in_seconds) / Config.get(:meals_per_day)
set :bored_period_seconds,
  Config.get(:day_length_in_seconds) / Config.get(:playtimes_per_day)
set :memory_length_seconds,
  Config.get(:hunger_period_seconds) * Config.get(:memory_in_terms_of_meals)

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
  { getting_hungry: getting_hungry?(state),
    is_hungry: is_hungry?(state),
    getting_bored: getting_bored?(state),
    is_bored: is_bored?(state),
    disposition: disposition(state)
  }
end

periodically do |state|
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
  state.times_of_hunger = state.times_of_hunger.uniq.sort.select do |hunger_time|
    hunger_time + Config.get(:hunger_period_seconds) >= Time.now
  end
  state.times_of_boredom = state.times_of_boredom.uniq.sort.select do |bored_time|
    bored_time + Config.get(:bored_period_seconds) >= Time.now
  end
end

def getting_hungry? state
  starts_getting_hungry_at(state) <= Time.now
end

def is_hungry? state
  hungry_at(state) <= Time.now
end

def starts_getting_hungry_at state
  hungry_at(state) - (Config.get(:day_length_in_seconds) / 15)
end

def is_bored? state
  bored_at(state) <= Time.now
end

def hungry_at state
  if state.last_fed_at.nil?
    Time.now - 1
  else
    state.last_fed_at + Config.get(:hunger_period_seconds)
  end
end

def getting_bored? state
  starts_getting_bored_at(state) <= Time.now
end

def is_bored? state
  bored_at(state) <= Time.now
end

def starts_getting_bored_at state
  bored_at(state) - (Config.get(:day_length_in_seconds) / 15)
end

def bored_at state
  if state.last_played_at.nil?
    Time.now - 1
  else
    state.last_played_at + Config.get(:bored_period_seconds)
  end
end

def disposition state
  now = Time.now.to_i
  bored_amount = now - (state.times_of_boredom.first || 0).to_i
  hunger_amount = now - (state.times_of_hunger.first || 0).to_i
  memory_length_seconds = Config.get(:memory_length_seconds)
  percent_bad = (bored_amount + hunger_amount).to_f / memory_length_seconds
  if percent_bad < 0.1
    :very_good
  elsif percent_bad < 0.3
    :good
  elsif percent_bad < 0.5
    :bad
  elsif percent_bad < 0.9
    :very_bad
  end
end
