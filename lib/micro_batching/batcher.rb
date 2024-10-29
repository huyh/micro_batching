# frozen_string_literal: true

require 'concurrent'

module MicroBatching
  class Batcher
    SUBMITTED = 'job-submitted'
    PROCESSING = 'job-processing'
    COMPLETED = 'job-completed'
    FAILED = 'job-failed'

    def initialize(batch_size:, max_queue_size: , frequency:, batch_processor:, event_broadcaster: nil)
      @batch_size = batch_size
      @max_queue_size = max_queue_size
      @frequency = frequency
      @batch_processor = batch_processor
      @event_broadcaster = event_broadcaster
      @jobs_queue = Thread::Queue.new
      @shutdown_requested = Concurrent::AtomicBoolean.new(false)
      start
    end

    def submit(job)
      if @shutdown_requested.true?
        raise MicroBatching::Errors::BatcherShuttingDownError.new('Batcher is shutting down')
      end

      if @jobs_queue.size >= @max_queue_size
        raise MicroBatching::Errors::QueueFullError.new('Queue is full')
      end

      @jobs_queue.push(job)
      broadcast_event_for_job(job, SUBMITTED)
      MicroBatching::JobResult.new(job.id)
    end

    def shutdown
      @shutdown_requested.make_true
      @timer_task.wait_for_termination
      true
    end

    private

    def start
      @timer_task = Concurrent::TimerTask.new(execution_interval: @frequency) do
        process_batch
      end
      @timer_task.execute
    end

    def process_batch
      batch = []

      @batch_size.times do
        break if @jobs_queue.empty?
        batch << @jobs_queue.pop
      end

      # Jobs may need to be transformed into a structure compatible with the batch processor
      if batch.any?
        broadcast_event_for_jobs(batch, PROCESSING)
        # TODO: process the result of the batch processor and broadcast appropriate events
        result = @batch_processor.process(batch)
        broadcast_event_for_jobs(batch, COMPLETED)
      end
    rescue StandardError => e
      broadcast_event_for_jobs(batch, FAILED, { error: e.message })
    ensure
      @timer_task.shutdown if @shutdown_requested.true? && @jobs_queue.empty?
    end

    def broadcast_event_for_jobs(jobs, event, data = {})
      if @event_broadcaster
        jobs.each { |job| broadcast_event_for_job(job, event, data) }
      end
    end

    def broadcast_event_for_job(job, event, data = {})
      @event_broadcaster&.broadcast(event, data.merge(id: job.id))
    end
  end
end
