#!/usr/bin/env ruby

require 'httparty'
require 'dotenv'
require 'colorize'
require 'json'
require 'optparse'

# Load environment variables
Dotenv.load(File.join(File.dirname(__FILE__), '..', '.env'))

API_BASE_URL = ENV['CONVERTHUB_API_BASE_URL'] || 'https://api.converthub.com/v2'
API_KEY = ENV['CONVERTHUB_API_KEY']

class FormatDiscovery
  def initialize(api_key, base_url)
    @api_key = api_key
    @base_url = base_url
    
    # Format categories for grouping
    @categories = {
      'Images' => %w[jpg jpeg png webp gif bmp tiff svg ico heic tga psd],
      'Documents' => %w[pdf docx doc txt rtf odt html markdown tex xml],
      'Spreadsheets' => %w[xlsx xls csv ods tsv],
      'Presentations' => %w[pptx ppt odp key],
      'Videos' => %w[mp4 webm avi mov mkv wmv flv mpg m4v 3gp],
      'Audio' => %w[mp3 wav ogg m4a flac aac wma opus aiff],
      'eBooks' => %w[epub mobi azw3 fb2 lit pdb],
      'Archives' => %w[zip rar 7z tar gz bz2 xz],
      'CAD' => %w[dwg dxf dwf stl obj],
      'Fonts' => %w[ttf otf woff woff2 eot]
    }
  end

  def list_formats(from_format: nil, check_conversion: nil)
    # Check if API key is set
    unless @api_key
      puts "Error: CONVERTHUB_API_KEY is not set".red
      puts "Get your API key at: https://converthub.com/api"
      puts "\nSet it in .env file or use --api-key parameter"
      exit 1
    end

    puts "Format Discovery - ConvertHub API"
    puts "=" * 34

    headers = {
      'Authorization' => "Bearer #{@api_key}"
    }

    begin
      # Check specific conversion
      if check_conversion
        unless check_conversion.include?(':')
          puts "Error: Invalid format. Use 'from:to' (e.g., pdf:docx)".red
          exit 1
        end

        from_fmt, to_fmt = check_conversion.split(':', 2)
        puts "\n→ Checking conversion: #{from_fmt.upcase} → #{to_fmt.upcase}"

        response = HTTParty.get(
          "#{@base_url}/formats/#{from_fmt}/conversions",
          headers: headers
        )

        if response.code >= 400
          handle_error(response)
          exit 1
        end

        data = JSON.parse(response.body)
        available_conversions = extract_conversions(data)

        if available_conversions.map(&:downcase).include?(to_fmt.downcase)
          puts "\n✓ Conversion supported!".green
          puts "\nYou can convert #{from_fmt.upcase} files to #{to_fmt.upcase} format."
          puts "\nExample commands:"
          puts "  ruby simple-convert/convert.rb file.#{from_fmt} #{to_fmt}"
          puts "  ruby url-convert/convert-from-url.rb https://example.com/file.#{from_fmt} #{to_fmt}"
        else
          puts "\n✗ Conversion not supported".red
          puts "\n#{from_fmt.upcase} cannot be converted to #{to_fmt.upcase}"
          
          if available_conversions.any?
            puts "\nSupported conversions from #{from_fmt.upcase}:"
            available_conversions.first(10).each_with_index do |fmt, i|
              puts "  #{i + 1}. #{fmt.upcase}"
            end
            puts "  ... and #{available_conversions.size - 10} more" if available_conversions.size > 10
          end
        end
        
        return
      end

      # List conversions from a specific format
      if from_format
        puts "\n→ Getting conversions from #{from_format.upcase}..."

        response = HTTParty.get(
          "#{@base_url}/formats/#{from_format}/conversions",
          headers: headers
        )

        if response.code >= 400
          handle_error(response)
          exit 1
        end

        data = JSON.parse(response.body)
        conversions = extract_conversions(data)

        puts "\nAvailable conversions from #{from_format.upcase}:".cyan
        puts "-" * 50

        # Group conversions by category
        categorized = {}
        other = []

        conversions.each do |fmt|
          found = false
          @categories.each do |category, formats|
            if formats.include?(fmt.downcase)
              categorized[category] ||= []
              categorized[category] << fmt.upcase
              found = true
              break
            end
          end
          other << fmt.upcase unless found
        end

        # Display categorized formats
        @categories.keys.each do |category|
          if categorized[category]
            puts "\n#{category}:".yellow
            formats = categorized[category]
            formats.each_slice(10) do |slice|
              puts "  #{slice.join(', ')}"
            end
          end
        end

        if other.any?
          puts "\nOther:".yellow
          other.each_slice(10) do |slice|
            puts "  #{slice.join(', ')}"
          end
        end

        puts "\nTotal: #{conversions.size} formats supported".green
        
        return
      end

      # List all supported formats
      puts "\n→ Getting all supported formats..."

      response = HTTParty.get(
        "#{@base_url}/formats",
        headers: headers
      )

      if response.code >= 400
        handle_error(response)
        exit 1
      end

      data = JSON.parse(response.body)
      formats = extract_all_formats(data)

      puts "\nAll Supported Formats:".cyan
      puts "-" * 50

      # Group formats by category
      categorized = {}
      other = []

      formats.keys.each do |fmt|
        found = false
        @categories.each do |category, format_list|
          if format_list.include?(fmt.downcase)
            categorized[category] ||= []
            categorized[category] << fmt.upcase
            found = true
            break
          end
        end
        other << fmt.upcase unless found
      end

      # Display categorized formats
      total_conversions = 0
      @categories.keys.each do |category|
        if categorized[category]
          puts "\n#{category}:".yellow
          categorized[category].each do |fmt|
            fmt_lower = fmt.downcase
            if formats[fmt_lower]
              num_conversions = formats[fmt_lower]['conversions']&.size || 0
              total_conversions += num_conversions
              if num_conversions > 0
                puts "  • #{fmt} (#{num_conversions} conversions)"
              else
                puts "  • #{fmt}"
              end
            end
          end
        end
      end

      if other.any?
        puts "\nOther:".yellow
        other.each do |fmt|
          fmt_lower = fmt.downcase
          if formats[fmt_lower]
            num_conversions = formats[fmt_lower]['conversions']&.size || 0
            total_conversions += num_conversions
            if num_conversions > 0
              puts "  • #{fmt} (#{num_conversions} conversions)"
            else
              puts "  • #{fmt}"
            end
          end
        end
      end

      puts "\nSummary:".green
      puts "  Total formats: #{formats.size}"
      puts "  Total conversion pairs: #{total_conversions}"

      puts "\n" + "-" * 50
      puts "Usage examples:"
      puts "  ruby list-formats.rb --from=pdf"
      puts "  ruby list-formats.rb --check=pdf:docx"

    rescue => e
      puts "\n✗ Unexpected error: #{e.message}".red
      puts e.backtrace if ENV['DEBUG']
      exit 1
    end
  end

  private

  def extract_conversions(data)
    conversions = []
    
    # Try different possible response structures
    if data.is_a?(Hash)
      # Check for available_conversions key (v2 API)
      if data['available_conversions']
        conv_data = data['available_conversions']
      elsif data['conversions']
        conv_data = data['conversions']
      elsif data['supported_conversions']
        conv_data = data['supported_conversions']
      else
        conv_data = []
      end

      if conv_data.is_a?(Array)
        conv_data.each do |item|
          if item.is_a?(Hash)
            # Extract format from dict structure
            fmt = item['target_format'] || item['extension'] || item['format']
            conversions << fmt if fmt
          elsif item.is_a?(String)
            conversions << item
          end
        end
      elsif conv_data.is_a?(Hash)
        # If it's a dict, extract formats from categories
        conv_data.each do |_, formats|
          if formats.is_a?(Array)
            formats.each do |fmt|
              if fmt.is_a?(Hash)
                f = fmt['target_format'] || fmt['extension'] || fmt['format']
                conversions << f if f
              elsif fmt.is_a?(String)
                conversions << fmt
              end
            end
          end
        end
      end
    elsif data.is_a?(Array)
      conversions = data
    end

    conversions
  end

  def extract_all_formats(data)
    formats = {}
    
    if data.is_a?(Hash) && data['formats']
      raw_formats = data['formats']
      
      if raw_formats.is_a?(Hash)
        # Check if formats are grouped by category
        raw_formats.each do |key, value|
          if value.is_a?(Array)
            # It's a category with array of formats
            value.each do |fmt_info|
              if fmt_info.is_a?(Hash)
                ext = fmt_info['extension'] || fmt_info['format']
                formats[ext] = fmt_info if ext
              elsif fmt_info.is_a?(String)
                formats[fmt_info] = { 'conversions' => [] }
              end
            end
          elsif value.is_a?(Hash)
            # Direct format mapping
            formats[key] = value
          end
        end
      end
    end

    formats
  end

  def handle_error(response)
    begin
      error_data = JSON.parse(response.body)
      error = error_data['error'] || {}
      puts "\n✗ Error: #{error['message'] || 'Format not supported'}".red
      puts "  Code: #{error['code']}" if error['code']
    rescue
      puts "\n✗ Error: HTTP #{response.code}".red
    end
  end
end

# Main execution
if __FILE__ == $0
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby list-formats.rb [options]"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby list-formats.rb                    # List all supported formats"
    opts.separator "  ruby list-formats.rb --from=pdf         # Show all conversions from PDF"
    opts.separator "  ruby list-formats.rb --check=pdf:docx   # Check if PDF to DOCX is supported"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--from FORMAT", "List conversions from this format") do |f|
      options[:from_format] = f
    end

    opts.on("--check CONVERSION", "Check if conversion is supported (format: from:to)") do |c|
      options[:check_conversion] = c
    end

    opts.on("--api-key KEY", "Your API key") do |key|
      options[:api_key] = key
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end

  parser.parse!

  # Validate arguments
  if options[:from_format] && options[:check_conversion]
    puts "Error: Please use only one of --from or --check".red
    exit 1
  end

  # Override API key if provided
  api_key = options[:api_key] || API_KEY

  discovery = FormatDiscovery.new(api_key, API_BASE_URL)
  discovery.list_formats(
    from_format: options[:from_format],
    check_conversion: options[:check_conversion]
  )
end