require 'securerandom'
require 'socket'
require 'json'

class NetworkBrokerClient

  attr_accessor :receiver_id, :endpoint

  def initialize endpoint, receiver_id=SecureRandom.uuid
    self.endpoint = endpoint
    self.receiver_id = receiver_id
    STDERR.puts "config: #{config}"
  end

  def listen &blk
    socket = TCPSocket.new endpoint.host, endpoint.port
    socket.write "#{config.to_json}\n"
    loop do
      line = socket.readline
      data = JSON.load line
      blk.call data
    end
  end

  def config
    { receiver_id: receiver_id }
  end
end

def connect endpoint, &blk
  client = NetworkBrokerClient.new endpoint
  client.listen do |d|
    blk.call d
  end
end

if __FILE__ == $0
  require 'ostruct'
  host = 'localhost'
  port = 7777
  endpoint = OpenStruct.new(host: host, port: port)
  connect(endpoint) do |event|
    puts event
  end
end
