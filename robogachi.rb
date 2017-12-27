require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'

class Hungry < Emotion
  attr_accessor :when
  def initialize
    self.when = Time.now
  end
  def name
    :hungry
  end
  def == other
    self.when == other.when && self.name == other.name
  end
end

set :http_port, (ARGV.shift || 8080).to_i
set :hunger_period_seconds, 60

state_field :last_fed_at, Time, lambda { |s,o| [s,o].max }
state_field :feelings, Array

where "action == 'feed'" do |event, state|
  state.last_fed_at = Time.now
end

report 'status' do |state|
  puts "getting status"
  { feelings: state.feelings.map(&:name) }
end

periodically do |state|
  hungry_at = last_fed_at + hunger_period_seconds
  puts "now:#{Time.now}; last_fed_at:#{last_fed_at}; hungry_at:#{hungry_at}"
  if Time.now > hungry_at
    puts "hungry"
    state.feelings << Hungry.new
  end
end

cleanup do |state|
  puts "post cleanup state: #{state}"
  state.feelings == state.feelings.uniq
end
