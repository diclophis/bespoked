#

module Bespoked
  class HealthController
    attr_accessor :run_loop,
                  :logger,
                  :rack_server

    def initialize(run_loop_in, logger_in)
      self.run_loop = run_loop_in
      self.logger = logger_in
      self.rack_server = LibUVRackServer.new(@run_loop, logger_in, method(:handle_request), {:Port => 55002})
    end

    def shutdown
      @rack_server.shutdown
    end

    def start
      @rack_server.start
    end

    def handle_request(env)
      #@logger.notify(:health => env)

      ['200', {'Content-Type' => 'text/html', 'Connection' => 'close'}, ["OK.\r\n"]]
    end
  end
end
