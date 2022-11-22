#

require 'yajl'
require 'msgpack'
require 'date'
require 'open3'

class Bespoked
  def handle_descript(description)
    @changed = true

    kind = description["kind"]
    name = description["metadata"]["name"]
    created_at = description["metadata"]["creationTimestamp"] ? DateTime.parse(description["metadata"]["creationTimestamp"]) : nil
    deleted_at = description["metadata"]["deletionTimestamp"] ? DateTime.parse(description["metadata"]["deletionTimestamp"]) : nil
    exit_at = deleted_at ? (deleted_at.to_time).to_i : nil
    grace_time = description["metadata"]["deletionGracePeriodSeconds"]
    meta_keys = description["metadata"].keys

    case kind
      when "Pod"
        latest_condition = nil
        phase = nil
        state_keys = nil
        ready = nil
        namespace = description["metadata"]["namespace"]
        status = description["status"]

        #NOTE: this is resolution of pod state algorithm
        #TODO: handle more resolution states for various kinds
        if status
          phase = status["phase"]
          if conditions = status["conditions"]
            latest_condition_in = conditions.sort_by { |a| a["lastTransitionTime"]}.last
            latest_condition = latest_condition_in["type"]
          end

          if status["containerStatuses"]
            state_keys = status["containerStatuses"].map { |f| [f["name"], f["state"].keys.first] }.to_h
            ready = status["containerStatuses"].map { |f| [f["name"], f["ready"]] }.to_h
          end
        end

        @pods ||= {}

        recalc_spec = {
          "latestCondition" => latest_condition,
          "containers" => description["spec"]["containers"],
          "initContainers" => description["spec"]["initContainers"],
          "phase" => phase,
          "ready" => ready,
          "stateKeys" => state_keys,
          "created_at" => created_at.to_time.to_i,
          "exitAt" => exit_at,
          "grace_time" => grace_time
        }

        @pods[name] = recalc_spec

      when "Service"
        @services ||= {}
        spec = description["spec"]
        @services[name] = spec

      when "Ingress"
        @ingresses ||= {}
        spec = description["spec"]
        @ingresses[name] = spec

    end
  end

  def handle_event_list(event)
    items = event["items"]

    if items
      items.each do |item|
        handle_descript(item)
      end
    else
      handle_descript(event)
    end
  end

  def watch!(*kubernetes_resources)
    #TODO: performance, multi kubectl get a,b,c ?
    kubernetes_resources.each { |kubernetes_resource|
      parser = Yajl::Parser.new
      parser.on_parse_complete = method(:handle_event_list)
      io = get_yaml_producer_io(kubernetes_resource)

      @watches ||= {}
      @watches[io] = [kubernetes_resource, parser]
    }
  end

  def rewatch_io(old_io)
    if ab = @watches[old_io]
      Process.wait(old_io.pid) rescue Errno::ECHILD

      kubernetes_resource, old_parser = ab
      puts [:recycling, kubernetes_resource].inspect
      @changed = true

      @watches.delete(old_io)

      watch!(kubernetes_resource)
    end
  end

  def ingest!(&block)
    last_read_bit = nil
    loop do
      begin
        # see whats still running
        io_to_rewatch = @watches.collect { |io, _|
          begin
            Process.kill(0, io.pid)
            Process.waitpid(io.pid, Process::WNOHANG)
            nil
          rescue Errno::ECHILD, Errno::ESRCH
            io
          end
        }.compact

        # rewatched closed bits
        io_to_rewatch.each { |old_io|
          rewatch_io(old_io)
        }

        selectable_io = @watches.collect { |io, _| io }.compact
        a,b,c = IO.select(selectable_io, [], [], 1.0)

        if a
          a.each { |io|
            if ab = @watches[io]
              resource, parser = ab
              last_read_bit = io
              got_read = io.read_nonblock(1)
              parser << got_read
            end
          }
        end

        if a.nil? && @changed
          block.call(@pods, @services, @ingresses)

          @changed = false
        end

      end
    rescue EOFError => eof_err
      rewatch_io(last_read_bit)

      retry
    end
  rescue Interrupt => ctrlc_err
    exit(0)
  end

  def get_yaml_producer_io(kubernetes_resource)
    IO.popen("kubectl get --all-namespaces --watch=true --output=json #{kubernetes_resource}")
  end
end
