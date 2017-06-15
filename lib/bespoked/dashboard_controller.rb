#

module Bespoked
  class DashboardController
    attr_accessor :run_loop,
                  :logger,
                  :rack_server,
                  :proxy_controller

    def initialize(run_loop_in, logger_in, proxy_controller_in)
      self.run_loop = run_loop_in
      self.logger = logger_in
      self.proxy_controller = proxy_controller_in
      self.rack_server = LibUVRackServer.new(@run_loop, logger_in, method(:handle_request), {:Port => 55003})
    end

    def shutdown
      @rack_server.shutdown
    end

    def start
      @rack_server.start
    end

    def handle_request(env)
      @logger.notify(:dashboard => env)

      ['200', {'Content-Type' => 'text/html'}, ["OK. #{@proxy_controller.vhosts.inspect}\r\n"]]
    end
  end
end
