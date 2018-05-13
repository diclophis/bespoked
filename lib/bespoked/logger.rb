$global_logger = nil

module Bespoked
  class Logger < ::Logger
    def initialize(io_in, run_loop_in)
      @io = io_in
      @run_loop = run_loop_in
      $global_logger = self
      @libuv_logger = @run_loop.defer

      @promise = @libuv_logger.promise

      @promise.progress do |log_entry|
        #if @pipe
        #  @pipe.write(log_entry)
        #  @pipe.write($/)
        #else
        #  @libuv_logger.notify(log_entry)
        #end
      end
    end

    def start
      #$stdout.puts "??3"
      @pipe = @run_loop.pipe
      @pipe.open(@io.fileno)
    end

    def shutdown
      #$stdout.puts "??3"
      @pipe.shutdown
    end

    def add(sev, thing, msg)
      #$stderr.puts [sev, thing, msg].inspect

      #@libuv_logger.notify(msg)

      false
    end

    def notify(*args)
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
      #@pipe.flush
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
