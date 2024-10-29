# frozen_string_literal: true

require 'securerandom'
require 'concurrent'

module MicroBatching
  class Batcher
    JOB_SUBMITTED = 'job-submitted'.freeze
    JOB_PROCESSING = 'job-processing'.freeze
    JOB_COMPLETED = 'job-completed'.freeze
    JOB_FAILED = 'job-failed'.freeze

    BATCHER_START = 'batcher-start'.freeze
    BATCHER_SHUTTING_DOWN = 'batcher-shutting-down'.freeze
    BATCHER_SHUTDOWN = 'batcher-shutdown'.freeze

    attr_reader :id

    def initialize(batch_size:, max_queue_size: , frequency:, batch_processor:, event_broadcaster: nil)
      @id = SecureRandom.uuid
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
      broadcast_event_for_job(job, JOB_SUBMITTED)
      MicroBatching::JobResult.new(job.id)
    end

    def shutdown
      broadcast_event(BATCHER_SHUTTING_DOWN, { id: @id })
      @shutdown_requested.make_true
      @timer_task.wait_for_termination
      broadcast_event(BATCHER_SHUTDOWN, { id: @id })
      true
    end

    private

    def start
      @timer_task = Concurrent::TimerTask.new(execution_interval: @frequency) do
        process_batch
      end
      @timer_task.execute

      broadcast_event(BATCHER_START, { id: @id })
    end

    def process_batch
      batch = []

      @batch_size.times do
        break if @jobs_queue.empty?
        batch << @jobs_queue.pop(true)
      end

      if batch.any?
        broadcast_event_for_jobs(batch, JOB_PROCESSING)
        # TODO: process the result of the batch processor and broadcast appropriate events
        result = @batch_processor.process(batch)
        broadcast_event_for_jobs(batch, JOB_COMPLETED)
      end
    rescue StandardError => e
      broadcast_event_for_jobs(batch, JOB_FAILED, { error: e.message })
    ensure
      @timer_task.shutdown if @shutdown_requested.true? && @jobs_queue.empty?
    end

    def broadcast_event(event, data)
      @event_broadcaster&.broadcast(event, data)
    end

    def broadcast_event_for_jobs(jobs, event, data = {})
      if @event_broadcaster
        jobs.each { |job| broadcast_event_for_job(job, event, data) }
      end
    end

    def broadcast_event_for_job(job, event, data = {})
      broadcast_event(event, data.merge(id: job.id))
    end
  end
end
