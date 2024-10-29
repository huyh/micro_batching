# frozen_string_literal: true

module MicroBatching
  class JobResult
    attr_reader :job_id

    def initialize(job_id)
      @job_id = job_id
    end
  end
end
