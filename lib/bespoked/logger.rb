$global_logger = nil

module Bespoked
  class Logger < ::Logger
    def initialize(io)
      @io = io
      $global_logger = self
      $stdout.puts "??2"
    end

    def start(run_loop)
      $stdout.puts "??3"
      @stdout_pipe = run_loop.pipe
      @stdout_pipe.open(@io.fileno)

      @libuv_logger = run_loop.defer
      @libuv_logger.promise.progress do |log_entry|
      $stdout.puts "??"
      @stdout_pipe.write(log_entry)
      @stdout_pipe.write($/)
      end
    end

    def add(sev, thing, msg)
        $stdout.puts "??5#{msg}"
      @libuv_logger.notify(msg)
      false
    end

    def notify(*args)
        $stdout.puts "??4"
      add(1, nil, args.inspect)
    end

		#puts must be called with a single argument that responds to to_s.
		def puts(str)
			add(1, nil, str.to_s)
		end

		#write must be called with a single argument that is a String.
		def write(str)
			add(1, nil, str)
		end

		#flush must be called without arguments and must be called in order to make the error appear for sure.
		def flush
			#add(1, nil, "flush")
      #@stdout_pipe.flush
		end

		#close must never be called on the error stream.
		#def close
		#end

=begin
    def formatter(*args)
      @formatter
    end

    def info(*args)
      @logger.notify(args)
    end

    def debug(*args)
      @logger.notify(args)
    end

    def fatal(*args)
      @logger.notify(args)
    end

    def error(*args)
      @logger.notify(args)
    end

    #def info?(*args)
    #  true
    #end
=end
  end
end
