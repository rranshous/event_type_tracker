require 'singleton'
require 'thread'
require 'concurrent'
require 'jmespath'

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

class Condition
  attr_accessor :query

  def initialize query
    self.query = query
  end

  def match? data
    r = JMESPath.search query, data
    r
  end

  def to_s
    "<#{self.class.name} #{query}>"
  end
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

class SimpleAgent
  include Singleton

  attr_accessor :tasks, :state, :lock, :broker, :http_listener, :http_event_receiver, :running, :event_queue

  def initialize
    self.tasks = []
    self.state = State.new
    self.lock = Mutex.new
    self.http_listener = HttpListener.new
    self.http_event_receiver = HttpEventReceiver.new http_listener: http_listener
    self.broker = Broker.instance
    self.running = false
  end

  def subscribe criteria, &blk
    broker.subscribe(criteria) do |event|
      lock.synchronize { blk.call event, state }
    end
  end

  def handle action, &blk
    http_listener.add_listener("/action/#{action}") do |req, res|
      response = blk.call state
      res.body = JSON.dump(response)
      res.status = 200
    end
  end

  def periodically &blk
    task = Concurrent::TimerTask.new(execution_interval: 10, timeout_interval: 10) do
      blk.call state
    end
    task.execute
    self.tasks << task
  end

  def start
    puts "starting"
    self.running = true
    setup_event_queue
    start_http_listener
    load_state
    start_background_saver
    puts "Started with state: #{state}"
  end

  def tick
    event_data = event_queue.pop(true)
    puts "queue length: #{event_queue.length}"
    Broker.instance.event event_data
    :SUCCESS
  rescue ThreadError
    :NO_EVENTS
  end

  def run!
    puts "running!"
    trap 'SIGINT' do stop end;
    start
    while running
      case tick
      when :NO_EVENTS
        sleep 0.1
      end
    end
  end

  def stop
    puts "shutting down"
    running = false
    stop_http_listener
    stop_background_tasks
    save_state
  end

  def load_state
    self.state = StateLoader.load(State)
  end

  def save_state
    path = StateSaver.save(state)
    puts "saved: #{path}"
  end

  def start_background_saver
    # load up some state for the agent
    load_state
    periodically do |state|
      save_state
    end
  end

  private

  def start_http_listener
    http_listener.start!
  end

  def stop_http_listener
    http_listener.shutdown
  end

  def stop_background_tasks
    tasks.each(&:shutdown)
  end

  def setup_event_queue
    self.event_queue = SizedQueue.new(10)
    http_event_receiver.handle do |event_data|
      puts "adding event: #{event_data}"
      event_queue << event_data
    end
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
