#

module Bespoked
  class Promise
    def promise
      Progress.new
    end

    def notify(*args)
      puts [:pnoti, args].inspect
      return "pnoti"
    end
  end

  class Progress
    def progress(*args)
      return "bib"
    end
  end

  class Pipe
    def open(*args)
      return "popen"
    end

    def close(*args)
      return "pclos"
    end

    def shutdown(*args)
      return "pshut"
    end
  end

  class Then
    attr_accessor :args
    attr_accessor :on_then

    def initialize(*args)
      self.args = args
    end

    def then(&block)
      puts [:tthen, @args, block].inspect

      self.on_then = block

      return Catch.new
    end
  end

  class Catch
    def catch(*args)
      puts [:ccatch, args].inspect
    end
  end

  class Tcp
    attr_accessor :flags
    attr_accessor :io
    attr_accessor :on_progress
    attr_accessor :on_accept
    attr_accessor :output_buffer
    attr_accessor :input_buffer
    attr_accessor :write_thens

    def initialize(args = {})
      self.flags = args[:flags]
      self.input_buffer, self.output_buffer = IO.pipe
      self.write_thens = []
    end

    def to_io
      self.io
    end

    def peername
      [@io.remote_address.ip_port, @io.remote_address.ip_address]
    end

    def snap(io)
      self.io = io
      self
    end

    def open(*args)
      puts [:topen]

      return "topen"
    end

    def catch(*args)
      puts [:tcatch]

      return "tcatch"
    end

    def bind(*args, &block)
      puts [:tbind, self.object_id, args, block].inspect
      #"0:0:0:0:0:0:0:0", 55003
      self.io ||= TCPServer.new(args[0], args[1])

      #Thread.new do
      #  #IO::EAGAINWaitReadable
      #  #yield Tcp.new.snap(self.io.accept_nonblock)
      #  begin
      #    while true do

      self.on_accept = block

      #      yield Tcp.new.snap(self.io.accept)
      #    end
      #  rescue IOError => e
      #    #puts [:accepte, e].inspect
      #  end
      #end

      return "tbind"
    end

    def connect(*args)
      puts [:tconn, args].inspect
      @io ||= TCPSocket.new(args[0], args[1])

      yield

      return "tconn"
    end

    def start_read
      puts :start_read
    end

    def write(chunk, other = nil)
      #puts [:write_buffer, chunk, other].inspect
      @output_buffer.write_nonblock(chunk)
      new_then = Then.new
      self.write_thens << new_then
      new_then
    end

    def perform_write_callbacks
      #if @io.is_a?(TCPSocket)
        while output_ready_to_be_written = @input_buffer.read_nonblock(1024)
          #puts [:write_nonblock, output_ready_to_be_written].inspect
          @io.write_nonblock(output_ready_to_be_written)
        end
      #end
    rescue IO::EAGAINWaitReadable => e
      #puts [:write_call, e].inspect

        #puts :wtf2

        #if @input_buffer.eof?
          @write_thens.each do |write_then|
            puts :write_thens
            write_then.on_then.call(nil) if write_then.on_then
          end

          self.write_thens = [] #@write_thens.empty!
        #end
    end

    def listen(*args)
      #puts [:tlist].inspect

      return nil
    end

    def close(*args)
      puts [:tclos, self.object_id, args].inspect
      @io.close

      return "tclos"
    end

    def closed?
      @io && @io.closed?
    end

    def eof?
      @io.eof?
    end

    def shutdown(*args)
      return "tshut"
    end

    def progress(*args, &block)
      #Thread.new do
      #  while true
      #    if @io
      #      yield @io.recv(1024)
      #    else
      #      puts [:noio].inspect
      #    end
      #  end
      #end
      self.on_progress = block

      return "tprog #{args}"
    end

    def perform_read_callbacks
      if @io.is_a?(TCPServer)
        if @on_accept
          $stderr.write("R")

          new_raw_io = @io.accept_nonblock
          new_io = Tcp.new.snap(new_raw_io)

          @on_accept.call(new_io) if @on_accept

          return new_io
        end

        nil
      else
        if @on_progress
          if recvd = @io.read_nonblock(1024)
            if recvd.length > 0
              puts [:recvd, @on_progress].inspect
              @on_progress.call(recvd)
            end
          end
        end

        nil
      end
    rescue EOFError => e
      @io.close
    rescue IOError => e
      puts [:read_call, e].inspect
    end

    def finally(*args)
      return "tfina #{args}"
    end
  end

  class Timer
    attr_accessor :active

    def initialize(args = {})
      puts [:tinit, args].inspect

    end

    def active?
      @active
    end

    def stop(*args)
      return "bab"
    end

    def start(*args)
      return "boo"
    end

    def progress(*args)
      return "biz"
    end
  end

  class Notifier
    def notifier(*args)
      puts [:nnotifer, args].inspect
    end
  end

  class RunLoop
    attr_accessor :notifier
    attr_accessor :ios

    def initialize
      self.notifier = Notifier.new
      self.ios = []
    end

    def timer(*args)
      Timer.new(*args)
    end

    def run(*args)
      puts args.inspect

      #sleep 1

      #Thread.new do

      yield @notifier

      #end.join

      #sleep 10

      #raw_ios = @ios.collect { |io| io.io }
      all_io_open = proc {
        @ios.all? { |io| !io.closed? }
      }

      while all_io_open.call
        $stderr.write("l")
        not_nil = @ios.reject { |io| io.io.nil? || io.io.closed? }
        readable, writable, errored = IO.select(not_nil, not_nil, not_nil, 10000)
        readable.each do |readable_io|
          if new_io = readable_io.perform_read_callbacks
            @ios << new_io
          end
        end

        writable.each do |writable_io|
          writable_io.perform_write_callbacks
        end

        puts [errored].inspect if errored.length > 0
      end

      return nil
    end

    def stop(*args)
      puts args.inspect
      return "rstop"
    end

    def defer(*args)
      Promise.new
    end

    def pipe(*args)
      Pipe.new
    end

    def tcp(*args)
      puts args.inspect
      new_io = Tcp.new(*args)
      self.ios << new_io
      new_io
    end

    def next_tick(*args)
      puts [:rntic, args].inspect
      yield
    end

    def work(*args)
      puts [:rwork, args].inspect
      yield
    end

    def finally(*args)
      puts [:finally, args].inspect
      Then.new(*args)
    end
  end
end
