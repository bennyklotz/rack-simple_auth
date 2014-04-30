module Rack
  module SimpleAuth
    # Contains different classes for authorizing against a hmac signed request
    module HMAC
      ##
      # Middleware class which represents the interface to the rack api via {#call}
      # and checks if a request is hmac authorized.
      #
      # @example Basic Usage
      #   "request_config = {
      #      'GET' => 'path',
      #      'POST' => 'params',
      #      'DELETE' => 'path',
      #      'PUT' => 'path',
      #      'PATCH' => 'path'
      #    }
      #
      #    use Rack::SimpleAuth::HMAC::Middleware do |options|
      #      options.tolerance = 1500
      #
      #      options.secret = 'test_secret'
      #      options.signature = 'test_signature'
      #
      #      options.logpath = "#{File.expand_path('..', __FILE__)}/logs"
      #      options.request_config = request_config
      #
      #      options.verbose = true
      #    end
      #
      #    run Rack::Lobster.new"
      #
      class Middleware
        ##
        # Throw NoMethodError and give hint if method who was called is Rack::SimpleAuth::Middleware.call
        #
        # @param [Symbol] name
        # @param [Array] args
        #
        # @raise [NoMethodError] if the method isn't defined
        #   and outputs additional hint for calling Rack::SimpleAuth::Middleware.call
        def self.method_missing(name, *args)
          msg = "Did you try to use HMAC Middleware as Rack Application via 'run'?\n" if name.eql?(:call)
          msg << "method: #{name}\n"
          msg << "args: #{args.inspect}\n" unless name.eql?(:call)
          msg << "on: #{self}"

          fail NoMethodError, msg
        end

        ##
        # Constructor for Rack Middleware (passing the rack stack)
        #
        # @param [Rack Application] app [next middleware or rack app which gets called]
        # @param [Proc] block [the dsl block which will be yielded into the config object]
        #
        def initialize(app, &block)
          @app, @config = app, Config.new

          yield @config if block_given?
        end

        ##
        # call Method for Rack Middleware/Application
        #
        # @param [Hash] env [Rack Env Hash which contains headers etc..]
        #
        def call(env)
          @request = Rack::Request.new(env)

          if valid_request?
            @app.call(env)
          else
            response = Rack::Response.new('Unauthorized', 401, 'Content-Type' => 'text/html')
            response.finish
          end
        end

        private

        ##
        # Checks for valid HMAC Request
        #
        # @return [TrueClass] if request is authorized
        # @return [FalseClass] if request is not authorized or HTTP_AUTHORIZATION Header is not set
        #
        def valid_request?
          log

          return false if empty_header? || !authorized?

          true
        end

        ##
        # Check if HTTP_AUTHORIZATION Header is set
        #
        # @return [TrueClass] if header is set
        # @return [FalseClass] if header is not set
        #
        def empty_header?
          @request.env['HTTP_AUTHORIZATION'].nil?
        end

        ##
        # Check if request is authorized
        #
        # @return [TrueClass] if request is authorized -> {#request_signature} is correct & {#request_message} is included
        #   in {#allowed_messages}
        # @return [FalseClass] if request is not authorized
        #
        def authorized?
          request_signature.eql?(@config.signature) && allowed_messages.include?(request_message)
        end

        ##
        # Get request signature
        #
        # @return [String] signature of current request
        #
        def request_signature
          @request.env['HTTP_AUTHORIZATION'].split(':').last
        end

        ##
        # Get encrypted request message
        #
        # @return [String] message of current request
        #
        def request_message
          @request.env['HTTP_AUTHORIZATION'].split(':').first
        end

        ##
        # Builds Array of allowed message hashs between @tolerance via {#message}
        #
        # @return [Array]
        def allowed_messages
          messages = []

          # Timestamp with milliseconds as Fixnum
          date = (Time.now.to_f.freeze * 1000).to_i
          (-(@config.tolerance)..@config.tolerance).step(1) do |i|
            messages << OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), @config.secret, message(date, i))
          end

          messages
        end

        ##
        # Get Message for current Request and delay
        #
        # @param [Fixnum] date [current date in timestamp format]
        # @param [Fixnum] delay [delay in timestamp format]
        #
        # @return [String] message
        def message(date, delay = 0)
          date += delay

          { 'method' => @request.request_method, 'date' => date, 'data' => request_data }.to_json
        end

        ##
        # Get Request Data specified by @config.request_config
        #
        # @return [String|Hash] data
        def request_data
          if @config.request_config[@request.request_method] == 'path' || @config.request_config[@request.request_method] == 'params'
            @request.send(@config.request_config[@request.request_method].to_sym)
          else
            fail "Not a valid option #{@config.request_config[@request.request_method]} - Use either params or path"
          end
        end

        ##
        # Log to @config.logpath
        # Contains:
        #   - allowed messages and received message
        #   - time when request was made
        #   - type of request
        #   - requested path
        def log
          if @config.logpath
            msg =  "#{Time.new} - #{@request.request_method} #{@request.path} - 400 Unauthorized\n"
            msg << "HTTP_AUTHORIZATION: #{@request.env['HTTP_AUTHORIZATION']}\n"
            msg << "Auth Message Config: #{@config.request_config[@request.request_method]}\n"

            if allowed_messages
              msg << "Allowed Encrypted Messages:\n"
              allowed_messages.each do |hash|
                msg << "#{hash}\n"
              end
            end

            msg << "Auth Signature: #{@config.signature}"

            Rack::SimpleAuth::Logger.log(@config.logpath, @config.verbose, ENV['RACK_ENV'], msg)
          end
        end
      end # Middleware
    end # HMAC
  end # SimpleAuth
end # Rack