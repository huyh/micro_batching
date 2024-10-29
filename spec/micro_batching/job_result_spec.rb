# frozen_string_literal: true

RSpec.describe MicroBatching::JobResult do
  describe '#initialize' do
    it 'sets the job id' do
      job_result = MicroBatching::JobResult.new('job-1')
      expect(job_result.job_id).to eq('job-1')
    end
  end
end
