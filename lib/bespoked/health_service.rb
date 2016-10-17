#

module Bespoked
  class HealthService
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8182})
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK"]]
    end
  end
end
