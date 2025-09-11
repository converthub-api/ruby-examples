#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'ruby-progressbar'
require 'optparse'
require 'pathname'

# Load environment variables
Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

class FileConverter
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

  def convert_file(input_file, target_format, options = {})
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
    file_size_mb = file_size / 1048576.0

    # Check file size limit (50MB for simple upload)
    if file_size_mb > 50
      puts "Error: File size (#{file_size_mb.round(2)} MB) exceeds 50MB limit.".red
      puts "Use chunked-upload/upload-large-file.rb for larger files."
      exit 1
    end

    puts "Simple Convert - ConvertHub API"
    puts "=" * 32
    puts "File: #{File.basename(input_file)} (#{format_file_size(file_size)})"
    puts "Target format: #{target_format}"

    if options.any? { |k, _| ![:api_key, :output].include?(k) }
      puts "\nOptions:"
      options.each do |key, value|
        puts "  #{key}: #{value}" unless [:api_key, :output].include?(key)
      end
    end

    puts "-" * 50 + "\n"

    begin
      # Step 1: Upload file and convert
      puts "→ Uploading and converting file..."

      headers = {
        'Authorization' => "Bearer #{@api_key}"
      }

      # Prepare conversion options
      conversion_options = {}
      options.each do |key, value|
        unless [:api_key, :output].include?(key)
          conversion_options[key] = value
        end
      end

      # Prepare form data
      form_data = {
        file: File.open(input_file, 'rb'),
        target_format: target_format
      }

      # Add options as JSON if present
      form_data[:options] = conversion_options.to_json if conversion_options.any?

      response = HTTParty.post(
        "#{@base_url}/convert",
        headers: headers,
        body: form_data
      )

      if response.code >= 400
        handle_error(response)
        exit 1
      end

      job = JSON.parse(response.body)
      job_id = job['job_id']
      status = job['status'] || 'processing'

      puts "✓ Conversion job created: #{job_id}".green

      # Check if already completed (from cache)
      if status == 'completed' && job['result']
        puts "✓ Using cached result (instant conversion)\n".green
        job_status = job
      else
        # Step 2: Monitor progress
        puts ""
        print "→ Converting"
        
        attempts = 0
        max_attempts = 60  # 2 minutes for simple conversions
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
      end

      # Step 3: Handle results
      if status == 'completed' && job_status['result'] && job_status['result']['download_url']
        puts "✓ Conversion complete!\n".green
        puts "-" * 50
        puts "Results:"
        
        result = job_status['result']
        puts "  Download URL: #{result['download_url']}"
        puts "  Format: #{result['format']}"
        puts "  Size: #{format_file_size(result['file_size'])}"
        puts "  Processing time: #{job_status['processing_time']}" if job_status['processing_time']
        puts "  Expires: #{result['expires_at']}"

        # Download file if output specified
        output_file = options[:output]
        if output_file
          download_file(result['download_url'], output_file)
        end
      elsif status == 'failed'
        puts "✗ Conversion failed".red
        if job_status['error']
          puts "Error: #{job_status['error']['message'] || 'Unknown error'}"
        end
        exit 1
      else
        puts "✗ Timeout: Conversion is taking longer than expected".red
        puts "Check status with: ruby job-management/check-status.rb #{job_id}"
        exit 1
      end

    rescue => e
      puts "\n✗ Unexpected error: #{e.message}".red
      exit 1
    end
  end

  private

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
    opts.banner = "Usage: ruby convert.rb [options] <input_file> <target_format>"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby convert.rb document.pdf docx"
    opts.separator "  ruby convert.rb image.png jpg --quality=85"
    opts.separator "  ruby convert.rb video.mp4 webm --output=converted.webm"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--api-key KEY", "Your API key") do |key|
      options[:api_key] = key
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

    opts.on("--sample-rate VALUE", Integer, "Audio sample rate") do |s|
      options[:sample_rate] = s
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

  converter = FileConverter.new(api_key, API_BASE_URL)
  converter.convert_file(input_file, target_format, options)
end