#

module Bespoked
  class Dashboard
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request), {:Port => 8890})
    end

    def start
      @run_loop.log(:info, :dashboard_start, nil)

      @run_loop.next_tick do
        @rack_handler.listen(1024).inspect
      end
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["Dashboard\r\n"]]
    end
  end
end
