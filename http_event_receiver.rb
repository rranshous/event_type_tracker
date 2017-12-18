require 'webrick'

class HttpEventReceiver
  attr_accessor :http_listener

  def initialize http_listener: nil
    self.http_listener = http_listener
  end

  def handle
    http_listener.add_listener('/event') do |req, res|
      begin
        event = JSON.parse req.body
        yield event
        res.status = 201
      rescue => ex
        puts "#{self.class.name}] Ex: #{ex}"
        res.status = 500
      end
    end
  end
end
