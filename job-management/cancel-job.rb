#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'optparse'

Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

def cancel_job(job_id, force = false)
  unless API_KEY
    puts "Error: CONVERTHUB_API_KEY is not set".red
    exit 1
  end

  puts "Cancel Job - ConvertHub API"
  puts "=" * 27
  puts "Job ID: #{job_id}"
  puts "-" * 50 + "\n"

  headers = { 'Authorization' => "Bearer #{API_KEY}" }

  begin
    puts "→ Retrieving job information..."
    
    response = HTTParty.get("#{API_BASE_URL}/jobs/#{job_id}", headers: headers)
    
    if response.code >= 400
      error_data = JSON.parse(response.body) rescue {}
      error = error_data['error'] || {}
      puts "\n✗ Error: #{error['message'] || 'Job not found'}".red
      exit 1
    end

    job = JSON.parse(response.body)
    job = job.first if job.is_a?(Array)
    status = job['status'] || 'unknown'

    if status == 'completed'
      puts "\n⚠️  Job already completed".yellow
      puts "The conversion has finished successfully."
      exit 0
    elsif status == 'failed'
      puts "\n⚠️  Job already failed".yellow
      exit 0
    elsif status == 'cancelled'
      puts "\n⚠️  Job already cancelled".yellow
      exit 0
    end

    puts "\nCurrent status: #{status.capitalize}".cyan
    
    if job['source_format'] && job['target_format']
      puts "Conversion: #{job['source_format'].upcase} → #{job['target_format'].upcase}"
    end

    unless force
      puts "\nWarning: This action cannot be undone.".yellow
      print "Are you sure you want to cancel this job? (y/n): "
      answer = gets.chomp
      unless answer.downcase == 'y'
        puts "\n✗ Cancellation aborted"
        exit 0
      end
    end

    puts "\n→ Cancelling job..."
    
    cancel_response = HTTParty.delete("#{API_BASE_URL}/jobs/#{job_id}", headers: headers)
    
    if cancel_response.code == 200 || cancel_response.code == 204
      puts "\n✓ Job cancelled successfully".green
      result = JSON.parse(cancel_response.body) rescue {}
      puts "  #{result['message']}" if result['message']
    else
      error_data = JSON.parse(cancel_response.body) rescue {}
      error = error_data['error'] || {}
      puts "\n✗ Failed to cancel job".red
      puts "Error: #{error['message'] || 'Unknown error'}"
    end
    
  rescue => e
    puts "\n✗ Unexpected error: #{e.message}".red
    exit 1
  end
end

if __FILE__ == $0
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby cancel-job.rb [options] <job_id>"
    opts.on("--force", "Skip confirmation prompt") { options[:force] = true }
    opts.on("--api-key KEY", "Your API key") { |k| API_KEY = k }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end

  parser.parse!
  
  if ARGV.empty?
    puts parser
    exit 1
  end

  cancel_job(ARGV[0], options[:force])
end
