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

    #@run_loop.run(:UV_RUN_NOWAIT) do
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

        [200, {"Content-Type" => "text"}, ["example rack handler"]]
      }

      @mock_upstream_server = Bespoked::LibUVRackServer.new(@run_loop, @mock_upstream_app, @mock_upstream_options)

      @mock_proxy_controller = Bespoked::ProxyController.new(@run_loop, nil)
      @mock_proxy_controller.vhosts = {
        "localhost" => "localhost:#{@mock_upstream_options[:Port]}"
      }

      @http_proxy_server = Bespoked::LibUVHttpProxyServer.new(@run_loop, nil, @mock_proxy_controller, @mock_instream_options)

      puts :before
    #end
=begin
=end
  end

  after do
    puts :canceling_timeout
    cancel_failsafe_timeout

    #@run_loop.run(:UV_RUN_NOWAIT) do
    #10.times do
    @run_loop.run do
    #  @run_loop.run(:UV_RUN_ONCE) do
        @mock_upstream_server.shutdown
    #  end

    #  @run_loop.run(:UV_RUN_ONCE) do
        @http_proxy_server.shutdown
    #  end
    #  sleep 1
      @run_loop.stop
    end

    #@mock_entry_point.halt :stopping_tests
    #@run_loop.stop
    #@run_loop = nil

    #TODO: puts @logs.inspect
    #@run_loop.stop
    #end


    #@run_loop.run

    puts :afterd
  end

  describe "initialize" do
    it "has a libuv runloop" do
      puts :with_out
      #@http_proxy_server.run_loop.must_be_kind_of Libuv::Reactor
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
      puts :with
        @run_loop.run do

    @run_loop.run(:UV_RUN_ONCE) do
      @mock_upstream_server.start
    end

    @run_loop.run(:UV_RUN_ONCE) do
      @http_proxy_server.start
    end
        
        if false
          @run_loop.stop
        else
        #@run_loop.run do
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
            puts :finally
            puts @run_loop.inspect
            @run_loop.stop
            #client.close
            #client.shutdown
          end

          client.connect(DEFAULT_LIBUV_SOCKET_BIND, @mock_instream_options[:Port]) do
            puts :connected

            client.write(MOCK_HTTP_REQUEST, wait: true)
            client.start_read
          end
        end

        end
    end
  end
end
