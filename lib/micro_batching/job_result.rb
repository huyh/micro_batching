# frozen_string_literal: true

class MicroBatching::JobResult
  VALID_STATUS = %i[queued processing completed failed].freeze

  attr_reader :job_id, :status, :error

  def initialize(job_id, event_broadcaster=nil)
    @job_id = job_id
    @event_broadcaster = event_broadcaster
    @status = :queued
  end

  def set_status(status, error=nil)
    raise ArgumentError, "Invalid status: #{status}" unless VALID_STATUS.include?(status)

    @status = status
    @error = error
    @event_broadcaster&.broadcast(self)
  end
end
