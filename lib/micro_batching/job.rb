# frozen_string_literal: true

require 'securerandom'

class MicroBatching::Job
  def initialize(data)
    @data = data
    @id = SecureRandom.uuid
  end

  attr_reader :data, :id
end
