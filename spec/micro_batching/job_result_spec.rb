# frozen_string_literal: true

RSpec.describe MicroBatching::JobResult do
  let(:event_broadcast) { double('event_broadcaster') }
  let(:job_result) { MicroBatching::JobResult.new('job-1', event_broadcast) }

  describe '#initialize' do
    it 'sets the job id' do
      expect(job_result.job_id).to eq('job-1')
    end

    it 'sets the status to queued' do
      expect(job_result.status).to eq(:queued)
    end

    it 'sets the event broadcaster' do
      expect(job_result.instance_variable_get(:@event_broadcaster)).to eq(event_broadcast)
    end
  end

  describe '#set_status' do
    before do
      allow(event_broadcast).to receive(:broadcast).with(job_result)
    end

    it 'sets the status' do
      job_result.set_status(:processing)
      expect(job_result.status).to eq(:processing)
    end

    it 'broadcasts the event' do
      expect(event_broadcast).to receive(:broadcast).with(job_result)
      job_result.set_status(:processing)
    end
  end
end
