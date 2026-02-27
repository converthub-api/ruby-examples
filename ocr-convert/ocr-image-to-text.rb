#!/usr/bin/env ruby
# frozen_string_literal: true

#
# ConvertHub API - OCR Image to Text Conversion
#
# Extract text from images (PNG, JPG, TIFF, etc.) using OCR.
# Supports multiple languages and outputs plain text.
#
# Usage:
#   ruby ocr-image-to-text.rb <input_image> [--language eng] [--api-key KEY]
#
# Examples:
#   ruby ocr-image-to-text.rb screenshot.png
#   ruby ocr-image-to-text.rb document.jpg --language deu
#   ruby ocr-image-to-text.rb scan.tiff --language eng+fra
#
# Supported input formats: png, jpg, jpeg, tiff, tif, bmp, gif, webp
# Supported languages: eng, deu, fra, spa, ita, por, nld, rus, chi_sim, chi_tra, jpn, kor, ara, hin
#
# Get your API key at: https://converthub.com/api
#

require 'httparty'
require 'optparse'
require 'json'

# Load .env from parent directory
env_file = File.join(File.dirname(__FILE__), '..', '.env')
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    ENV[key.strip] ||= value.strip if key && value
  end
end

SUPPORTED_FORMATS = %w[png jpg jpeg tiff tif bmp gif webp].freeze

class OcrImageToText
  API_BASE_URL = ENV.fetch('CONVERTHUB_API_BASE_URL', 'https://api.converthub.com/v2')
  MAX_FILE_SIZE = 52_428_800 # 50MB
  MAX_ATTEMPTS = 150 # 5 minutes (2s intervals)

  def initialize(api_key)
    @api_key = api_key
    @headers = { 'Authorization' => "Bearer #{api_key}" }
  end

  def convert(input_file, language)
    validate_file!(input_file)

    file_size = File.size(input_file)
    file_size_mb = (file_size / 1_048_576.0).round(2)

    puts "OCR: #{File.basename(input_file)} (#{file_size_mb} MB) -> txt (language: #{language})"
    puts '━' * 50
    puts

    # Step 1: Submit file for OCR conversion
    puts '-> Uploading file...'

    response = HTTParty.post(
      "#{API_BASE_URL}/convert",
      headers: @headers,
      multipart: true,
      body: {
        file: File.open(input_file, 'rb'),
        target_format: 'txt',
        'options[ocr]' => 'true',
        'options[ocr_language]' => language
      }
    )

    # Handle errors
    if response.code >= 400
      handle_error(response)
      exit 1
    end

    result = JSON.parse(response.body)

    # Check for cached result
    if response.code == 200 && result.dig('result', 'download_url')
      puts '[OK] OCR complete (cached result)'
      puts
      download_and_display(result['result']['download_url'], input_file)
      return
    end

    job_id = result['job_id']
    puts "[OK] Job created: #{job_id}"
    puts

    # Step 2: Poll for job completion
    print '-> Processing OCR'

    status = 'processing'
    job_status = nil

    MAX_ATTEMPTS.times do
      break unless %w[processing queued].include?(status)

      sleep 2
      print '.'

      begin
        resp = HTTParty.get("#{API_BASE_URL}/jobs/#{job_id}", headers: @headers)
        job_status = JSON.parse(resp.body)
        status = job_status['status'] || 'unknown'
      rescue StandardError
        next
      end
    end

    puts "\n\n"

    # Step 3: Handle result
    case status
    when 'completed'
      puts '[OK] OCR complete!'
      puts '━' * 50
      puts "Processing time: #{job_status['processing_time'] || 'N/A'}"
      puts "Download URL: #{job_status['result']['download_url']}"
      puts "Expires: #{job_status['result']['expires_at']}"
      puts

      download_and_display(job_status['result']['download_url'], input_file)
    when 'failed'
      puts '[ERROR] OCR failed'
      error = job_status&.dig('error') || {}
      puts "Error: #{error['message'] || 'Unknown error'}"
      exit 1
    else
      puts '[ERROR] Timeout: OCR is taking longer than expected'
      puts "Check status with: ruby ../job-management/check-status.rb #{job_id}"
      exit 1
    end
  end

  private

  def validate_file!(input_file)
    unless File.exist?(input_file)
      puts "Error: File '#{input_file}' not found."
      exit 1
    end

    extension = File.extname(input_file).downcase.delete('.')
    unless SUPPORTED_FORMATS.include?(extension)
      puts "Error: Unsupported format '#{extension}'. Supported: #{SUPPORTED_FORMATS.join(', ')}"
      exit 1
    end

    file_size = File.size(input_file)
    return unless file_size > MAX_FILE_SIZE

    puts "Error: File size (#{(file_size / 1_048_576.0).round(2)} MB) exceeds 50MB limit."
    exit 1
  end

  def handle_error(response)
    result = JSON.parse(response.body)
    error = result['error'] || {}
    puts "[ERROR] #{error['message'] || 'Unknown error'}"
    (error['details'] || {}).each do |key, value|
      puts "  #{key}: #{value.is_a?(Hash) ? value.to_json : value}"
    end
  rescue JSON::ParserError
    puts "[ERROR] HTTP #{response.code}: #{response.body}"
  end

  def download_and_display(download_url, input_file)
    base_name = File.basename(input_file, File.extname(input_file))
    output_file = File.join(File.dirname(input_file), "#{base_name}.txt")

    response = HTTParty.get(download_url)

    if response.code >= 400
      puts "[ERROR] Failed to download file (HTTP #{response.code})"
      exit 1
    end

    File.write(output_file, response.body)
    puts "Saved to: #{output_file}"
    puts

    # Display extracted text
    text = File.read(output_file, encoding: 'utf-8')
    if text.strip.length.positive?
      puts '--- Extracted Text ---'
      puts text
      puts '--- End ---'
    else
      puts '(No text was extracted - the image may not contain readable text)'
    end
  end
end

# Parse command line arguments
options = { language: 'eng', api_key: nil }

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby ocr-image-to-text.rb [options] <input_image>'
  opts.separator ''
  opts.separator 'Examples:'
  opts.separator '  ruby ocr-image-to-text.rb screenshot.png'
  opts.separator '  ruby ocr-image-to-text.rb document.jpg --language deu'
  opts.separator '  ruby ocr-image-to-text.rb scan.tiff --language eng+fra'
  opts.separator ''
  opts.separator "Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
  opts.separator ''

  opts.on('--language LANG', 'OCR language code (default: eng). Use + for multiple: eng+fra') do |v|
    options[:language] = v
  end

  opts.on('--api-key KEY', 'ConvertHub API key') do |v|
    options[:api_key] = v
  end
end

parser.parse!

if ARGV.empty?
  puts parser
  puts "\nGet your API key at: https://converthub.com/api"
  exit 1
end

input_file = ARGV[0]
api_key = options[:api_key] || ENV['CONVERTHUB_API_KEY']

unless api_key
  puts 'Error: API key required. Set CONVERTHUB_API_KEY in .env or use --api-key parameter.'
  puts 'Get your API key at: https://converthub.com/api'
  exit 1
end

converter = OcrImageToText.new(api_key)
converter.convert(input_file, options[:language])
