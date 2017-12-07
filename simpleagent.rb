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
    r = JMESPath.search query, data
    puts "condition match? [#{query}] :: #{data} == #{r}"
    r
  end

  def to_s
    "<#{self.class.name} #{query}>"
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

  attr_accessor :subscribers, :to_send

  class Subscriber
    attr_accessor :callback, :criteria

    def initialize criteria, &blk
      self.criteria = criteria
      self.callback = blk
    end

    def call data
      puts "subscriber calling [#{criteria}] :: #{data}"
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

  def event data
    enqueue_event data
    send_events
  end

  private

  def send_events
    while event_data = self.to_send.shift
      puts "shifted: #{event_data}"
      self.subscribers.select { |s| s.match? event_data }.each { |s| s.call event_data }
    end
  end

  def enqueue_event data
    puts "enqueued #{data}"
    self.to_send << data
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
    subscribe Condition.new("action.request == '#{action}'") do |event|
      puts "Simple handling action request: #{action} :: #{event}"
      response = blk.call state
      broker.publish({ 'action' => { 'response' => action }, 'response' => response })
    end
  end

  def periodically &blk
    task = Concurrent::TimerTask.new(execution_interval: 10, timeout_interval: 5) do
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

STATE_DIR = './state'
class StateLoader
  def self.load state_class
    states = Dir.glob("#{STATE_DIR}/*.rmarshal").map do |file_path|
      Marshal.load File.read(file_path)
    end
    state = states.reduce(&:+)
    state || state_class.new
  end
end

class StateSaver
  def self.save state_object
    pid = Process.pid
    @time ||= Time.now.to_f
    filename = Pathname.new File.join(STATE_DIR, "#{@time}-#{pid}.rmarshal")
    File.open(filename, 'wb') do |fh|
      fh.write Marshal.dump(state_object)
    end
    filename
  end
end
