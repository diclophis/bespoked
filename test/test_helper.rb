ENV['RUBY_ENV'] ||= 'test'

Thread.abort_on_exception = true

require File.expand_path('../../config/environment', __FILE__)

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'

class MiniTest::Spec
  # Add more helper methods to be used by all tests here...

  def install_failsafe_timeout(run_loop, failsafe_after_ms = 3000)
    @did_failsafe_timeout = false

    @failsafe_timeout = run_loop.timer
    @failsafe_timeout.progress do
      @did_failsafe_timeout = true
      run_loop.stop
    end
    @failsafe_timeout.start(failsafe_after_ms)
  end

  def cancel_failsafe_timeout
    @failsafe_timeout.stop

    assert(!@did_failsafe_timeout, "failsafe timeout encountered, please adjust test to safely exit reactor runloop before failing")
  end
end
