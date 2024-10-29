# frozen_string_literal: true

class MockBatchProcessor
  attr_reader :processed_jobs

  def initialize
    @processed_jobs = []
  end

  def process(jobs)
    jobs.each do |job|
      @processed_jobs << job
    end
  end
end

class MockEventBroadcaster
  attr_reader :events

  def initialize
    @events = []
  end

  def broadcast(event)
    @events << event
  end
end

def submit_jobs(batcher, count)
  Thread.new do
    count.times do |i|
      batcher.submit(MicroBatching::Job.new(i))
      sleep(0.001)
    end
  end
end

RSpec.describe MicroBatching::Batcher do
  let(:batch_processor) { MockBatchProcessor.new }
  let(:event_broadcaster) { MockEventBroadcaster.new }
  let(:batcher) {
    MicroBatching::Batcher.new(
      batch_size: 10,
      max_queue_size: 50,
      frequency: 0.02,
      batch_processor: batch_processor,
      event_broadcaster: event_broadcaster)
  }

  describe '#submit' do
    it 'pushes the given job to the queue' do
      job = MicroBatching::Job.new('data')

      expect {
        batcher.submit(job)
      }.to change { batcher.instance_variable_get(:@jobs_queue).size }.by(1)
    end

    it 'returns a JobResult object' do
      job = MicroBatching::Job.new('data')
      result = batcher.submit(job)

      expect(result).to be_a(MicroBatching::JobResult)
      expect(result.job_id).to eq(job.id)
    end

    context 'when shutdown is requested' do
      it 'raises a BatcherShuttingDownError' do
        batcher.shutdown
        expect { batcher.submit(MicroBatching::Job.new('data')) }.to raise_error(MicroBatching::Errors::BatcherShuttingDownError).with_message('Batcher is shutting down')
      end
    end

    context 'when the queue is full' do
      it 'raises a QueueFullError' do
        50.times do
          batcher.submit(MicroBatching::Job.new('data'))
        end

        expect { batcher.submit(MicroBatching::Job.new('data')) }.to raise_error(MicroBatching::Errors::QueueFullError).with_message('Queue is full')
      end
    end
  end

  describe '#shutdown' do
    it 'stops the timer task then returns true' do
      submit_jobs(batcher, 5)

      sleep(0.1)

      result = batcher.shutdown

      expect(batcher.instance_variable_get(:@timer_task)).not_to be_running
      expect(result).to be(true)
    end
  end

  describe 'jobs processing' do
    it 'processes the jobs in the queue by batches' do
      expect(batch_processor).to receive(:process).with(satisfy { |arg|
        arg.is_a?(Array) && arg.size > 0 && arg.size <= 10
      }).at_least(4).times

      submit_jobs(batcher, 31)

      sleep(0.2)
    end

    it 'processes all received jobs' do
      submit_jobs(batcher, 31)

      sleep(0.2)

      expect(batch_processor.processed_jobs.size).to eq(31)
    end

    it 'processes the jobs in the order they were received' do
      submit_jobs(batcher, 31)

      sleep(0.2)

      expect(batch_processor.processed_jobs.map(&:data)).to eq((0..30).to_a)
    end

    it 'updates the status of the job results to completed' do
      submit_jobs(batcher, 31)

      sleep(0.2)

      expect(event_broadcaster.events.size).to eq(31)
      expect(event_broadcaster.events.all? { |event| event.status == :completed }).to be(true)
    end

    context 'when shutdown is requested' do
      it 'ensures all received jobs are processed' do
        submit_jobs(batcher, 31)

        sleep(0.04)

        expect(batcher.instance_variable_get(:@jobs_queue)).not_to be_empty

        batcher.shutdown

        expect(batcher.instance_variable_get(:@jobs_queue)).to be_empty
      end
    end

    context 'when an error occurs during processing' do
      it 'updates the status of the job results to failed with the error message' do
        allow(batch_processor).to receive(:process).and_raise(StandardError.new('An error occurred'))

        submit_jobs(batcher, 31)

        sleep(0.2)

        expect(event_broadcaster.events.size).to eq(31)
        expect(event_broadcaster.events.all? { |event| event.status == :failed }).to be(true)
        expect(event_broadcaster.events.all? { |event| event.error == 'An error occurred' }).to be(true)
      end
    end
  end
end
