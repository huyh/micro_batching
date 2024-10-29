# frozen_string_literal: true

module MicroBatching
  # The JobResult class represents the result of processing a job in a micro-batching context.
  # It includes the job ID associated with this result, which can be used to reference the original job.
  #
  # Example:
  #   result = MicroBatching::JobResult.new(job.id)
  #
  # Attributes:
  # - job_id: The unique identifier of the job associated with this result.
  class JobResult
    # Initializes a new JobResult instance with the given job ID.
    #
    # @param job_id [String] The ID of the job for which this result is created.
    #
    # @return [MicroBatching::JobResult]
    def initialize(job_id)
      @job_id = job_id
    end

    # @return [String] the ID of the job associated with this result
    attr_reader :job_id
  end
end
