#

module Bespoked
  class WatchFactory
    DEBUG_WATCH_TIMEOUT = 30000

    attr_accessor :run_loop

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def create(resource_kind, authentication_timeout = 1)
      raise

=begin
      @run_loop.log(:info, :debug_watch_create, [resource_kind, defer, json_parser])

      defer.resolve(true)

      retry_defer = @run_loop.defer
      watch_timeout = @run_loop.timer
      watch_timeout.start(DEBUG_WATCH_TIMEOUT, 0)
      watch_timeout.progress do
        retry_defer.resolve(true)
      end

      return retry_defer.promise
=end
    end

    def path_for_watch(kind)
      #TODO: add resource very query support e.g. ?resourceVersion=0
      path_prefix = "/%s/watch/namespaces/default/%s"
      path_for_watch = begin
        case kind
          when "pods"
            path_prefix % ["api/v1", "pods"]

          when "services"
            path_prefix % ["api/v1", "services"]

          when "ingresses"
            path_prefix % ["apis/extensions/v1beta1", "ingresses"]

          when "endpoints"
            path_prefix % ["api/v1", "endpoints"]

        else
          raise "unknown api Kind to watch: #{kind}"
        end
      end

      path_for_watch
    end
  end
end
