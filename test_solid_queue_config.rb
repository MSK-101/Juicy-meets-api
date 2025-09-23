#!/usr/bin/env ruby

# Test SolidQueue configuration
puts "Testing SolidQueue configuration..."

begin
  # Test if we can access SolidQueue models
  puts "Testing SolidQueue models..."
  puts "SolidQueue::Job count: #{SolidQueue::Job.count}"
  puts "SolidQueue::Process count: #{SolidQueue::Process.count}"

  # Test if we can enqueue a job
  puts "Testing job enqueueing..."
  SessionManagementJob.perform_later(1, { success: true, room_id: 'test_room' })
  puts "✅ Job enqueued successfully"

  # Check job count
  puts "Jobs in queue: #{SolidQueue::Job.count}"

  puts "🎉 SolidQueue configuration is working correctly!"

rescue => e
  puts "❌ Error: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5)
end
