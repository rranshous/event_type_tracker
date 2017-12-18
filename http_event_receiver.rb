require 'webrick'

class HttpEventReceiver

  PORT = 8080

  attr_accessor :server

  def initialize
    self.server = WEBrick::HTTPServer.new :Port => PORT
  end

  def listen!
    server.mount_proc '/event' do |req, res|
      puts "got req: #{req}"
      begin
        event = JSON.parse req.body
        yield event
        res.status = 201
      rescue
        res.status = 500
      end
    end
    server.start
  end

  def shutdown
    server.shutdown
  end
end
