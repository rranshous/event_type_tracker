require 'thin'
require 'sinatra'
require 'thread'
require 'socket'

Thread.abort_on_exception = true

PORT = 7777

def log msg
  STDOUT.write "#{msg}\n"
end

# does not support binary
class NetworkBroker
  attr_accessor :server, :receivers, :accept_thread, :publish_thread, :to_publish

  def initialize
    self.receivers = {}
    self.to_publish = SizedQueue.new 10
  end

  def publish receiver_id, data
    log "publishing [#{receiver_id}]"
    if !receivers.include?(receiver_id)
      log "receiver [#{receiver_id}] not found in #{receivers.keys}"
      return false
    else
      log "adding to queue [#{receiver_id}]"
      to_publish << [receiver_id, data]
    end
    true
  rescue Errno::EPIPE
    log "broken pipe [#{receiver_id}], removing receiver"
    receivers.delete receiver_id
    false
  end

  def start!
    log "started listening on #{PORT}"
    self.server = TCPServer.new PORT
    self.accept_thread = Thread.new { self.work_accept }
    self.publish_thread = Thread.new { self.work_publish }
  end

  def add_receiver receiver_id, socket
    # TODO: kill off old socket if one was here
    log "adding receiver: #{receiver_id} :: #{socket}"
    self.receivers[receiver_id] = socket
  end

  def work_publish
    loop do
      receiver_id, data = to_publish.pop
      log "queue length: #{to_publish.length}"
      log "working publish #{receiver_id}"
      socket = receivers[receiver_id]
      log "writing #{receiver_id} :: #{socket}"
      socket.write("#{data}\n")
      log "flushing #{receiver_id}"
      socket.flush
    end
  end

  def work_accept
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
  log "got data"
  halt 400 unless JSON.load(data)
  log "datas clean, publishing"
  halt 404 unless settings.network_broker.publish receiver_id, data
end

settings.network_broker.start!
