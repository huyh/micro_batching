# frozen_string_literal: true

require 'concurrent'

class MicroBatching::Batcher
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

    job_result = MicroBatching::JobResult.new(job.id, @event_broadcaster)
    @jobs_queue.push({ job: job, result: job_result })
    job_result
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
    jobs = []
    results = []

    @batch_size.times do
      break if @jobs_queue.empty?

      job_item = @jobs_queue.pop
      jobs << job_item[:job]
      results << job_item[:result]
    end

    # Jobs may need to be transformed into a structure compatible with the batch processor
    if jobs.any?
      # TODO: Ensure that job result statuses are accurately updated according to the outcomes returned by the BatchProcessor.
      @batch_processor.process(jobs)
      results.each { |result| result.set_status(:completed) }
    end
  rescue StandardError => e
    results.each { |result| result.set_status(:failed, e.message) }
  ensure
    @timer_task.shutdown if @shutdown_requested.true? && @jobs_queue.empty?
  end
end
