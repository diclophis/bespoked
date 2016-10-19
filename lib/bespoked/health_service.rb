#

module Bespoked
  class HealthService
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8889})
    end

    def start
      @run_loop.log(:info, :health_start, nil)

      @run_loop.next_tick do
        @rack_handler.listen(1024)
      end
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK.\r\n"]]
    end
  end
end
