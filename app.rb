require_relative 'simpleagent'
require_relative 'http_event_receiver'
require_relative 'http_listener'
require 'thread'


state_field :event_types, Array

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
  state.event_types = state.event_types.uniq
  puts "post cleanup state: #{state}"
end
