#

module Bespoked
  class DashboardController
    attr_accessor :run_loop,
                  :rack_server,
                  :proxy_controller

    def initialize(run_loop_in, proxy_controller_in)
      self.run_loop = run_loop_in
      self.rack_server = LibUVRackServer.new(@run_loop, method(:handle_request), {:Port => 8890})
      self.proxy_controller = proxy_controller_in
    end

    def shutdown
      @rack_server.shutdown
    end

    def start
      @rack_server.start
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["OK. #{@proxy_controller.vhosts.inspect}\r\n"]]
    end
  end
end
