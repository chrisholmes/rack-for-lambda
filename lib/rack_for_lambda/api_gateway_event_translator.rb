require 'rack/utils'
require 'rack'
require 'base64'

module RackForLambda
  class ApiGatewayEventTranslator
    def translate(event)
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
