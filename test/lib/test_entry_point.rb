require_relative '../test_helper'

class TestEntryPoint < MiniTest::Spec
  before do
    @run_loop = Libuv::Reactor.new
    @bespoked = Bespoked::EntryPoint.new(@run_loop)
    @short_timeout = 10
    @never_timeout = 99999
    @failsafe_timeout = install_failsafe_timeout(@run_loop)
  end

  after do
    cancel_failsafe_timeout(@failsafe_timeout)
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

  describe "connect" do
    it "disconnects all watches and reconnects them" do
      #assert !mock_watch.
    end
  end

  describe "run_ingress_controller" do
    it "installs heartbeat timer" do
      @bespoked.run_ingress_controller(@short_timeout)
      @bespoked.heartbeat.must_be_kind_of(Libuv::Timer)
    end

    it "halts after failure to authenticate within number of ms" do
      did_fail_to_auth_timeout = false

      on_failed_to_auth_cb_stub = lambda { |*args|
        did_fail_to_auth_timeout = true
      }

      @bespoked.stub :on_failed_to_auth_cb, on_failed_to_auth_cb_stub do
        assert(!@bespoked.authenticated)

        @run_loop.run do
          @bespoked.run_ingress_controller(@short_timeout, @never_timeout)

          active_at_start_of_run = @bespoked.failure_to_auth_timer.active?
          assert(active_at_start_of_run)

          on_failed_to_auth_cb_check_idle = @run_loop.idle
          on_failed_to_auth_cb_check_idle.progress do
            if did_fail_to_auth_timeout
              @run_loop.stop
            end
          end
          on_failed_to_auth_cb_check_idle.start
        end

        assert(!@bespoked.authenticated)
      end
    end

    it "continues to run after succeeding to authenticate within a number of ms" do
      @run_loop.run do
        @bespoked.run_ingress_controller(@short_timeout)

        active_at_start_of_run = @bespoked.failure_to_auth_timer.active?
        assert(active_at_start_of_run)

        @bespoked.resolve_authentication!

        active_at_end_of_run = @bespoked.failure_to_auth_timer.active?
        assert(!active_at_end_of_run)

        assert(@bespoked.authenticated)
      end
    end

    it "reconnects every reconnect interval" do
      times_reconnected = 0

      on_reconnect_cb_stub = lambda { |*args|
        times_reconnected += 1
      }

      @bespoked.stub :on_reconnect_cb, on_reconnect_cb_stub do

        @run_loop.run do

          @bespoked.run_ingress_controller(@never_timeout, @short_timeout)

          on_reconnect_cb_check_idle = @run_loop.idle
          on_reconnect_cb_check_idle.progress do
            if times_reconnected > 5
              @run_loop.stop
            end
          end
          on_reconnect_cb_check_idle.start

        end
      end

      times_reconnected.must_equal 6
    end
  end
end
