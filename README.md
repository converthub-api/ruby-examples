# ConvertHub API Ruby Examples

Complete Ruby code examples for integrating with the [ConvertHub API](https://converthub.com/api) - a powerful file conversion service supporting 800+ format pairs.

## 🚀 Quick Start

1. **Get your API key** from [https://converthub.com/api](https://converthub.com/api)
2. **Clone this repository**:
   ```bash
   git clone https://github.com/converthub-api/ruby-examples.git
   cd ruby-examples
   ```
3. **Install dependencies**:
   ```bash
   bundle install
   ```
4. **Configure your API key**:
   ```bash
   cp .env.example .env
   # Edit .env and add your API key
   ```
5. **Run any example**:
   ```bash
   ruby simple-convert/convert.rb document.pdf docx
   ```

## 📁 Examples Directory Structure

Each directory contains working examples for specific API endpoints:

### 1. Simple Convert (`/simple-convert`)
Direct file upload and conversion (files up to 50MB).

- `convert.rb` - Convert a local file with optional quality settings

```bash
# Basic conversion
ruby simple-convert/convert.rb image.png jpg

# With options
ruby simple-convert/convert.rb document.pdf docx --api-key=YOUR_KEY
```

### 2. URL Convert (`/url-convert`)
Convert files directly from URLs without downloading them first.

- `convert-from-url.rb` - Convert a file from any public URL

```bash
ruby url-convert/convert-from-url.rb https://example.com/file.pdf docx
```

### 3. Chunked Upload (`/chunked-upload`)
Upload and convert large files (up to 2GB) in chunks.

- `upload-large-file.rb` - Upload large files in configurable chunks

```bash
# Default 5MB chunks
ruby chunked-upload/upload-large-file.rb video.mov mp4

# Custom chunk size
ruby chunked-upload/upload-large-file.rb large.pdf docx --chunk-size=10
```

### 4. Job Management (`/job-management`)
Track and manage conversion jobs with dedicated scripts for each operation.

- `check-status.rb` - Check job status and optionally watch progress
- `cancel-job.rb` - Cancel a running or queued job
- `delete-file.rb` - Delete converted file from storage
- `download-result.rb` - Download the converted file

```bash
# Check job status
ruby job-management/check-status.rb job_123e4567-e89b-12d3

# Watch progress until complete
ruby job-management/check-status.rb job_123e4567-e89b-12d3 --watch

# Cancel a running job
ruby job-management/cancel-job.rb job_123e4567-e89b-12d3

# Delete a completed file (with confirmation)
ruby job-management/delete-file.rb job_123e4567-e89b-12d3

# Force delete without confirmation
ruby job-management/delete-file.rb job_123e4567-e89b-12d3 --force

# Download conversion result
ruby job-management/download-result.rb job_123e4567-e89b-12d3

# Download with custom filename
ruby job-management/download-result.rb job_123e4567-e89b-12d3 --output=myfile.pdf
```

### 5. Format Discovery (`/format-discovery`)
Explore supported formats and conversions.

- `list-formats.rb` - List formats, check conversions, explore possibilities

```bash
# List all supported formats
ruby format-discovery/list-formats.rb

# Show all conversions from PDF
ruby format-discovery/list-formats.rb --from=pdf

# Check if specific conversion is supported
ruby format-discovery/list-formats.rb --check=pdf:docx
```

### 6. Webhook Handler (`/webhook-handler`)
Receive real-time conversion notifications.

- `webhook-receiver.rb` - Production-ready webhook endpoint

Start the webhook server:
```bash
ruby webhook-handler/webhook-receiver.rb
```

Then use the webhook URL in your conversions:
```ruby
# When submitting conversions:
data = {
  file: file,
  target_format: 'pdf',
  webhook_url: 'https://your-server.com/webhook'
}
```

## 🔑 Authentication

All API requests require a Bearer token. Get your API key at [https://converthub.com/api](https://converthub.com/api).

### Method 1: Environment File (Recommended)
```bash
# Copy the example file
cp .env.example .env

# Edit .env and add your key
CONVERTHUB_API_KEY="your_api_key_here"
```

### Method 2: Command Line Parameter
```bash
ruby simple-convert/convert.rb file.pdf docx --api-key=your_key_here
```

### Method 3: Direct in Code
```ruby
API_KEY = 'your_api_key_here'
headers = { 'Authorization' => "Bearer #{API_KEY}" }
```

## 📊 Supported Conversions

The API supports 800+ format conversions, some popular ones include:

| Category | Formats |
|----------|---------|
| **Images** | JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC, ICO, TGA |
| **Documents** | PDF, DOCX, DOC, TXT, RTF, ODT, HTML, MARKDOWN, TEX |
| **Spreadsheets** | XLSX, XLS, CSV, ODS, TSV |
| **Presentations** | PPTX, PPT, ODP, KEY |
| **Videos** | MP4, WEBM, AVI, MOV, MKV, WMV, FLV, MPG |
| **Audio** | MP3, WAV, OGG, M4A, FLAC, AAC, WMA, OPUS |
| **eBooks** | EPUB, MOBI, AZW3, FB2, LIT |
| **Archives** | ZIP, RAR, 7Z, TAR, GZ, BZ2 |

## ⚙️ Conversion Options

Customize your conversions with various options:

```bash
# In simple-convert/convert.rb:
ruby convert.rb image.png jpg --quality=85 --resolution=1920x1080

# Available options:
--quality=N        # Image quality (1-100)
--resolution=WxH   # Output resolution
--bitrate=RATE     # Audio/video bitrate (e.g., "320k")
--sample-rate=N    # Audio sample rate (e.g., 44100)
--output=FILENAME  # Custom output filename
```

## 🚦 Error Handling

All examples include comprehensive error handling:

```ruby
# Every script handles API errors properly:
if response.code >= 400
  error_data = JSON.parse(response.body)
  error = error_data['error'] || {}
  puts "Error: #{error['message'] || 'Unknown error'}"
  puts "Code: #{error['code']}"
end
```

Common error codes:
- `AUTHENTICATION_REQUIRED` - Missing or invalid API key
- `NO_MEMBERSHIP` - No active membership found
- `INSUFFICIENT_CREDITS` - No credits remaining
- `FILE_TOO_LARGE` - File exceeds size limit
- `UNSUPPORTED_FORMAT` - Format not supported
- `CONVERSION_FAILED` - Processing error

## 📈 Rate Limits

| Endpoint | Limit | Script |
|----------|-------|--------|
| Convert | 60/minute | `simple-convert/convert.rb` |
| Convert URL | 60/minute | `url-convert/convert-from-url.rb` |
| Status Check | 100/minute | `job-management/check-status.rb` |
| Format Discovery | 200/minute | `format-discovery/list-formats.rb` |
| Chunked Upload | 500/minute | `chunked-upload/upload-large-file.rb` |

## 🔧 Requirements

- Ruby 2.7 or higher
- Dependencies in `Gemfile`:
  - `httparty` - HTTP client library
  - `dotenv` - Environment variable management
  - `colorize` - Cross-platform colored terminal output
  - `ruby-progressbar` - Progress bars for uploads/downloads
  - `sinatra` - Web framework for webhook receiver
  - `puma` - Web server for Sinatra
  - `json` - JSON parsing
  - `mime-types` - File mime type detection

## 📚 File Descriptions

| File | Purpose |
|------|---------|
| `.env.example` | Environment configuration template |
| `Gemfile` | Ruby package dependencies |
| **Simple Convert** | |
| `simple-convert/convert.rb` | Convert local files up to 50MB |
| **URL Convert** | |
| `url-convert/convert-from-url.rb` | Convert files from URLs |
| **Chunked Upload** | |
| `chunked-upload/upload-large-file.rb` | Upload files up to 2GB in chunks |
| **Job Management** | |
| `job-management/check-status.rb` | Check job status and watch progress |
| `job-management/cancel-job.rb` | Cancel running or queued jobs |
| `job-management/delete-file.rb` | Delete converted files from storage |
| `job-management/download-result.rb` | Download conversion results |
| **Format Discovery** | |
| `format-discovery/list-formats.rb` | Explore supported formats |
| **Webhook Handler** | |
| `webhook-handler/webhook-receiver.rb` | Handle webhook notifications |

## 💡 Usage Examples

### Convert a PDF to Word
```bash
ruby simple-convert/convert.rb document.pdf docx
```

### Convert an image from URL
```bash
ruby url-convert/convert-from-url.rb https://example.com/photo.png jpg
```

### Upload a large video
```bash
ruby chunked-upload/upload-large-file.rb movie.mov mp4 --chunk-size=10
```

### Monitor conversion progress
```bash
ruby job-management/check-status.rb job_abc123 --watch
```

### Check if conversion is supported
```bash
ruby format-discovery/list-formats.rb --check=heic:jpg
```

## 💎 Ruby Code Examples

### Simple conversion
```ruby
require 'httparty'

API_KEY = 'your_api_key'
headers = { 'Authorization' => "Bearer #{API_KEY}" }

File.open('document.pdf', 'rb') do |file|
  response = HTTParty.post(
    'https://api.converthub.com/v2/convert',
    headers: headers,
    body: {
      file: file,
      target_format: 'docx'
    }
  )
  
  job = JSON.parse(response.body)
  puts "Job ID: #{job['job_id']}"
end
```

### URL conversion
```ruby
require 'httparty'
require 'json'

API_KEY = 'your_api_key'
headers = {
  'Authorization' => "Bearer #{API_KEY}",
  'Content-Type' => 'application/json'
}

data = {
  file_url: 'https://example.com/file.pdf',
  target_format: 'docx'
}

response = HTTParty.post(
  'https://api.converthub.com/v2/convert-url',
  headers: headers,
  body: data.to_json
)

job = JSON.parse(response.body)
puts "Job ID: #{job['job_id']}"
```

## 🚀 Production Deployment

For production webhook deployment:

### Using Puma
```bash
# Install puma
gem install puma

# Run with 4 workers
puma -w 4 -p 8080 webhook-handler/webhook-receiver.rb
```

### Using systemd
```ini
# /etc/systemd/system/converthub-webhook.service
[Unit]
Description=ConvertHub Webhook Receiver
After=network.target

[Service]
User=www-data
WorkingDirectory=/path/to/webhook-handler
Environment="PATH=/path/to/ruby/bin"
ExecStart=/path/to/ruby/bin/ruby webhook-receiver.rb
Restart=always

[Install]
WantedBy=multi-user.target
```

### Using Docker
```dockerfile
FROM ruby:3.0-slim

WORKDIR /app
COPY Gemfile .
RUN bundle install

COPY webhook-handler/ .

CMD ["ruby", "webhook-receiver.rb"]
```

## 🤝 Support

- **API Documentation**: [https://converthub.com/api/docs](https://converthub.com/api/docs)
- **Developer Dashboard**: [https://converthub.com/developers](https://converthub.com/developers)
- **Get API Key**: [https://converthub.com/api](https://converthub.com/api)
- **Email Support**: support@converthub.com

## 📄 License

These examples are provided under the MIT License. Feel free to use and modify them for your projects.

## 🙏 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

---

Built with ❤️ by [ConvertHub](https://converthub.com) - Making file conversion simple and powerful.