#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'uri'
require 'optparse'

# Load environment variables
Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

class UrlConverter
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

  def convert_from_url(url, target_format, options = {})
    # Check if API key is set
    unless @api_key
      puts "Error: CONVERTHUB_API_KEY is not set".red
      puts "Get your API key at: https://converthub.com/api"
      puts "\nSet it in .env file or use --api-key parameter"
      exit 1
    end

    # Validate URL
    begin
      uri = URI.parse(url)
      unless uri.scheme && uri.host
        raise "Invalid URL format"
      end
      
      filename = File.basename(uri.path).empty? ? 'file' : File.basename(uri.path)
    rescue => e
      puts "Error: Invalid URL - #{e.message}".red
      exit 1
    end

    puts "URL Convert - ConvertHub API"
    puts "=" * 29
    puts "URL: #{url}"
    puts "Filename: #{filename}"
    puts "Target format: #{target_format}"

    if options.any? { |k, _| ![:api_key, :output, :webhook].include?(k) }
      puts "\nOptions:"
      options.each do |key, value|
        puts "  #{key}: #{value}" unless [:api_key, :output, :webhook].include?(key)
      end
    end

    puts "-" * 50 + "\n"

    begin
      # Step 1: Submit URL for conversion
      puts "→ Submitting URL for conversion..."

      headers = {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json'
      }

      # Prepare request data
      request_data = {
        file_url: url,
        target_format: target_format,
        output_filename: filename
      }

      # Add webhook if provided
      webhook_url = options[:webhook]
      if webhook_url
        request_data[:webhook_url] = webhook_url
        puts "  Webhook: #{webhook_url}"
      end

      # Add conversion options
      conversion_options = {}
      options.each do |key, value|
        unless [:api_key, :output, :webhook].include?(key)
          conversion_options[key] = value
        end
      end
      request_data[:options] = conversion_options if conversion_options.any?

      response = HTTParty.post(
        "#{@base_url}/convert-url",
        headers: headers,
        body: request_data.to_json
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
        print "→ Downloading from URL and converting"
        
        attempts = 0
        max_attempts = 90  # 3 minutes for URL conversions
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
        elsif !webhook_url
          print "\nDownload converted file? (y/n): "
          answer = STDIN.gets.chomp
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
        puts "URL downloads may take more time for large files."
        puts "Check status with: ruby job-management/check-status.rb #{job_id}"
        
        if webhook_url
          puts "You will receive a webhook notification when complete."
        end
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
    opts.banner = "Usage: ruby convert-from-url.rb [options] <url> <target_format>"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby convert-from-url.rb https://example.com/document.pdf docx"
    opts.separator "  ruby convert-from-url.rb https://example.com/image.png jpg --quality=85"
    opts.separator "  ruby convert-from-url.rb https://example.com/video.mp4 webm --webhook=https://your-server.com/webhook"
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

  url = ARGV[0]
  target_format = ARGV[1].downcase

  # Override API key if provided
  api_key = options[:api_key] || API_KEY

  converter = UrlConverter.new(api_key, API_BASE_URL)
  converter.convert_from_url(url, target_format, options)
end