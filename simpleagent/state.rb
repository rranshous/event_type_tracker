class State
  FIELDS = {}

  def self.add_field name, initial_value, combiner=nil
    attr_accessor name
    combiner ||= lambda { |s,o|
      if s.nil? && o.nil?
        nil
      elsif s.nil?
        o
      elsif o.nil?
        s
      else
        s + o
      end
    }
    FIELDS[name.to_sym] = OpenStruct.new(initial_value: initial_value,
                                         combiner: combiner)
  end

  def initialize
    FIELDS.each do |name, opts|
      self.send "#{name}=", opts.initial_value
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
    FIELDS.each do |name, opts|
      my_value = self.send name
      other_value = other.send name
      new_obj.send "#{name}=", opts.combiner.call(my_value, other_value)
    end
    new_obj
  end
end

class StateLoader
  def self.load state_class, state_dir='./state'
    states = Dir.glob("#{state_dir}/*.rmarshal").map do |file_path|
      begin
        Marshal.load File.read(file_path)
      rescue ArgumentError
        nil
      end
    end.compact
    state = states.reduce(&:+)
    state = state || state_class.new
    #puts "loaded: #{state}"
    state
  end
end

class StateSaver
  def self.save state_object, state_dir='./state'
    #puts "saving: #{state_object}"
    pid = Process.pid
    @time ||= Time.now.to_f
    FileUtils.mkdir_p state_dir
    filename = Pathname.new File.join(state_dir, "#{@time}-#{pid}.rmarshal")
    File.open(filename, 'wb') do |fh|
      fh.write Marshal.dump(state_object)
    end
    filename
  end
end
