#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'ruby-progressbar'
require 'optparse'
require 'digest'

# Load environment variables
Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

class ChunkedUploader
  def initialize(api_key, base_url)
    @api_key = api_key
    @base_url = base_url
  end

  def format_file_size(bytes)
    return '0 B' if bytes == 0
    
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    index = [0, [4, (Math.log(bytes) / Math.log(1024)).floor].min].max
    size = bytes.to_f / (1024 ** index)
    
    "#{size.round(2)} #{units[index]}"
  end

  def upload_large_file(input_file, target_format, options = {})
    # Check if API key is set
    unless @api_key
      puts "Error: CONVERTHUB_API_KEY is not set".red
      puts "Get your API key at: https://converthub.com/api"
      puts "\nSet it in .env file or use --api-key parameter"
      exit 1
    end

    # Validate input file
    unless File.exist?(input_file)
      puts "Error: File '#{input_file}' not found.".red
      exit 1
    end

    file_size = File.size(input_file)
    chunk_size_mb = options[:chunk_size] || 5  # Default 5MB chunks
    chunk_size = chunk_size_mb * 1024 * 1024
    total_chunks = (file_size.to_f / chunk_size).ceil

    puts "\nChunked Upload - ConvertHub API"
    puts "=" * 32
    puts "File: #{File.basename(input_file)} (#{format_file_size(file_size)})"
    puts "Target format: #{target_format}"
    puts "Chunk size: #{chunk_size_mb} MB"
    puts "Total chunks: #{total_chunks}"
    puts "-" * 50 + "\n"

    begin
      headers = {
        'Authorization' => "Bearer #{@api_key}"
      }

      # Step 1: Initialize upload session
      puts "→ Initializing upload session..."

      init_data = {
        filename: File.basename(input_file),
        file_size: file_size,
        chunk_size: chunk_size,
        total_chunks: total_chunks,
        file_hash: calculate_file_hash(input_file)
      }

      init_response = HTTParty.post(
        "#{@base_url}/upload/init",
        headers: headers.merge('Content-Type' => 'application/json'),
        body: init_data.to_json
      )

      if init_response.code >= 400
        handle_error(init_response)
        exit 1
      end

      session_data = JSON.parse(init_response.body)
      session_id = session_data['session_id']
      
      puts "✓ Session created: #{session_id}".green
      puts "  Expires at: #{session_data['expires_at']}"

      # Step 2: Upload chunks
      puts "\n→ Uploading chunks..."
      
      start_time = Time.now
      progressbar = ProgressBar.create(
        title: "Uploading",
        total: total_chunks,
        format: "%t: %p%% |%B| %c/%C chunks [%E]"
      )

      File.open(input_file, 'rb') do |file|
        total_chunks.times do |chunk_index|
          chunk_data = file.read(chunk_size)
          
          chunk_form = {
            chunk: {
              filename: "chunk_#{chunk_index}",
              type: 'application/octet-stream',
              tempfile: StringIO.new(chunk_data)
            }
          }

          chunk_response = HTTParty.post(
            "#{@base_url}/upload/#{session_id}/chunks/#{chunk_index}",
            headers: headers,
            body: { chunk: chunk_data }
          )

          if chunk_response.code >= 400
            progressbar.stop
            puts "\n✗ Failed to upload chunk #{chunk_index}".red
            handle_error(chunk_response)
            exit 1
          end

          progressbar.increment
        end
      end

      progressbar.finish
      elapsed = (Time.now - start_time).round
      puts "\n✓ All chunks uploaded successfully in #{elapsed} seconds".green

      # Step 3: Complete upload and start conversion
      puts "\n→ Finalizing upload and starting conversion..."

      # Prepare conversion options
      conversion_options = {}
      options.each do |key, value|
        unless [:api_key, :output, :chunk_size, :webhook].include?(key)
          conversion_options[key] = value
        end
      end

      complete_data = {
        target_format: target_format,
        options: conversion_options
      }

      complete_data[:webhook_url] = options[:webhook] if options[:webhook]

      complete_response = HTTParty.post(
        "#{@base_url}/upload/#{session_id}/complete",
        headers: headers.merge('Content-Type' => 'application/json'),
        body: complete_data.to_json
      )

      if complete_response.code >= 400
        handle_error(complete_response)
        exit 1
      end

      completion = JSON.parse(complete_response.body)
      job_id = completion['job_id']

      puts "✓ Upload complete! Conversion started.".green
      puts "  Job ID: #{job_id}"

      # Step 4: Monitor conversion progress
      print "\n→ Converting"
      
      attempts = 0
      max_attempts = 180  # 6 minutes for large file conversions
      status = 'processing'
      job_status = nil

      while ['processing', 'queued', 'pending'].include?(status) && attempts < max_attempts
        sleep(2)
        attempts += 1
        print "."

        status_response = HTTParty.get(
          "#{@base_url}/jobs/#{job_id}",
          headers: headers
        )

        if status_response.code >= 400
          puts "\n✗ Failed to check status".red
          exit 1
        end

        job_status = JSON.parse(status_response.body)
        status = job_status['status'] || 'processing'
      end

      puts "\n"

      # Step 5: Handle results
      if status == 'completed' && job_status['result'] && job_status['result']['download_url']
        puts "✓ Conversion complete!\n".green
        
        total_time = (Time.now - start_time).round
        
        puts "-" * 50
        puts "Results:"
        
        result = job_status['result']
        puts "  Download URL: #{result['download_url']}"
        puts "  Format: #{result['format']}"
        puts "  Size: #{format_file_size(result['file_size'])}"
        puts "  Processing time: #{job_status['processing_time']}" if job_status['processing_time']
        puts "  Total time: #{total_time} seconds"
        puts "  Expires: #{result['expires_at']}"

        # Download file if output specified
        output_file = options[:output]
        if output_file
          download_file(result['download_url'], output_file)
        elsif !options[:webhook]
          print "\nDownload converted file? (y/n): "
          answer = gets.chomp
          if answer.downcase == 'y'
            output_file = "converted_#{Time.now.to_i}.#{target_format}"
            download_file(result['download_url'], output_file)
          end
        end
      elsif status == 'failed'
        puts "✗ Conversion failed".red
        if job_status['error']
          puts "Error: #{job_status['error']['message'] || 'Unknown error'}"
        end
        exit 1
      else
        puts "✗ Timeout: Conversion is taking longer than expected".red
        puts "Large files may take more time to process."
        puts "Check status with: ruby job-management/check-status.rb #{job_id}"
        
        if options[:webhook]
          puts "You will receive a webhook notification when complete."
        end
        exit 1
      end

    rescue => e
      puts "\n✗ Unexpected error: #{e.message}".red
      puts e.backtrace if ENV['DEBUG']
      exit 1
    end
  end

  private

  def calculate_file_hash(file_path)
    Digest::SHA256.file(file_path).hexdigest
  end

  def handle_error(response)
    begin
      error_data = JSON.parse(response.body)
      error = error_data['error'] || {}
      puts "✗ Error: #{error['message'] || 'Unknown error'}".red
      puts "  Code: #{error['code']}" if error['code']
      if error['details']
        error['details'].each do |key, value|
          puts "  #{key}: #{value}"
        end
      end
    rescue
      puts "✗ Error: HTTP #{response.code}".red
      puts "  Response: #{response.body}"
    end
  end

  def download_file(url, output_file)
    puts "\nDownloading to: #{output_file}"
    
    response = HTTParty.get(url)
    
    if response.code == 200
      File.open(output_file, 'wb') do |file|
        file.write(response.body)
      end
      
      file_size = File.size(output_file)
      puts "✓ File saved: #{output_file} (#{format_file_size(file_size)})".green
    else
      puts "✗ Download failed".red
    end
  end
