#

module Bespoked
  class HealthController
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackServer.new(@run_loop, method(:handle_request), {:Port => 8889})
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK.\r\n"]]
    end
  end
end
