#

module Bespoked
  class Dashboard
    attr_accessor :run_loop,
                  :rack_handler

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
      self.rack_handler = LibUVRackHandler.run(@run_loop, method(:handle_request))
    end

    def handle_request(env)
      ['200', {'Content-Type' => 'text/html'}, ["A barebones rack app. #{self.inspect}"]]
    end
  end
end
