# frozen_string_literal: true

RSpec.describe MicroBatching::Job do
  describe '#initialize' do
    it 'sets the data' do
      job = MicroBatching::Job.new('data')
      expect(job.data).to eq('data')
    end

    it 'sets the id' do
      job = MicroBatching::Job.new('data')
      expect(job.id).not_to be_nil
    end
  end
end
