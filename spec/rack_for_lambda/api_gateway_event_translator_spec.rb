require 'rack_for_lambda/api_gateway_event_translator'
module RackForLambda
  RSpec.describe ApiGatewayEventTranslator do
    let(:fixture) {
      { 
        "httpMethod" => "POST",
        'path' => '/my/path/info',
        'headers' => {
          'HOST' => 'example.com',
          'X-Forwarded-Port' => 443,
          'X-Forwarded-Proto' => 'https'
        },
        'requestContext' => {
          'path' => '/base/my/path/info'
        }
      }
    }

    subject { ApiGatewayEventTranslator.new }
    context "REQUEST_METHOD" do
      it "is extracted from httpMethod" do
        env = subject.translate(fixture)
        expect(env['REQUEST_METHOD']).to eql 'POST'
        %w{GET PUT POST DELETE PATCH}.each do |method|
          env = subject.translate(fixture.merge("httpMethod" => method))
          expect(env['REQUEST_METHOD']).to eql method
        end
      end
    end
    context "PATH_INFO" do
      it "is extracted from path" do
        env = subject.translate(fixture)
        expect(env['PATH_INFO']).to eql '/my/path/info'
        env = subject.translate(fixture.merge("path" => '/a/different/path'))
        expect(env['PATH_INFO']).to eql '/a/different/path'
      end
    end
    context "SERVER_NAME" do
      it "is extracted from HOST header" do
        env = subject.translate(fixture)
        expect(env['SERVER_NAME']).to eql 'example.com'
        env = subject.translate(fixture.merge('headers' => { 'HOST' => 'a.example.com'}))
        expect(env['SERVER_NAME']).to eql 'a.example.com'
      end
    end

    context "SERVER_PORT" do
      it "is extracted from X-Forwarded-Port header" do
        env = subject.translate(fixture)
        expect(env['SERVER_PORT']).to eql 443
        env = subject.translate(fixture.merge('headers' => { 'X-Forwarded-Port' => 444}))
        expect(env['SERVER_PORT']).to eql 444
      end
    end

    context "SCRIPT_NAME" do
      context "is extracted from requestContext.path and path" do
        it 'is / when requestContext.path is missing' do
          fixture['requestContext'].delete('path')
          env = subject.translate(fixture)
          expect(env['SCRIPT_NAME']).to eql ''
        end

        it 'is path chomped from request.path' do
          env = subject.translate(fixture)
          expect(env['SCRIPT_NAME']).to eql '/base'
          env = subject.translate(fixture.merge('requestContext' => { 'path' => '/prefix/my/path/info'}))
          expect(env['SCRIPT_NAME']).to eql '/prefix'
        end
      end
    end

    context 'QUERY_STRING' do
      it 'is the query parameters joined together' do
        fixture['multiValueQueryStringParameters'] = {
          'a' => %w{x y z},
          'b' => %w{j k l},
          'c' => %w{i o p},
        }
        env = subject.translate(fixture)
        expect(env['QUERY_STRING']).to eql 'a=x&a=y&a=z&b=j&b=k&b=l&c=i&c=o&c=p'
      end
      it 'will URL encode' do
        fixture['multiValueQueryStringParameters'] = {
          'a' => %w{http://example.com}
        }
        env = subject.translate(fixture)
        expect(env['QUERY_STRING']).to eql 'a=http%3A%2F%2Fexample.com'
      end
    end

    context 'rack.url_scheme' do
      it 'is taken from X-Forwarded-Proto header' do
        env = subject.translate(fixture)
        expect(env['rack.url_scheme']).to eql 'https'
        fixture['headers'].merge!('X-Forwarded-Proto' => 'http')
        env = subject.translate(fixture)
        expect(env['rack.url_scheme']).to eql 'http'
      end
    end

    context 'rack.input' do
      it 'is read from the body' do
        env = subject.translate(fixture.merge('body' => 'foobarbaz'))
        expect(env['rack.input']).to be_a StringIO
        expect(env['rack.input'].read).to eql 'foobarbaz'
      end

      it 'is empty when there is no body' do
        fixture.delete('body')
        env = subject.translate(fixture)
        expect(env['rack.input']).to be_a StringIO
        expect(env['rack.input'].read).to eql ''
      end

      it 'is the Base64 decoded form of body if event["isBase64Encoded"] is true' do
        env = subject.translate(fixture.merge('body' => Base64.encode64('foobarbaz'), 'isBase64Encoded' => true))
        expect(env['rack.input']).to be_a StringIO
        expect(env['rack.input'].read).to eql 'foobarbaz'
      end

      it 'does not decode body if event["isBase64Encoded"] is false' do
        encoded = Base64.encode64('foobarbaz')
        env = subject.translate(fixture.merge('body' => encoded, 'isBase64Encoded' => false))
        expect(env['rack.input']).to be_a StringIO
        rack_input = env['rack.input'].read
        expect(rack_input).to_not eql 'foobarbaz'
        expect(rack_input).to eql encoded
      end
    end

    context 'rack.errors' do
      it 'is stderr' do
        env = subject.translate(fixture)
        expect(env['rack.errors']).to eql $stderr
      end
    end

    context 'CONTENT_TYPE' do
      it 'is taken from the Content-Type header' do
        fixture['headers']['Content-Type'] = 'application/json'
        env = subject.translate(fixture)
        expect(env['CONTENT_TYPE']).to eql 'application/json'
      end

      it 'is nil when no header' do
        env = subject.translate(fixture)
        expect(env['CONTENT_TYPE']).to be_nil
      end
    end

    context 'CONTENT_LENGTH' do
      it 'is taken from the Content-Type header' do
        fixture['headers']['Content-Length'] = 188
        env = subject.translate(fixture)
        expect(env['CONTENT_LENGTH']).to eql 188
      end

      it 'is nil when no header' do
        env = subject.translate(fixture)
        expect(env['CONTENT_LENGTH']).to be_nil
      end
    end

    context 'HTTP_' do
      it 'is prefixed to all the headers' do
        env = subject.translate(fixture)
        expect(env['HTTP_HOST']).to eql 'example.com'
        expect(env['HTTP_X-Forwarded-Port']).to eql 443
        expect(env['HTTP_X-Forwarded-Proto']).to eql 'https'
      end

      it 'is prefixed to all the headers' do
        env = subject.translate(fixture.merge(headers: {}))
        expect(env.keys.any?{ |key| key.start_with?('HTTP_') }).to eql true
      end
    end

    context 'rack.hijack?' do
      it 'is false' do
        env = subject.translate(fixture)
        expect(env['rack.hijack?']).to eql false
      end
    end

    context 'rack.multiprocess' do
      it 'is false' do
        env = subject.translate(fixture)
        expect(env['rack.multiprocess']).to eql false
      end
    end

    context 'rack.multithread' do
      it 'is true' do
        env = subject.translate(fixture)
        expect(env['rack.multithread']).to eql true
      end
    end

    context 'rack.run_once' do
      it 'is false because we will reuse the process' do
        env = subject.translate(fixture)
        expect(env['rack.run_once']).to eql false
      end
    end
  end
end
