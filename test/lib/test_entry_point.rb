require_relative '../test_helper'

class TestEntryPoint < MiniTest::Spec
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

    @short_timeout = 10
    @never_timeout = 99999
    @bespoked = Bespoked::EntryPoint.new(@run_loop, logger)
  end

  after do
    #TODO: puts @logs.inspect
    @bespoked.halt :stopping_tests
    cancel_failsafe_timeout
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
      called_install_ingress_into_proxy_controller = false

      install_ingress_into_proxy_controller_stub = lambda {
        called_install_ingress_into_proxy_controller = true
        @run_loop.stop
      }

      @bespoked.stub :install_ingress_into_proxy_controller, install_ingress_into_proxy_controller_stub do
        heartbeat = @bespoked.install_heartbeat
        heartbeat.start(0, 0)

        @run_loop.run

        called_install_ingress_into_proxy_controller.must_equal true
      end
    end
  end

  describe "connect" do
    it "disconnects all watches and reconnects them" do
      defer_authentication = @run_loop.defer
      promise_authentication = defer_authentication.promise

      mock_watch = Minitest::Mock.new
      mock_watch.expect :restart, true
      mock_watch.expect :on_event, true
      mock_watch.expect :waiting_for_authentication_promise, promise_authentication

      did_fail_to_auth_timeout = false

      on_failed_to_auth_cb_stub = lambda { |*args|
        did_fail_to_auth_timeout = true
        @run_loop.stop
      }

      @bespoked.stub :on_failed_to_auth_cb, on_failed_to_auth_cb_stub do
        @run_loop.run do
          @bespoked.install_watch(mock_watch)

          @bespoked.run_ingress_controller(@short_timeout, nil)
        end
      end

      mock_watch.verify

      #puts [:resolved?, promise_authentication.resolved?].inspect
    end
  end

  describe "run_ingress_controller" do
    it "installs heartbeat timer" do
      @bespoked.run_ingress_controller(@short_timeout)
      @bespoked.heartbeat.must_be_kind_of(Libuv::Timer)
    end

    it "halts after failure to authenticate within number of ms" do
      did_fail_to_auth_timeout = false
      did_try_to_connect = false

      on_failed_to_auth_cb_stub = lambda { |*args|
        did_fail_to_auth_timeout = true
      }

      will_try_to_connect = lambda { |*args|
        did_try_to_connect = true
      }

      @bespoked.stub :on_failed_to_auth_cb, on_failed_to_auth_cb_stub do
        @bespoked.stub :connect, will_try_to_connect do
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

          assert(did_try_to_connect, "should have tried to connect")
          assert(!@bespoked.authenticated, "should not be authenticated")
        end
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

        @run_loop.stop
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
