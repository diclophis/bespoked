ENV['RUBY_ENV'] ||= 'test'

Thread.abort_on_exception = true

require File.expand_path('../../config/environment', __FILE__)

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'

class MiniTest::Spec
  # Add more helper methods to be used by all tests here...

  def install_failsafe_timeout(run_loop, failsafe_after_ms = 1000)
    failsafe_timeout = run_loop.timer
    failsafe_timeout.progress do
#      assert(false, "failsafe timeout reached")

      run_loop.stop

=begin
      run_loop.prepare {
        #if bespoked.stopping
        #  #TODO: this should maybe not be needed if we clean up everything ok?
          run_loop.stop
        #end
      }.start
      puts "#{run_loop.inspect}"
=end

    end
    failsafe_timeout.start(failsafe_after_ms)

    failsafe_timeout
  end

  def cancel_failsafe_timeout(timeout)
    timeout.stop
  end
end
