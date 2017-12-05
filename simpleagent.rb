require 'singleton'
require 'thread'
require 'concurrent'
require 'jmespath'

class Condition
  attr_accessor :query

  def initialize query
    self.query = query
  end

  def match? data
    JMESPath.search query, data
  end
end

def where query_string, &blk
  # register ourselve as a subscriber to the queried events
  condition = Condition.new query_string
  SimpleAgent.instance.subscribe(condition, &blk)
end

def report report_name, &blk
  # register an report generator
  SimpleAgent.instance.handle(report_name, &blk)
end

def cleanup &blk
  # register a periodic task
  SimpleAgent.instance.periodically(&blk)
end

class Broker
  include Singleton

  attr_accessor :subscribers

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
  end

  def subscribe criteria, &blk
    self.subscribers << Subscriber.new(criteria, &blk)
  end

  def event data
    self.subscribers.select { |s| s.match? data }.each { |s| s.call data }
  end
end

class SimpleAgent
  include Singleton

  attr_accessor :tasks, :state, :lock, :broker

  def initialize
    self.tasks = []
    self.state = State.new
    self.lock = Mutex.new
  end

  def subscribe criteria, &blk
    broker.subscribe(criteria) do |event|
      lock.synchronize { blk.call event, state }
    end
  end

  def handle action, &blk
    # TODO
  end

  def periodically &blk
    task = Concurrent::TimerTask.new(execution_interval: 5, timeout_interval: 5) do
      puts "in concurrent"
      blk.call state
    end
    task.execute
    self.tasks << task
  end

  def broker
    Broker.instance
  end
end