end

# Main execution
if __FILE__ == $0
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby upload-large-file.rb [options] <input_file> <target_format>"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby upload-large-file.rb large-video.mp4 webm"
    opts.separator "  ruby upload-large-file.rb document.pdf docx --chunk-size=10"
    opts.separator "  ruby upload-large-file.rb archive.zip tar.gz --output=converted.tar.gz"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--api-key KEY", "Your API key") do |key|
      options[:api_key] = key
    end

    opts.on("--chunk-size SIZE", Integer, "Chunk size in MB (default: 5)") do |size|
      options[:chunk_size] = size
    end

    opts.on("--quality VALUE", Integer, "Output quality (1-100)") do |q|
      options[:quality] = q
    end

    opts.on("--resolution VALUE", "Output resolution (e.g., 1920x1080)") do |r|
      options[:resolution] = r
    end

    opts.on("--bitrate VALUE", "Audio/video bitrate (e.g., 320k)") do |b|
      options[:bitrate] = b
    end

    opts.on("--webhook URL", "Webhook URL for notifications") do |w|
      options[:webhook] = w
    end

    opts.on("--output FILE", "Output filename") do |o|
      options[:output] = o
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end

  parser.parse!

  if ARGV.length < 2
    puts parser
    exit 1
  end

  input_file = ARGV[0]
  target_format = ARGV[1].downcase

  # Override API key if provided
  api_key = options[:api_key] || API_KEY

  uploader = ChunkedUploader.new(api_key, API_BASE_URL)
  uploader.upload_large_file(input_file, target_format, options)
end