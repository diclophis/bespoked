require_relative '../test_helper'

class LibUVHttpProxyServerTest < MiniTest::Spec
  before do
    @run_loop = Libuv::Reactor.new

    logger = @run_loop.defer
    @logs = []

    @run_loop.run(:UV_RUN_ONCE) do
      logger.promise.progress do |log_entry|
        @logs << log_entry
      end
    end

    install_failsafe_timeout(@run_loop)

    #@short_timeout = 10
    #@never_timeout = 99999

    @http_proxy_server = Bespoked::EntryPoint.new(@run_loop, logger)
  end

  after do
    #TODO: puts @logs.inspect
    cancel_failsafe_timeout
  end

  describe "initialize" do
    it "has a libuv runloop" do
      @http_proxy_server.run_loop.must_be_kind_of Libuv::Reactor
    end
  end
end
