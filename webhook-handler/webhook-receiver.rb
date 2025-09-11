#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'colorize'
require 'dotenv'
require 'openssl'

Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

WEBHOOK_SECRET = ENV['WEBHOOK_SECRET']

set :port, ENV['PORT'] || 3000
set :bind, '0.0.0.0'

def verify_signature(payload, signature)
  return true unless WEBHOOK_SECRET
  
  expected_sig = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', WEBHOOK_SECRET, payload)}"
  Rack::Utils.secure_compare(expected_sig, signature)
end

def process_webhook_event(event_data)
  job_id = event_data['job_id']
  status = event_data['status']
  
  puts "\n" + "=" * 50
  puts "Webhook Event Received".cyan
  puts "Time: #{Time.now}"
  puts "Job ID: #{job_id}"
  puts "Status: #{status}"
  
  case status
  when 'completed'
    puts "✓ Conversion completed successfully!".green
    if event_data['result']
      result = event_data['result']
      puts "  Format: #{result['format']}"
      puts "  Download URL: #{result['download_url']}"
      puts "  Expires: #{result['expires_at']}"
    end
  when 'failed'
    puts "✗ Conversion failed".red
    if event_data['error']
      puts "  Error: #{event_data['error']['message']}"
    end
  when 'cancelled'
    puts "⚠️  Job cancelled".yellow
  else
    puts "Status updated: #{status}"
  end
  
  puts "=" * 50 + "\n"
  
  { status: 'received', job_id: job_id }
end

post '/webhook' do
  begin
    request.body.rewind
    raw_data = request.body.read
    
    signature = request.env['HTTP_X_WEBHOOK_SIGNATURE'] || ''
    unless verify_signature(raw_data, signature)
      status 401
      return { error: 'Invalid signature' }.to_json
    end
    
    event_data = JSON.parse(raw_data)
    result = process_webhook_event(event_data)
    
    content_type :json
    result.to_json
  rescue JSON::ParserError
    status 400
    { error: 'Invalid JSON' }.to_json
  rescue => e
    puts "Error: #{e.message}".red
    status 500
    { error: 'Internal server error' }.to_json
  end
end

get '/health' do
  content_type :json
  {
    status: 'healthy',
    timestamp: Time.now.iso8601,
    service: 'ConvertHub Webhook Receiver'
  }.to_json
end

get '/' do
  content_type :json
  {
    service: 'ConvertHub Webhook Receiver',
    endpoints: {
      '/webhook' => 'POST - Receive webhook events',
      '/health' => 'GET - Health check',
      '/' => 'GET - This message'
    },
    status: 'running'
  }.to_json
end

puts "ConvertHub Webhook Receiver".cyan
puts "=" * 30
puts "Listening on port #{settings.port}"
puts "Webhook endpoint: http://localhost:#{settings.port}/webhook"
puts "\nPress Ctrl+C to stop the server"
puts "-" * 30
