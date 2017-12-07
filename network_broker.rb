require 'sinatra'

PORT = 7777

def log msg
  STDOUT.write "#{msg}\n"
end

# does not support binary
require 'socket'
class NetworkBroker
  attr_accessor :server, :receivers, :thread

  def initialize
    self.receivers = {}
  end

  def publish receiver_id, data
    log "publishing [#{receiver_id}]: #{data}"
    if !receivers.include?(receiver_id)
      log "receiver [#{receiver_id}] not found in #{receivers.keys}"
      return false
    else
      log "writing #{receiver_id}"
      socket = receivers[receiver_id]
      socket.write("#{data}\n")
      socket.flush
    end
    true
  rescue Errno::EPIPE
    puts "broken pipe [#{receiver_id}], removing receiver"
    receivers.delete receiver_id
    false
  end

  def start!
    log "started listening on #{PORT}"
    self.server = TCPServer.new PORT
    self.thread = Thread.new { self.work }
  end

  def add_receiver receiver_id, socket
    # TODO: kill off old socket if one was here
    log "adding receiver: #{receiver_id} :: #{socket}"
    self.receivers[receiver_id] = socket
  end

  def work
    log "starting work"
    loop do
      log "new loop"
      Thread.new(server.accept) do |socket|
        log "accepted: #{socket}"
        config = JSON.load(socket.readline)
        log "config [#{socket}]: #{config}"
        self.add_receiver config['receiver_id'], socket
      end
    end
  end
    
end

set :network_broker, NetworkBroker.new

post "/injest/:receiver_id" do |receiver_id|
  data = request.body.read
  log "got data: #{data}"
  halt 400 unless JSON.load(data)
  log "datas clean, publishing"
  halt 404 unless settings.network_broker.publish receiver_id, data
end

settings.network_broker.start!
