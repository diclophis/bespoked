#

module Bespoked
  class HealthController
    attr_accessor :run_loop,
                  :rack_server

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_server = LibUVRackServer.new(@run_loop, method(:handle_request), {:Port => 8889})
    end

    def shutdown
      @rack_server.shutdown
    end

    def start
      @rack_server.start
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK.\r\n"]]
    end
  end
end
