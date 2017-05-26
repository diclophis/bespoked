require_relative '../test_helper'

class LibUVHttpProxyServerTest < MiniTest::Spec
  MOCK_HTTP_REQUEST = <<-HERE
GET /first HTTP/1.1
Host: localhost
User-Agent: minitest/ruby
Accept: */png
Connection: keep-alive

GET /second HTTP/1.1
Host: localhost
User-Agent: minitest/ruby
Accept: */txt
Connection: keep-alive

HERE

=begin
GET /second HTTP/1.1
Host: localhost
User-Agent: minitest/ruby
Accept: */*
Content-Length: 32
Connection: keep-alive

12345678901234567890123456789012
=end

  before do
    @run_loop = Libuv::Reactor.new

    install_failsafe_timeout(@run_loop)

    @mock_instream_options = {
      :Port => 14544
    }

    @mock_upstream_options = {
      :Port => 4545
    }

    @called_upstream = 0
    @got_data = 0
    @times = 2 * 1024 * 1024 * 2
    @t = "0"
    @length = @t.length

    @content = [@t] * @times
    @content_length = 0
    @content.each do |chunk|
      @content_length += chunk.length
    end

    @mock_upstream_app = (proc { |env|
      @called_upstream += 1
      [200, {"Content-Type" => "text/plain", "Content-Length" => @content_length.to_s}, @content]
    })

    @logger = Bespoked::Logger.new(STDERR, @run_loop)
    @logger.start
    @mock_upstream_server = Bespoked::LibUVRackServer.new(@run_loop, @logger, @mock_upstream_app, @mock_upstream_options)

    @mock_proxy_controller = Bespoked::ProxyController.new(@run_loop, nil)
    @mock_proxy_controller.vhosts = {
      "localhost" => ["localhost:#{@mock_upstream_options[:Port]}", "127.0.0.1"]
    }

    @http_proxy_server = Bespoked::LibUVHttpProxyServer.new(@run_loop, @logger, @mock_proxy_controller, @mock_instream_options)
  end

  after do
    @run_loop.run do
      @mock_upstream_server.shutdown
      @http_proxy_server.shutdown
      @run_loop.stop
    end

    cancel_failsafe_timeout
  end

  describe "initialize" do
    it "has a libuv runloop" do
      @http_proxy_server.run_loop.must_be_kind_of Libuv::Reactor
    end
  end

  describe "http proxy service" do
    it "redirects and proxies all requests to an upstream http server" do

      @run_loop.run do
        @mock_upstream_server.start
        @http_proxy_server.start
      
        client = @run_loop.tcp

        http_parser = Http::Parser.new
        http_parser.on_headers_complete = proc do
          #@logger.puts [:http_parser, http_parser.inspect, http_parser.headers]

          if http_parser.upgrade_data && http_parser.upgrade_data.length > 0
            #request_to_upstream.concat(http_parser.upgrade_data)
            #@logger.puts [:http_parser_upgrade_data, http_parser.upgrade_data]
          end
        end

        http_parser.on_body = proc do |chunk|
          # One chunk of the body
          #@logger.puts [:on_body, chunk.length]
          @got_data += chunk.length
        end

        http_parser.on_message_complete = proc do |env|
          # Headers and body is all parsed
          @logger.puts [:on_complete, env.inspect, @got_data, (@length * @times * 2)]
          if @got_data == (@length * @times * 2)
            #client.close
          end
        end

        client.catch do |reason|
          @logger.puts [:client_caught_exception, reason]
        end

        client.progress do |chunk|
          #@logger.puts [:called_upstream, @called_upstream, chunk.length, @got_data].inspect

          if chunk && chunk.length > 0
            offset_of_body_left_in_buffer = http_parser << chunk
            body_left_over = chunk[offset_of_body_left_in_buffer, (chunk.length - offset_of_body_left_in_buffer)]
          end
        end

        # close the handle
        client.finally do
          #@logger.puts [:finally]
          @run_loop.stop
        end

        client.connect(Bespoked::DEFAULT_LIBUV_SOCKET_BIND, @mock_instream_options[:Port]) do
          #client.start_tls
          client.start_read

          client.write(MOCK_HTTP_REQUEST, {:wait => :promise}).then { |a|
            #@logger.puts [:wrote_reqs, @called_upstream].inspect
          }
        end
      end

      @called_upstream.must_equal 2
      @got_data.must_equal ((@length * @times * 2))
    end
  end
end
