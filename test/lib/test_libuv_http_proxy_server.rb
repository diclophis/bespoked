require_relative '../test_helper'

class LibUVHttpProxyServerTest < MiniTest::Spec
  MOCK_HTTP_REQUEST = <<-HERE
GET / HTTP/1.1
Host: localhost
User-Agent: minitest/ruby
Accept: */*
Connection: close

HERE

  before do
    @run_loop = Libuv::Reactor.new

    #logger = @run_loop.defer
    #@logs = []
    ##@run_loop.run(:UV_RUN_ONCE) do
    #  logger.promise.progress do |log_entry|
    #    @logs << log_entry
    #  end
    ##end

    install_failsafe_timeout(@run_loop)

    @mock_instream_options = {
      :Port => 14544
    }

    @mock_upstream_options = {
      :Port => 4545
    }

    #@stop_mock_servers_defer = @run_loop.defer
    #@stop_mock_servers_defer.promise.then do
    #  puts :cheese
    #  @run_loop.stop
    #end

    @mock_upstream_app = proc { |env|
      #@stop_mock_servers_defer.resolve(true)

      #[200, {"Content-Type" => "text"}, ["example rack handler"]]
      [200, {"Content-Type" => "text/event-stream"}, ["example rack handler"]]
    }

    @mock_upstream_server = Bespoked::LibUVRackServer.new(@run_loop, @mock_upstream_app, @mock_upstream_options)

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
        @mock_upstream_server.start
        @http_proxy_server.start
      
        client = @run_loop.tcp

        client.catch do |reason|
          puts reason.inspect
          #client.shutdown
        end

        client.progress do |data|
          puts [:data, data].inspect
          client.close
          #@mock_upstream_server.shutdown
          #@http_proxy_server.shutdown
          #@run_loop.stop
        end

        # close the handle
        client.finally do
          @run_loop.stop
          #client.close
          #client.shutdown
        end

        client.connect(Bespoked::DEFAULT_LIBUV_SOCKET_BIND, @mock_instream_options[:Port]) do
          client.write(MOCK_HTTP_REQUEST, wait: true)
          client.start_read
        end
      end
    end
  end
end
