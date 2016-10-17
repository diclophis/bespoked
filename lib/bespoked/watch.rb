#

module Bespoked
  class Watch
    DEBUG_WATCH_TIMEOUT = 30000

    attr_accessor :run_loop

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def create(resource_kind, defer, json_parser)
      @run_loop.log(:info, :debug_watch_create, [resource_kind, defer, json_parser])

      defer.resolve(true)

      retry_defer = @run_loop.defer
      watch_timeout = @run_loop.timer
      watch_timeout.start(DEBUG_WATCH_TIMEOUT, 0)
      watch_timeout.progress do
        retry_defer.resolve(true)
      end

      return retry_defer.promise
    end
  end
end
