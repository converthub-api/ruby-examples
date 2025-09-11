#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'optparse'
require 'ruby-progressbar'

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

def download_result(job_id, output_file = nil)
  unless API_KEY
    puts "Error: CONVERTHUB_API_KEY is not set".red
    exit 1
  end

  puts "Download Result - ConvertHub API"
  puts "=" * 32
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
      puts "  Code: #{error['code']}" if error['code']
      exit 1
    end

    job_response = JSON.parse(response.body)
    job = job_response.is_a?(Array) ? job_response.first : job_response
    
    status = job['status'] || 'unknown'
    
    if status != 'completed'
      puts "\n⚠️  File not available".yellow
      puts "Job status: #{status}"
      exit 1
    end

    result = job['result'] || {}
    download_url = result['download_url']
    
    unless download_url
      puts "\n✗ No download URL available".red
      exit 1
    end

    puts "\nFile Information:".cyan
    puts "  Format: #{result['format']&.upcase || 'N/A'}"
    puts "  Size: #{format_file_size(result['file_size'])}"
    puts "  Processing time: #{job['processing_time']}" if job['processing_time']
    puts "  Expires: #{result['expires_at']}"

    unless output_file
      format_ext = result['format'] || 'bin'
      metadata = job['metadata'] || {}
      original_name = 'converted'
      
      if metadata.is_a?(Hash) && metadata['original_filename']
        original_name = File.basename(metadata['original_filename'], '.*')
      end
      
      output_file = "#{original_name}_#{job_id[0..7]}.#{format_ext}"
    end

    puts "\nOutput file: #{output_file}"
    puts "\n→ Downloading file..."

    dl_response = HTTParty.get(download_url)
    
    if dl_response.code != 200
      puts "\n✗ Failed to download file".red
      exit 1
    end

    File.open(output_file, 'wb') do |file|
      file.write(dl_response.body)
    end
    actual_size = File.size(output_file)
    
    puts "\n✓ Download complete!".green
    puts "  File: #{output_file}"
    puts "  Size: #{format_file_size(actual_size)}"
    
  rescue => e
    puts "\n✗ Unexpected error: #{e.message}".red
    exit 1
  end
end

if __FILE__ == $0
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby download-result.rb [options] <job_id>"
    opts.on("--output FILE", "Output filename") { |o| options[:output] = o }
    opts.on("--api-key KEY", "Your API key") { |k| API_KEY = k }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end

  parser.parse!
  
  if ARGV.empty?
    puts parser
    exit 1
  end

  download_result(ARGV[0], options[:output])
end
