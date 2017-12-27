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

def state_field name, kls, combiner=nil
  State.add_field name, kls, combiner
end

def periodically &blk
  SimpleAgent.instance.periodically(&blk)
end

def set name, value
  Config.set name.to_sym, value
end

