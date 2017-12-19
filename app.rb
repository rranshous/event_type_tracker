require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'
require 'thread'


class State
  # TODO: make generic and cool
  attr_accessor :event_types
  def initialize
    self.event_types = Array.new
  end

  def marshal_dump
    [@event_types]
  end

  def marshal_load array
    @event_types, _ = array
  end

  def inspect
    "<State event_types=#{self.event_types}>"
  end

  def to_s
    inspect
  end

  def + other
    s = self.class.new
    s.event_types += self.event_types
    s.event_types += other.event_types
    s
  end
end

# block will run for each event observed
where 'eventType != null' do |event, state|
  event_type = event['eventType']
  puts "adding event type: #{event_type}"
  state.event_types << event_type
end

# block will run when the report is requested
# results of block eval will be returned to requester
report 'unique_event_types.json' do |state|
  puts "generating report"
  state.event_types.uniq
end

# cleanup block will be run periodically
# is used to "clean up" the data that it has been collecting
cleanup do |state|
  puts "in cleanup"
  state.event_types = state.event_types.uniq
end

puts "DONE"
