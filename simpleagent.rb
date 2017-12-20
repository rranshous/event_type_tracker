require 'singleton'
require 'thread'
require 'concurrent'
require 'jmespath'

Thread.abort_on_exception = true

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

def state_field name, kls
  State.add_field name, kls
end

def periodically &blk
  SimpleAgent.instance.periodically(&blk)
end

def set name, value
  Config.set name.to_sym, value
end


class State
  FIELDS = {}

  def self.add_field name, kls
    attr_accessor name
    FIELDS[name.to_sym] = kls
  end

  def initialize
    FIELDS.each do |name, kls|
      self.send "#{name}=", kls.new
    end
  end

  def to_s
    "<State #{FIELDS.keys.map{|f| "#{f}:#{self.send(f)}" }.join(',')}>"
  end

  def inspect
    inspect
  end

  def marshal_dump
    d = Hash[FIELDS.to_a.map do |(name, _)|
      [name, self.send(name)]
    end]
    d
  end

  def marshal_load data_hash
    FIELDS.each do |name, _|
      self.send "#{name}=", data_hash[name]
    end
  end

  def + other
    new_obj = self.class.new
    FIELDS.each do |name, kls|
      if kls == Array
        new_obj.send "#{name}=", self.send(name) + other.send(name)
      end
    end
    new_obj
  end
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

class Config
  include Singleton

  def initialize
    @config = {}
  end

  def self.get key
    self.instance.get key
  end

  def get key
    @config[key]
  end

  def self.set key, value
    self.instance.set key, value
  end

  def set key, value
    @config[key] = value
  end
end

class SimpleAgent
  include Singleton

  attr_accessor :tasks, :state, :lock, :broker, :http_listener,
                :http_event_receiver, :running, :event_queue

  def initialize
    self.tasks = []
    self.state = State.new
    self.lock = Mutex.new
    self.http_listener = HttpListener.new port: config.get(:http_port)
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
    task_config = { execution_interval: 10, timeout_interval: 10 }
    task = Concurrent::TimerTask.new(task_config) do
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
    start_background_loader
    puts "Started with state: #{state}"
  end

  def tick
    event_data = event_queue.pop(true)
    Broker.instance.event event_data
    :SUCCESS
  rescue ThreadError
    :NO_EVENTS
  end

  def run!
    trap 'SIGINT' do self.running = false end;
    start
    while running
      case tick
      when :NO_EVENTS
        sleep 0.1
      end
    end
    stop
  end

  def stop
    puts "shutting down"
    self.running = false
    stop_http_listener
    stop_background_tasks
    save_state
  end

  def start_background_saver
    periodically do |state|
      save_state
    end
  end

  def start_background_loader
    periodically do |state|
      load_state
    end
  end

  def load_state
    if state
      self.state = state + StateLoader.load(State)
    else
      self.state = StateLoader.load(State)
    end
  end

  def save_state
    StateSaver.save(state)
  end

  def config
    Config.instance
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
    state = state || state_class.new
    puts "loaded: #{state}"
    state
  end
end

class StateSaver
  def self.save state_object
    puts "saving: #{state_object}"
    pid = Process.pid
    @time ||= Time.now.to_f
    filename = Pathname.new File.join(STATE_DIR, "#{@time}-#{pid}.rmarshal")
    File.open(filename, 'wb') do |fh|
      fh.write Marshal.dump(state_object)
    end
    filename
  end
end

at_exit do
  if $!
    puts "EXCEPTION: #{$!}"
  else
    SimpleAgent.instance.run!
  end
end
