require_relative 'simpleagent'
require_relative 'network_broker_client.rb'
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
  state.event_types << event_type
end

where 'true == true' do |event|
  puts "start sleeping"
  sleep 1
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

# load up some state for the agent
# TODO: move state management elsewhere
state = StateLoader.load(State)
puts "starting state: #{state}"
SimpleAgent.instance.state = state
SimpleAgent.instance.periodically do |state|
  # seems like some sort of locking should be occuring right now
  path = StateSaver.save(state)
  puts "saved: #{path}"
end

SimpleAgent.instance.subscribe Condition.new('action.response != null') do |event|
  puts "report #{event['action']['response']}: #{event['response']}"
end

# setup the network broker connection
events_in = SizedQueue.new 10
endpoint = OpenStruct.new(host: 'localhost', port: 7777)
name = "client-0"
puts "network name: #{name}"
Thread.new(NetworkBrokerClient.new(endpoint, name), events_in) do |network_broker, event_queue|
  puts "starting network broker background thread, listening"
  network_broker.listen do |event|
    event_queue << event
  end
end

# have to keep the proc from dying by holding in a loop here
loop do
  event_data = events_in.pop
  puts "queue length: #{events_in.length}"
  Broker.instance.event event_data
end
