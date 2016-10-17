#

class Watch
  attr_accessor :run_loop, :stdin_pipe

  def initialize(run_loop_in)
    puts :init_watch
    self.run_loop = run_loop_in
  end

  def create(resource_kind, defer, json_parser)
    puts :create, resource_kind, defer
    defer.resolve(true)

    self.stdin_pipe = @run_loop.pipe
    @stdin_pipe.open($stdin.fileno)
    @run_loop.log(:info, :fake_watch, @stdin_pipe)
    @stdin_pipe.progress do |chunk|
      begin
        json_parser << chunk
      rescue Yajl::ParseError => bad_json
        @run_loop.log(:error, :bad_json, [bad_json, chunk])
      end
    end

    @stdin_pipe.start_read

    retry_defer = @run_loop.defer
    watch_timeout = @run_loop.timer
    watch_timeout.start(10000, 0)
    watch_timeout.progress do
      puts :faking_disconnect
      retry_defer.resolve(true)
    end
    return retry_defer.promise
  end
end
