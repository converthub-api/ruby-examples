#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'optparse'

Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

def format_file_size(bytes)
  return '0 B' if bytes == 0
  units = ['B', 'KB', 'MB', 'GB', 'TB']
  index = [0, [4, (Math.log(bytes) / Math.log(1024)).floor].min].max
  size = bytes.to_f / (1024 ** index)
  "#{size.round(2)} #{units[index]}"
end

def check_status(job_id, watch = false)
  unless API_KEY
    puts "Error: CONVERTHUB_API_KEY is not set".red
    exit 1
  end

  puts "Job Status - ConvertHub API"
  puts "=" * 28
  puts "Job ID: #{job_id}"
  puts "-" * 50 + "\n"

  headers = { 'Authorization' => "Bearer #{API_KEY}" }

  begin
    loop do
      puts "→ Checking job status..."
      
      response = HTTParty.get("#{API_BASE_URL}/jobs/#{job_id}", headers: headers)
      
      if response.code >= 400
        error_data = JSON.parse(response.body) rescue {}
        error = error_data['error'] || {}
        puts "\n✗ Error: #{error['message'] || 'Job not found'}".red
        puts "  Code: #{error['code']}" if error['code']
        exit 1
      end

      job = JSON.parse(response.body)
      job = job.first if job.is_a?(Array)
      status = job['status'] || 'unknown'

      puts "\nStatus: #{status.capitalize}".send(
        status == 'completed' ? :green : 
        status == 'failed' ? :red : 
        status == 'cancelled' ? :yellow : :cyan
      )

      if status == 'completed' && job['result']
        result = job['result']
        puts "\n" + "-" * 50
        puts "Conversion Details:"
        puts "  Source format: #{job['source_format']&.upcase || 'N/A'}"
        puts "  Target format: #{result['format']}"
        puts "  File size: #{format_file_size(result['file_size'])}"
        puts "  Processing time: #{job['processing_time']}" if job['processing_time']
        puts "\nDownload URL:"
        puts "  #{result['download_url']}"
        puts "\nExpires: #{result['expires_at']}"
        puts "\n" + "-" * 50
        puts "Actions:"
        puts "  Download: ruby job-management/download-result.rb #{job_id}"
        puts "  Delete: ruby job-management/delete-file.rb #{job_id}"
        break
      elsif status == 'failed'
        puts "\nConversion failed"
        puts "Error: #{job['error']['message']}" if job['error']
        break
      elsif status == 'cancelled'
        puts "\nJob was cancelled"
        break
      elsif watch && ['processing', 'queued', 'pending'].include?(status)
        print "\nWaiting for completion"
        10.times do
          sleep(1)
          print "."
        end
        puts "\n"
      else
        break
      end
    end
  rescue => e
    puts "\n✗ Unexpected error: #{e.message}".red
    exit 1
  end
end

if __FILE__ == $0
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby check-status.rb [options] <job_id>"
    opts.on("--watch", "Watch status until completion") { options[:watch] = true }
    opts.on("--api-key KEY", "Your API key") { |k| API_KEY = k }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end

  parser.parse!
  
  if ARGV.empty?
    puts parser
    exit 1
  end

  check_status(ARGV[0], options[:watch])
end
