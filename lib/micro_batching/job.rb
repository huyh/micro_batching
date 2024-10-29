# frozen_string_literal: true

require 'securerandom'

module MicroBatching
  # The Job class represents an individual job to be processed within a micro-batching system.
  # Each job instance is initialized with data and assigned a unique identifier.
  #
  # Example:
  #   job = MicroBatching::Job.new({ task: 'process_file', file_id: 123 })
  #
  # Attributes:
  # - data: [Object] Contains any data relevant to the job's processing.
  # - id: [String] A unique identifier for the job, automatically generated upon initialization.
  class Job
    # @return [Object] the data associated with the job
    attr_reader :data

    # @return [String] the unique identifier of the job
    attr_reader :id

    # Initializes a new Job instance with the specified data and generates a unique ID.
    #
    # @param data [Object] The data to be associated with this job.
    #
    # @return [MicroBatching::Job]
    def initialize(data)
      @data = data
      @id = SecureRandom.uuid
    end
  end
end
