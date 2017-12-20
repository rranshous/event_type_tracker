require 'webrick'

class HttpListener
  attr_accessor :server, :listeners, :port, :thread

  def initialize port: 8081
    self.listeners = {}
    self.port = port
    self.server = WEBrick::HTTPServer.new :Port => port
  end

  def add_listener path, &blk
    listeners[path] = blk
  end

  def start!
    self.thread = Thread.new do
      listeners.each do |path, blk|
        server.mount_proc(path) do |req, res|
          blk.call(req, res)
        end
      end
      server.start
    end
  end

  def shutdown
    server.shutdown
  end
end

