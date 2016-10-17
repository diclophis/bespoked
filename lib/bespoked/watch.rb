#

module Bespoked
  class Watch
    DEBUG_WATCH_TIMEOUT = 30000

    attr_accessor :run_loop

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def create(resource_kind, defer, json_parser)
      defer.resolve(true)

      combined = ["ssh", "provision@jenkins-master01.staging.mavenlink.net", "kubectl", "get", "-o=json", "-w", resource_kind]
      stdin, stdout, stderr, process_waiter = Open3.popen3(*combined)

      stdout_pipe = @run_loop.pipe
      stderr_pipe = @run_loop.pipe

      stdout_pipe.open(stdout.fileno)
      stderr_pipe.open(stderr.fileno)

      stdout_pipe.progress do |chunk|
        begin
          json_parser << chunk
        rescue Yajl::ParseError => bad_json
          @run_loop.log(:error, :bad_json, [bad_json, chunk])
        end
      end

      stdout_pipe.start_read

=begin
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
=end

      retry_defer = @run_loop.defer
      watch_timeout = @run_loop.timer
      watch_timeout.start(DEBUG_WATCH_TIMEOUT, 0)
      watch_timeout.progress do
        Process.kill("INT", process_waiter.pid)
        process_waiter.kill
        process_waiter.join

        retry_defer.resolve(true)
      end

      return retry_defer.promise
    end
  end
end
