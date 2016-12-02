ENV['RUBY_ENV'] ||= 'test'

Thread.abort_on_exception = true

require File.expand_path('../../config/environment', __FILE__)

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/spec'
require 'minitest/mock'

reporter_options = { color: true, slow_count: 5 }
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(reporter_options)]

class MiniTest::Spec
  # Add more helper methods to be used by all tests here...

  def install_failsafe_timeout(run_loop, failsafe_after_ms = 3000)
    #run_loop.run(:UV_RUN_NOWAIT) do
      @did_failsafe_timeout = false

      @failsafe_timeout = run_loop.timer
      @failsafe_timeout.progress do
        @did_failsafe_timeout = true
        run_loop.stop
      end
      @failsafe_timeout.start(failsafe_after_ms)
    #end
    puts :install
  end

  def cancel_failsafe_timeout
    #@run_loop.run(:UV_RUN_NOWAIT) do
    puts :wtf
        #@run_loop.run do
          @failsafe_timeout.stop
        #end
    puts :wtfd
    #end

    assert(!@did_failsafe_timeout, "failsafe timeout encountered, please adjust test to safely exit reactor runloop before failing")
  end
end
