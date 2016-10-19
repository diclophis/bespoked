#

module Bespoked
  class HealthService
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def start
      self.rack_handler = LibUVRackHandler.new(@run_loop, method(:handle_request), {:Port => 8889})
      @run_loop.log(:info, :health_start, nil)
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK.\r\n"]]
    end
  end
end
