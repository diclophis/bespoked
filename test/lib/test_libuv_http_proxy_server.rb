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
    @mock_upstream_app = proc { |env|
      #[200, {"Content-Type" => "text"}, ["example rack handler"]]
      @called_upstream += 1
      [200, {"Content-Type" => "text/event-stream"}, ["example rack handler"]]
    }

    @logger = Bespoked::Logger.new(STDERR)
    @mock_upstream_server = Bespoked::LibUVRackServer.new(@run_loop, @logger, @mock_upstream_app, @mock_upstream_options)

    @mock_proxy_controller = Bespoked::ProxyController.new(@run_loop, nil)
    @mock_proxy_controller.vhosts = {
      "localhost" => "localhost:#{@mock_upstream_options[:Port]}"
    }

    @http_proxy_server = Bespoked::LibUVHttpProxyServer.new(@run_loop, nil, @mock_proxy_controller, @mock_instream_options)
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

#< HTTP/1.1 302 Moved Temporarily
#< Server: nginx
#< Date: Tue, 29 Nov 2016 03:23:25 GMT
#< Content-Type: text/html
#< Connection: keep-alive
#< Content-Length: 154
#< Location: https://medium.com/foo/@mavenlink

  describe "http proxy service" do
    it "redirects and proxies all requests to an upstream http server" do
      @run_loop.run do
        @logger.start(@run_loop)
        @mock_upstream_server.start
        @http_proxy_server.start
      
        client = @run_loop.tcp

        client.catch do |reason|
          #client.shutdown
        end

        client.progress do |data|
          @logger.puts [:called_upstream, @called_upstream].inspect
        end

        # close the handle
        client.finally do
          @run_loop.stop
        end

        client.connect(Bespoked::DEFAULT_LIBUV_SOCKET_BIND, @mock_instream_options[:Port]) do
          client.write(MOCK_HTTP_REQUEST, wait: true)
          client.start_read
        end
      end

      @called_upstream.must_equal 2
    end
  end
end
