#

module Bespoked
  class InputIO
    def initialize(io, client)
      @io = io
      @client = client
    end

    def write
      $global_logger.notify([:write])
    end

    def gets
      $global_logger.notify([:gets])
      read
    end

    def read(*args)
      rad = @io.read
      $global_logger.notify([:read, args, rad])
      rad
    end

    def each
      $global_logger.notify([:each])
			while chunk = fd.read
				yield chunk
			end
    end

    def rewind
      $global_logger.notify([:rewind])
      @io.rewind
    end
  end

  class HijackWrapper < InputIO
    def initialize(reader, writer)
      @reader = reader
      @writer = writer
    end

    def call(args)
      $global_logger.notify([:call, args])
      self
    end
  end

  class LibUVRackServer
    attr_accessor :run_loop,
                  :app,
                  :server,
                  :logger

    def initialize(run_loop_in, logger_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in
      self.logger = logger_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      self.server = @run_loop.tcp(flags: Socket::AF_INET6 | Socket::AF_INET)

      @server.catch do |reason|
        record :debug, :rack_server_catch, [reason]
      end

      @server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        defer_until_after_body = @run_loop.defer
        defer_until_after_body.promise.progress do |request_depth|
          handle_client(defer_until_after_body, client, request_depth)
        end

        handle_client(defer_until_after_body, client, 0)
      end
    end

    def record(level = nil, name = nil, message = nil)
      if @logger
        log_event = {:date => Time.now, :level => level, :name => name, :message => message}
        @logger.notify(log_event)
      end
    end

    def start
      @server.listen(1024)
    end

    def shutdown
      @server.shutdown
      @server.close
    end

    def foop(outer_http_parser, outer_io, client, retry_defer, request_depth)
      http_parser_http_version = outer_http_parser.http_version || ["1", "1"]
      http_parser_http_method = outer_http_parser.http_method || "GET"
      http_parser_headers = outer_http_parser.headers || {}
      request_url = outer_http_parser.request_url

      if http_parser_headers == {}
        #puts http_parser.inspect
      end

      url = nil
      host = nil
      port = nil
      host_header = nil
      query_string = nil
      path_info = nil

      host_header = (http_parser_headers["host"] || http_parser_headers["Host"])
      forwarded_scheme = (http_parser_headers["X-Forwarded-Proto"] || "http")

      url = URI.parse("")
      host = ""
      port = 0
      query_string = ""
      path_info = ""
      scheme = forwarded_scheme

      if host_header
        url = URI.parse("#{forwarded_scheme}://" + host_header + request_url)
        scheme = url.scheme
        host = url.host
        port = url.port

        query_string = url.query
        path_info = url.path
      end

      #string_io = StringIO.new(string_io) unless string_io.is_a?(StringIO)
      hijack_wrapper = HijackWrapper.new(outer_io, client)
      hijack = true

      input_io = InputIO.new(outer_io, client)

      env = {}

      env.update(
        'HTTP_VERSION'      => "HTTP/#{http_parser_http_version.join(".")}",

        'RACK_VERSION'      => ::Rack::VERSION.to_s,
        'RACK_ERRORS'       => "",
        "RACK_INPUT"        => "",

        'rack.url_scheme'   => scheme,
        'rack.hijack?'      => hijack,
        'rack.hijack'       => hijack_wrapper,
        "rack.errors"       => @logger,
        "rack.logger"       => @logger,
        "rack.version"      => ::Rack::VERSION.to_s.split("."),
        "rack.multithread"  => true,
        "rack.multiprocess" => true,
        "rack.run_once"     => true,
        "rack.input"        => input_io
      )

      env['QUERY_STRING'] ||= query_string || ""
      env['REQUEST_METHOD'] = http_parser_http_method

      env['PATH_INFO'] = path_info
      env['SCRIPT_NAME'] = ""

      env["SERVER_NAME"] = host
      env["SERVER_PORT"] = port.to_s

      env["HTTP_COOKIE"] = http_parser_headers["Cookie"] || ""
      env["CONTENT_TYPE"] = http_parser_headers["Content-Type"] || ""
      env["CONTENT_LENGTH"] = http_parser_headers["Content-Length"] || "0"
      env["HTTP_ACCEPT"] = http_parser_headers["Accept"] || "0"

      ["Accept-Language", "Accept-Encoding", "Connection", "Upgrade-Insecure-Requests"].each do |inbh|
        env["HTTP_" + inbh.upcase.gsub("-", "_")] = http_parser_headers[inbh] if  http_parser_headers[inbh]
      end

      status = nil
      headers = nil
      body = nil

      #record :debug, :before_call, [http_parser_headers, env]
      status, headers, body = @app.call(env)
      #record :debug, :after_call, []

      crang(nil, client, status, headers, body, env).promise.progress do |sdsd|
        record :retry [request_depth]
        retry_defer.notify(request_depth + 1)
      end
    end

    def handle_client(retry_defer, client, request_depth)
      outer_io = StringIO.new
      #StringIO.new(body_left_over)
      outer_io.set_encoding('ASCII-8BIT')

      outer_http_parser = Http::Parser.new
      should_parse_http = true

      defer_until_after_body = @run_loop.defer

      # One chunk of the body
      outer_http_parser.on_body = proc do |chunk|
      end

      # HTTP headers available
      outer_http_parser.on_headers_complete = proc do
        should_parse_http = false

        defer_until_after_body.promise.progress do |string_io|
          #@run_loop.work do
          #Thread.new do
            foop(outer_http_parser, outer_io, client, retry_defer, request_depth)
          #end
        end

        :stop
      end

      ##################

      client.progress do |chunk|
        if should_parse_http
          offset_of_body_left_in_buffer = outer_http_parser << chunk
          body_left_over = chunk[offset_of_body_left_in_buffer, (chunk.length - offset_of_body_left_in_buffer)]
          outer_io << body_left_over
        else
          outer_io << chunk
        end

        length_required = outer_http_parser.headers["Content-Length"] || 0
        length_required = length_required.to_i
        #record :length, [outer_io.length, length_required]

        if length_required == 0 || outer_io.length == length_required
          #record :resolving, []
          outer_io.rewind
          defer_until_after_body.notify(outer_io)
        end
      end

      client.start_read
    end

    def crang(alt, client, status, headers, body, env)
      #if alt == :alt
        #unless headers["Content-Length"]
        #  length = 0
        #  body.each { |b|
        #    length += b.length
        #  }
        #  headers["Content-Length"] = length.to_s
        #end
      #end

      response = String.new

      headers_out = send_headers(client, status, headers, env)
      response.concat(headers_out) if headers_out.length > 0

      body_out = send_body(client, body)
      response.concat(body_out) if body_out.length > 0

      wrote_defer = @run_loop.defer
      thang(client, response, wrote_defer) unless client.closed?
      wrote_defer
    end

    def send_headers(client, status, headers, env)
      chunk = String.new
      chunk.concat("HTTP/1.1 #{status} #{WEBrick::HTTPStatus.reason_phrase(status)}\r\n")
      headers.each { |k, vs|
        vs.split("\n").each { |v|
          out = "#{k}: #{v}\r\n"
          chunk.concat(out)
        }
      }
      chunk.concat("\r\n")
      chunk
    end

    def send_body(client, body, wait = false)
      chunk = String.new
      body.each { |part|
        if part
          unless part.is_a?(String)
            part = part.to_s
          end
          chunk.concat(part)
        end
      }
      chunk
    end

    def thang(client, chunk, wrote_defer)
      if client && chunk && chunk.length > 0
        client.write(chunk, {:wait => :promise}).then { |a|
          wrote_defer.notify(:step)
        }.catch { |e|
          #TODO: record support
          #record :info, :proxy_write_error, [e].inspect
          if e.is_a?(Libuv::Error::ECANCELED)
            client.close
          end
        }
      end
    end
  end
end
