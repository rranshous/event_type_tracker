class Broker
  include Singleton

  attr_accessor :subscribers, :to_send

  class Subscriber
    attr_accessor :callback, :criteria

    def initialize criteria, &blk
      self.criteria = criteria
      self.callback = blk
    end

    def call data
      self.callback.call data
    end

    def match? data
      self.criteria.match? data
    end
  end

  def initialize
    self.subscribers = []
    self.to_send = []
  end

  def subscribe criteria, &blk
    self.subscribers << Subscriber.new(criteria, &blk)
  end

  def publish data
    enqueue_event data
  end

  def event data = nil
    enqueue_event(data) unless data.nil?
    send_events
  end

  private

  def send_events
    while event_data = self.to_send.shift
      self.subscribers.select { |s| s.match? event_data }.each { |s| s.call event_data }
    end
  end

  def enqueue_event data
    self.to_send << data
  end
end

