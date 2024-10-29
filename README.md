# MicroBatching Library

This Ruby library implements a micro-batching system designed for processing tasks in batches to optimize throughput and minimize individual requests to a downstream system. The library allows configurable batch size, frequency, and maximum queue size, providing flexibility for different workload requirements.

## Features

- **Micro-batching**: Groups jobs into small batches for efficient processing.
- **Configurable Batching**: Customize batch size, frequency of processing, and queue capacity.
- **Job Submission**: Submit individual jobs, which are processed in batches.
- **Graceful Shutdown**: Allows for orderly shutdown, processing remaining jobs before exit.
- **Job Status Updates**: Each job result is updated with success or failure status upon completion.

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
# This should be a class that implements a `broadcast` method that takes an event name and optional data.
event_broadcaster = YourEventBroadcaster.new

batcher = MicroBatching::Batcher.new(
  batch_size: 10,
  max_queue_size: 50,
  frequency: 5,
  batch_processor: batch_processor,
  event_broadcaster: event_broadcaster
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
require 'micro_batching'

class YourBatchProcessor
  def process(jobs)
    # Process the jobs here
  end
end

batch_processor = YourBatchProcessor.new

batcher = MicroBatching::Batcher.new(
  batch_size: 10,
  max_queue_size: 50,
  frequency: 5,
  batch_processor: batch_processor
)

# Submit jobs
100.times do |i|
  job = MicroBatching::Job.new("Job #{i}")
  batcher.submit(job)
end

# Shut down the batcher after processing all jobs
batcher.shutdown
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
