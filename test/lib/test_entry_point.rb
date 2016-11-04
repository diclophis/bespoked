require_relative '../test_helper'

class TestEntryPoint < MiniTest::Spec
  before do
    @run_loop = Libuv::Reactor.default
    @bespoked = Bespoked::EntryPoint.new(@run_loop)
    @short_fail_to_authenticate_timeout = 1000
  end

  describe "initialize" do
    it "has an empty database of ingress to service mappings" do
      @bespoked.descriptions.must_equal Hash.new
    end

    it "has a libuv runloop" do
      @bespoked.run_loop.must_be_kind_of Libuv::Reactor
    end
  end

  describe "halt" do
    it "informs run_loop of the intention to stop" do
      @bespoked.halt(:test_halt)
      @bespoked.running?.must_equal false
    end
  end

  describe "install_heartbeat" do
    it "creates a timer that when triggered installs proxy mappings" do
      called_install_proxy = false

      install_proxy_stub = lambda {
        called_install_proxy = true
      }

      @bespoked.stub :install_proxy, install_proxy_stub do
        heartbeat = @bespoked.install_heartbeat
        heartbeat.start(0, 0)

        @run_loop.run

        called_install_proxy.must_equal true
      end
    end
  end

  describe "run_ingress_controller" do
    it "installs heartbeat timer" do
      @bespoked.run_ingress_controller(@short_fail_to_authenticate_timeout)
      @bespoked.heartbeat.must_be_kind_of(Libuv::Timer)
    end

    it "halts after failure to authenticate withing number of ms" do
      @bespoked.run_ingress_controller(@short_fail_to_authenticate_timeout)

      @run_loop.run

      @bespoked.authenticated.must_equal false
    end

    it "continues to run after succeeding to authenticate within a number of ms" do
      @bespoked.run_ingress_controller(@short_fail_to_authenticate_timeout)

      mock_successful_authentication_timer = @run_loop.timer
      mock_successful_authentication_timer.progress do
        @bespoked.resolve_authentication!
      end
      mock_successful_authentication_timer.start(@short_fail_to_authenticate_timeout / 2, 0)

      @run_loop.run

      @bespoked.authenticated.must_equal true
    end
  end
end

=begin
      do
        #unless @bespoked.running?
        #  false.must_equal true
        #end
        #@bespoked.halt(:exit)
      end
=end
