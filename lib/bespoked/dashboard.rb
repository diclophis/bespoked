#

module Bespoked
  class Dashboard
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def start
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8890})
      @rack_handler.listen(16)
      @run_loop.log(:info, :dashboard_start, nil)
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["Dashboard\r\n"]]
    end
  end
end
