require 'rack_for_lambda/api_gateway_event_translator'
require 'rack/utils'

module RackForLambda
  class ApiGatewayEventProxy
    def initialize(app, translator)
      @app = app
      @translator = translator
    end

    def handle(event)
      env = @translator.translate_request(event)
      headers, status, body_content = @app.call(Rack::Utils::HeaderHash.new(env))

      body = ""
      body_content.each do |chunk|
        body += chunk
      end

      response = @translator.translate_response(event)
    end
  end
end
