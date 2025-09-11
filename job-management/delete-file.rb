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

def delete_file(job_id, force = false)
  unless API_KEY
    puts "Error: CONVERTHUB_API_KEY is not set".red
    exit 1
  end

  puts "Delete File - ConvertHub API"
  puts "=" * 29
  puts "Job ID: #{job_id}"
  puts "-" * 50 + "\n"

  headers = { 'Authorization' => "Bearer #{API_KEY}" }

  begin
    puts "→ Retrieving file information..."
    
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

    if status != 'completed'
      puts "\n⚠️  No file to delete".yellow
      puts "Job status: #{status}"
      exit 0
    end

    result = job['result'] || {}
    unless result['download_url']
      puts "\n⚠️  No file available".yellow
      exit 0
    end

    puts "\nFile Information:".cyan
    puts "  Format: #{result['format']&.upcase || 'N/A'}"
    puts "  Size: #{format_file_size(result['file_size'])}"
    puts "  Expires: #{result['expires_at']}" if result['expires_at']
    
    puts "\nDownload URL:"
    puts "  #{result['download_url']}"

    unless force
      puts "\n⚠️  Warning: This action cannot be undone!".red
      puts "Once deleted, the file cannot be recovered."
      print "\nAre you sure you want to delete this file? (y/n): "
      answer = gets.chomp
      unless answer.downcase == 'y'
        puts "\n✗ Deletion cancelled"
        exit 0
      end
    end

    puts "\n→ Deleting file..."
    
    delete_response = HTTParty.delete("#{API_BASE_URL}/jobs/#{job_id}/destroy", headers: headers)
    
    if delete_response.code == 200 || delete_response.code == 204
      puts "\n✓ File deleted successfully".green
      result = JSON.parse(delete_response.body) rescue {}
      puts "  #{result['message']}" if result['message']
      puts "\nThe converted file has been permanently deleted from storage."
    elsif delete_response.code == 404
      puts "\n⚠️  File not found".yellow
      puts "The file may have already been deleted or expired."
    else
      error_data = JSON.parse(delete_response.body) rescue {}
      error = error_data['error'] || {}
      puts "\n✗ Failed to delete file".red
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
    opts.banner = "Usage: ruby delete-file.rb [options] <job_id>"
    opts.on("--force", "Skip confirmation prompt") { options[:force] = true }
    opts.on("--api-key KEY", "Your API key") { |k| API_KEY = k }
    opts.on("-h", "--help", "Show help") { puts opts; exit }
  end

  parser.parse!
  
  if ARGV.empty?
    puts parser
    exit 1
  end

  delete_file(ARGV[0], options[:force])
end
