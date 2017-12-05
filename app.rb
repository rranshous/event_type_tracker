require_relative 'simpleagent'

class State
  # TODO: make generic and cool
  attr_accessor :event_types
  def initialize
    self.event_types = Array.new
  end

  def inspect
    "<State event_types=#{self.event_types}>"
  end

  def to_s
    inspect
  end
end


# block will run for each event observed
where 'eventType != null' do |event, state|
  event_type = event['eventType']
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


# FOR TESTING
events = [
  { 'eventType' => 'one.two' },
  { 'eventType' => 'one' },
  { 'eventType' => 'three' },
  { 'eventType' => 'three' },
  { 'eventType' => 'three' },
  { 'bob' => 'is a fine name' },
  { 'action' => { 'request' => 'unique_event_types.json' } }
]

events.each { |e| Broker.instance.event e }

loop do
  sleep 3
  puts "state: #{SimpleAgent.instance.state}"
end
