# frozen_string_literal: true

require 'securerandom'

module MicroBatching
  class Job
    def initialize(data)
      @data = data
      @id = SecureRandom.uuid
    end

    attr_reader :data, :id
  end
end
