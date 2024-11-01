# MicroBatching Library

This Ruby library implements a micro-batching system designed for processing tasks in batches to optimize throughput and minimize individual requests to a downstream system. The library allows configurable batch size, frequency, and maximum queue size, providing flexibility for different workload requirements.

## Features

- **Micro-batching**: Groups jobs into small batches for efficient processing.
- **Configurable Batching**: Customize batch size, frequency of processing, and queue capacity.
- **Job Submission**: Submit individual jobs, which are processed in batches.
- **Graceful Shutdown**: Allows for orderly shutdown, processing remaining jobs before exit.
- **Job Status Updates**: Broadcasts job processing status updates to subscribers.

## Installation

To install this library, add it to your `Gemfile`:

```ruby
gem 'micro_batching', github: 'huyh/micro_batching'

# Then run:
bundle install
```

## Usage
### Initialization
Create a new instance of the MicroBatching::Batcher with the desired configuration:

```ruby
require 'micro_batching'

# The batch processor that processes the batch of jobs.
# This should be a class that implements a `process` method that takes an array of jobs.
batch_processor = YourBatchProcessor.new

# An optional event broadcaster that broadcasts job processing status updates to subscribers. 
# This can be used, for example, to publish job status updates to pub/sub channels.
# This should be a class that implements a `broadcast` method that takes 
# an event name and optional data.
event_broadcaster = YourEventBroadcaster.new

# An optional converter that transforms the result returned
# by the batch_processor's process function into an array format, 
# such as [true, { error: 'An error message' }, ...].
result_converter = YourResultConverter.new

batcher = MicroBatching::Batcher.new(
  batch_size: 10,
  max_queue_size: 50,
  frequency: 5,
  batch_processor: batch_processor,
  event_broadcaster: event_broadcaster,
  result_converter: result_converter
)
```

### Submitting Jobs
Submit jobs to the batcher for processing:

```ruby
job = YourJob.new('job data')  # Replace with your Job implementation
job_result = batcher.submit(job)
```
The submit method returns a `JobResult` object, which contains the job ID.

### Shutting Down
To shutdown the batcher, ensuring that all jobs in the queue are processed first:

```ruby
batcher.shutdown
```
## Error Handling
The library provides custom error classes:

`QueueFullError`: Raised if the job queue exceeds the maximum queue size.

`BatcherShuttingDownError`: Raised if a job is submitted while the batcher is shutting down.

## Example
Here's an example of how you might use this library in a real-world scenario:

```ruby
require 'securerandom'
require 'micro_batching'

class BatchProcessor
  def process(jobs)
    jobs.each do |job|
      puts "Processing job #{job.id} with data #{job.data}"
    end
    jobs
  end
end

class EventBroadcaster
  def broadcast(event, data)
    puts "Broadcasting event #{event} with data: #{data}"
  end
end

class ResultConverter
  def convert(results)
    results.map.with_index do |_result, index|
      index % 2 == 0 ? true : { error: 'Failed to process job' }
    end
  end
end

batch_processor = BatchProcessor.new
event_broadcaster = EventBroadcaster.new
result_converter = ResultConverter.new

batcher = MicroBatching::Batcher.new(
  batch_size: 10,
  max_queue_size: 50,
  frequency: 10,
  batch_processor: batch_processor,
  event_broadcaster: event_broadcaster,
  result_converter: result_converter
)

@stop_submitting_job = false

job_submitter_one = Thread.new do
  while !@stop_submitting_job
    sleep(1)
    job = MicroBatching::Job.new("job-submitter-one-#{SecureRandom.uuid}")
    batcher.submit(job)
  end
end

job_submitter_two = Thread.new do
  while !@stop_submitting_job
    sleep(2)
    job = MicroBatching::Job.new("job-submitter-two-#{SecureRandom.uuid}")
    batcher.submit(job)
  end
end

sleep(50)

@stop_submitting_job = true
job_submitter_one.join
job_submitter_two.join

shutdown = batcher.shutdown
puts "Batcher shutdown: #{shutdown}"
```

## Testing
To run the tests, execute the following command:

```bash
bundle exec rspec

or

bundle exec rake spec
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
