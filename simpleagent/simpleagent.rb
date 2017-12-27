require 'singleton'
require 'thread'
require 'concurrent'
require 'jmespath'
require_relative 'dsl'
require_relative 'state'
require_relative 'broker'
require_relative 'config'
require_relative 'http_event_receiver'
require_relative 'http_listener'

Thread.abort_on_exception = true

class SimpleAgent
  include Singleton

  attr_accessor :tasks, :state, :lock, :broker, :http_listener,
                :http_event_receiver, :running, :event_queue,
                :name

  def initialize
    self.tasks = []
    self.state = State.new
    self.lock = Mutex.new
    self.http_listener = HttpListener.new port: config.get(:http_port)
    self.http_event_receiver = HttpEventReceiver.new http_listener: http_listener
    self.broker = Broker.instance
    self.running = false
    self.name = Config.get :name
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
      res.content_type = 'application/json'
    end
  end

  def periodically &blk
    task_config = { execution_interval: 10, timeout_interval: 10 }
    task = Concurrent::TimerTask.new(task_config) do
      lock.synchronize { blk.call state }
    end
    task.execute
    self.tasks << task
  end

  def start
    #puts "starting"
    self.running = true
    setup_event_queue
    load_state
    start_background_saver
    #start_background_loader
    start_http_listener
    #puts "Started with state: #{state}"
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
      self.state = state + StateLoader.load(State, state_path)
    else
      self.state = StateLoader.load(State, state_path)
    end
  end

  def save_state
    StateSaver.save(state, state_path)
  end

  def state_path
    "./state/#{name}"
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

at_exit do
  if $!
    puts "EXCEPTION: #{$!}"
  else
    SimpleAgent.instance.run!
  end
end
