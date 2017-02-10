#

module Bespoked
  class HijackWrapper
    def initialize(reader, writer)
      #TODO: assert this is correct wrapper script
      @reader = reader
      @writer = writer
    end

    def call(*args)
      self
    end

    def gets
      rad = read
      rad
    end

    def each
      rad = read
      yield rad
    end

    def rewind
      @reader.rewind
    end

    def read(length = nil)
      rad = @reader.read_nonblock(length)
      rad || ""
    end
    
    def write(chunk)
      puts "WEITERRIRIRIRIRIRIRIRIRIRIRI"
      @writer.write(chunk)
    end

    def read_nonblock
      read
    end

    def write_nonblock(chunk)
      write(chunk)
    end

    def flush
      @writer.flush
    end
    
    def close
      @writer.close
    end
    
    def close_read
      close
    end
    
    def close_write
      close
    end
    
    def closed?
      @writer.closed?
    end

    def eof?
      puts "ASDADASDASD"
      @reader.eof?
    end
  end

  class LibUVRackServer
    attr_accessor :run_loop,
                  :app,
                  :server

    def initialize(run_loop_in, app_in, options={})
      self.run_loop = run_loop_in
      self.app = app_in

      options[:BindAddress] = DEFAULT_LIBUV_SOCKET_BIND

      self.server = @run_loop.tcp(flags: Socket::AF_INET6 | Socket::AF_INET)

      @server.catch do |reason|
        puts reason.inspect
      end

      @server.bind(options[:BindAddress], options[:Port].to_i) do |client|
        puts "NEW CONNECTION"
        defer_until_after_body = @run_loop.defer
        defer_until_after_body.promise.progress do |request_depth|
          handle_client(defer_until_after_body, client, request_depth)
        end

        handle_client(defer_until_after_body, client, 0)
      end
    end

    def start
      @server.listen(1024)
    end

    def shutdown
      @server.shutdown
      @server.close
    end

    def handle_client(retry_defer, client, request_depth)
      puts request_depth

      outer_http_parser = Http::Parser.new
      should_parse_http = true

      defer_until_after_body = @run_loop.defer

      # One chunk of the body
      outer_http_parser.on_body = proc do |chunk|
      end

      # HTTP headers available
      outer_http_parser.on_headers_complete = proc do
        defer_until_after_body.promise.progress do |string_io|

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

          string_io = StringIO.new(string_io) unless string_io.is_a?(StringIO)
          hijack_wrapper = HijackWrapper.new(string_io, client)

          env = {}

          env.update(
            'HTTP_VERSION'      => "HTTP/#{http_parser_http_version.join(".")}",

            'RACK_VERSION'      => ::Rack::VERSION.to_s,
            'RACK_ERRORS'       => "",
            "RACK_INPUT"        => "",

            'rack.url_scheme'   => scheme,
            'rack.hijack?'      => true,
            'rack.hijack'       => hijack_wrapper,
            "rack.errors"       => $stdout,
            "rack.version"      => ::Rack::VERSION.to_s.split("."),
            "rack.multithread"  => true,
            "rack.multiprocess" => false,
            "rack.run_once"     => true,
            "rack.input"        => hijack_wrapper
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

          #puts http_parser_headers.inspect
          #puts env.inspect
          #puts [env['PATH_INFO'], host_header].inspect

          status = nil
          headers = nil
          body = nil

          status, headers, body = @app.call(env)
          puts [body.class].inspect

          #@run_loop.work do
            Thread.new do
              crang(nil, client, status, headers, body, env).promise.progress do |sdsd|
              puts [sdsd, :WWEWEWE].inspect
                retry_defer.notify(request_depth + 1)
              end
            end
          #end

=begin
          if headers["Content-Type"] == "text/event-stream"
            #TODO: figure out threads/co-routines
          else
            crang(:alt, client, status, headers, body, env)
          end
=end

        end
        
        should_parse_http = false

        #outer_http_parser.reset!

        :stop
      end

      ##################

      client.progress do |chunk|
        if should_parse_http
          offset_of_body_left_in_buffer = outer_http_parser << chunk
          body_left_over = chunk[offset_of_body_left_in_buffer, (chunk.length - offset_of_body_left_in_buffer)]
          string_io_alt = StringIO.new(body_left_over).set_encoding('ASCII-8BIT')
          string_io_alt.rewind
          defer_until_after_body.notify(string_io_alt)
        else
          defer_until_after_body.notify(chunk)
        end
      end

      client.start_read
    end

    def crang(alt, client, status, headers, body, env)
      if alt == :alt
        unless headers["Content-Length"]
          length = 0
          body.each { |b|
            length += b.length
          }
          headers["Content-Length"] = length.to_s
        end
      end

      response = String.new

      headers_out = send_headers(client, status, headers, env)
      response.concat(headers_out) if headers_out.length > 0

      body_out = send_body(client, body)
      response.concat(body_out) if body_out.length > 0

      ##puts [response].inspect

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
          puts [env["PATH_INFO"], out].inspect
          chunk.concat(out)
        }
      }
      chunk.concat("\r\n")
      chunk
    end

    def send_body(client, body, wait = false)
      chunk = String.new
      body.each { |part|
        #puts [length, part].inspect
        if part
          unless part.is_a?(String)
            part = part.to_s
          end
          #puts [part].inspect
          chunk.concat(part)
        end
      }
      chunk
    end

    def thang(client, chunk, wrote_defer)
      if client && chunk && chunk.length > 0
        client.write(chunk, {:wait => :promise}).then { |a|
          puts :wrote_next_step
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
