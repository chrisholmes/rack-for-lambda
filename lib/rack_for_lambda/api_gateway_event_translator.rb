require 'rack/utils'
require 'rack'
require 'base64'

module RackForLambda
  class ApiGatewayEventTranslator
    def translate_request(event)
      {
        "REQUEST_METHOD" => event["httpMethod"],
        "PATH_INFO" => event['path'],
        "SERVER_NAME" => event.dig('headers', 'HOST'),
        "SERVER_PORT" => event.dig('headers', 'X-Forwarded-Port'),
        "SCRIPT_NAME" => (event.dig('requestContext', 'path') || '').chomp(event['path']),
        'QUERY_STRING' => join_query_params(event),
        'CONTENT_TYPE' => event.dig('headers', 'Content-Type'),
        'CONTENT_LENGTH' => event.dig('headers', 'Content-Length'),
        'rack.version' => Rack::VERSION,
        'rack.url_scheme' => event.dig('headers', 'X-Forwarded-Proto'),
        'rack.input' => create_input(event),
        'rack.errors' => $stderr,
        'rack.multiprocess' => false,
        'rack.multithread' => true,
        'rack.hijack?' => false,
        'rack.run_once' => false
      }.merge(http_headers(event))
    end


    def translate_response(headers, status, body_content)
      Response.new(headers, status, body_content).to_h
    end

    class Response
      attr_reader :headers, :status, :body_content
      require 'set'
      BINARY_CONTENT_TYPES = Set.new(["application/octet-stream", "image/jpeg", "image/png", "image/gif"])

      def initialize(headers, status, body_content)
        @headers = headers
        @status = status
        @body_content = body_content.join("")
      end

      def body
        @body ||= convert_body_content
      end

      def convert_body_content
        if is_base_64_encoded?
          Base64.encode64(@body_content)
        else
          @body_content
        end
      end

      def is_base_64_encoded?
        @is_base_64_encoded ||= is_binary? || !is_utf8?
      end

      def is_binary?
        BINARY_CONTENT_TYPES.include?(headers["Content-Type"])
      end

      def is_utf8?
        @body_content.encoding == Encoding::UTF_8
      end

      def to_h
        {
          'status' => status,
          'headers' => headers,
          'isBase64Encoded' => is_base_64_encoded?,
          'body' => body,
        }
      end

      def to_json
        self.to_h.to_json
      end
    end

  private

    def create_input(event)
      body = event['body'] || ''
      if event['isBase64Encoded']
        body = Base64.decode64(body)
      end
      StringIO.new(body)
    end

    def join_query_params(event)
      Rack::Utils.build_query(event.fetch('multiValueQueryStringParameters', {}))
    end

    def http_headers(event)
      event.fetch('headers', {}).each.with_object({}) do |(key, value), headers|
        headers["HTTP_#{key}"] = value
      end
    end
  end
end
