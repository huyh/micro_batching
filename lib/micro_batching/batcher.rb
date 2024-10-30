# frozen_string_literal: true

require 'securerandom'
require 'concurrent'

module MicroBatching
  # The Batcher class handles micro-batching for job processing, grouping jobs and submitting them to
  # a batch processor in batches. It supports job submission, scheduled batch processing, and an optional
  # event broadcasting mechanism for monitoring batch and job status.
  #
  # Constants:
  # - JOB_SUBMITTED: Broadcasted when a job is submitted.
  # - JOB_PROCESSING: Broadcasted when a batch of jobs starts processing.
  # - JOB_COMPLETED: Broadcasted when a batch of jobs completes processing.
  # - JOB_FAILED: Broadcasted if a batch processing fails.
  # - BATCHER_START: Broadcasted when the batcher is started.
  # - BATCHER_SHUTTING_DOWN: Broadcasted when the batcher begins shutting down.
  # - BATCHER_SHUTDOWN: Broadcasted when the batcher has shut down.
  #
  # Example:
  #   batcher = MicroBatching::Batcher.new(
  #     batch_size: 10, max_queue_size: 100, frequency: 5, batch_processor: processor
  #   )
  #   batcher.submit(job)
  #   batcher.shutdown
  class Batcher
    JOB_SUBMITTED = 'job-submitted'.freeze
    JOB_PROCESSING = 'job-processing'.freeze
    JOB_COMPLETED = 'job-completed'.freeze
    JOB_FAILED = 'job-failed'.freeze

    BATCHER_START = 'batcher-start'.freeze
    BATCHER_SHUTTING_DOWN = 'batcher-shutting-down'.freeze
    BATCHER_SHUTDOWN = 'batcher-shutdown'.freeze

    # @return [String] the unique identifier of the batcher
    attr_reader :id

    # Initializes a new Batcher instance.
    #
    # @param batch_size [Integer] The number of jobs to process in each batch.
    # @param max_queue_size [Integer] The maximum number of jobs allowed in the queue.
    # @param frequency [Float] The interval (in seconds) for processing batches.
    # @param batch_processor [Object] The processor that handles job batches.
    # @param event_broadcaster [Object, nil] An optional broadcaster for job and batch status updates.
    # @param result_converter [Object, nil] An optional converter that transforms the result returned
    # by the batch_processor's process function into an array format, such as [true, { error: 'An error message' }, ...].
    # For example, a bulk insert request to BigQuery will returns in the following format:
    # {
    #   "kind": "bigquery#tableDataInsertAllResponse",
    #   "insertErrors": [
    #     {
    #       "index": 0,
    #       "errors": [
    #         {
    #           "reason": "invalid",
    #           "location": "field_name",
    #           "debugInfo": "Detailed error message",
    #           "message": "Specific error message describing the failure"
    #         }
    #       ]
    #     }
    #   ]
    # }
    #
    # @return [MicroBatching::Batcher]
    def initialize(batch_size:, max_queue_size:, frequency:, batch_processor:, event_broadcaster: nil, result_converter: nil)
      @id = SecureRandom.uuid
      @batch_size = batch_size
      @max_queue_size = max_queue_size
      @frequency = frequency
      @batch_processor = batch_processor
      @event_broadcaster = event_broadcaster
      @result_converter = result_converter
      @jobs_queue = Thread::Queue.new
      @shutdown = Concurrent::AtomicBoolean.new(false)
      start
    end

    # Submits a job to the batcher for processing.
    #
    # @param job [Object] The job to be submitted.
    #
    # @raise [MicroBatching::Errors::BatcherShuttingDownError] if the batcher is shutting down.
    # @raise [MicroBatching::Errors::QueueFullError] if the queue is at maximum capacity.
    #
    # @return [MicroBatching::JobResult] The job result object associated with the job.
    def submit(job)
      if @shutdown.true?
        raise MicroBatching::Errors::BatcherShuttingDownError.new('Batcher is shutting down')
      end

      if @jobs_queue.size >= @max_queue_size
        raise MicroBatching::Errors::QueueFullError.new('Queue is full')
      end

      @jobs_queue.push(job)
      broadcast_event_for_job(job, JOB_SUBMITTED)
      MicroBatching::JobResult.new(job.id)
    end

    # Initiates the shutdown process for the batcher.
    #
    # No new jobs will be accepted after calling this method. The batcher will continue processing
    # remaining jobs in the queue until it is empty, then shut down.
    #
    # @return [Boolean] Returns true once all jobs are processed and the batcher is shut down.
    def shutdown
      broadcast_event(BATCHER_SHUTTING_DOWN, { id: @id })
      @shutdown.make_true
      @timer_task.wait_for_termination
      broadcast_event(BATCHER_SHUTDOWN, { id: @id })
      true
    end

    private

    # Starts the batch processing timer task, which triggers batch processing at the specified frequency.
    #
    # @return [void]
    def start
      @timer_task = Concurrent::TimerTask.new(execution_interval: @frequency) do
        process_batch
      end
      @timer_task.execute

      broadcast_event(BATCHER_START, { id: @id })
    end

    # Processes a batch of jobs from the queue, up to the configured batch size.
    #
    # Retrieves up to `batch_size` jobs from the queue, sends them to the batch processor,
    # and broadcasts job events indicating the processing status.
    #
    # @return [void]
    def process_batch
      batch = []

      @batch_size.times do
        break if @jobs_queue.empty?
        batch << @jobs_queue.pop(true)
      end

      if batch.any?
        broadcast_event_for_jobs(batch, JOB_PROCESSING)
        result = @batch_processor.process(batch)
        broadcast_events_for_processed_batch(batch, result)
      end
    rescue StandardError => e
      broadcast_event_for_jobs(batch, JOB_FAILED, { error: e.message })
    ensure
      @timer_task.shutdown if @shutdown.true? && @jobs_queue.empty?
    end

    # Broadcasts a general event through the event broadcaster, if available.
    #
    # @param event [String] The event name.
    # @param data [Hash] Additional data to include in the event broadcast.
    #
    # @return [void]
    def broadcast_event(event, data)
      @event_broadcaster&.broadcast(event, data)
    end


    # Broadcasts an event for each job in a batch.
    #
    # @param jobs [Array<MicroBatching::Job>] The jobs for which to broadcast the event.
    # @param event [String] The event name.
    # @param data [Hash] Additional data to include in each job's event.
    #
    # @return [void]
    def broadcast_event_for_jobs(jobs, event, data = {})
      if @event_broadcaster
        jobs.each { |job| broadcast_event_for_job(job, event, data) }
      end
    end

    # Broadcasts an event for a single job.
    #
    # @param job [MicroBatching::Job] The job for which to broadcast the event.
    # @param event [String] The event name.
    # @param data [Hash] Additional data to include in the event.
    #
    # @return [void]
    def broadcast_event_for_job(job, event, data = {})
      broadcast_event(event, data.merge(id: job.id))
    end

    # Broadcasts events for each job in a processed batch based on the processing result.
    #
    # If an event broadcaster is available, this method sends a `JOB_COMPLETED` or `JOB_FAILED` event
    # for each job in the batch, depending on the result of the batch processing. If a `result_converter`
    # is present, the processing result is first converted, where each converted result should be `true`
    # for success or a hash containing an `:error` key for failure.
    #
    # @param batch [Array<MicroBatching::Job>] The batch of jobs to process.
    # @param processed_batch_result [Object] The result returned from the batch processor, which is passed
    #   to the `result_converter` (if defined) to determine individual job outcomes.
    #
    # @return [void]
    def broadcast_events_for_processed_batch(batch, processed_batch_result)
      if @event_broadcaster
        if @result_converter
          converted_results = @result_converter.convert(processed_batch_result)

          converted_results.each_with_index do |result, index|
            if result == true
              broadcast_event_for_job(batch[index], JOB_COMPLETED)
            else
              broadcast_event_for_job(batch[index], JOB_FAILED, { error: result[:error] })
            end
          end
        else
          broadcast_event_for_jobs(batch, JOB_COMPLETED)
        end
      end
    end
  end
end
