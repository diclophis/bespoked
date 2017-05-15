#

class Watch
  attr_accessor :run_loop,
                :json_parser,
                :on_event_cb,
                :waiting_for_authentication,
                :waiting_for_authentication_promise,
                :client,
                :rebop

  def initialize(run_loop_in)
    self.run_loop = run_loop_in
    self.waiting_for_authentication = @run_loop.defer
    self.waiting_for_authentication_promise = @waiting_for_authentication.promise
  end

  def on_event(&blk)
    self.on_event_cb = blk
  end

  def restart
    self.json_parser = Yajl::Parser.new
    json_parser.on_parse_complete = proc { |a|
      @on_event_cb.call(a) if @on_event_cb
    }
  end

  def shutdown
    @client.shutdown if @client
    @rebop.stop if @rebop
  end
end
