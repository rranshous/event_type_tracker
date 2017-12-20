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

