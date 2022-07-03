#

require './lib/bespoked'

client = Bespoked.new

client.watch!("pods", "services", "ingresses", "deployments", "jobs", "replicasets", "cronjobs")

client.ingest! do |pods, services, ingresses, deployments, jobs, replicasets, cronjobs|
#  puts pods.inspect
#  def pod(*args)
#    sleep 0.1
#    namespace, name, latest_condition, phase, container_readiness, container_states, created_at, exit_at, grace_time = *args
#    $stdout.write([namespace, name, latest_condition, phase, container_readiness, container_states, created_at, exit_at, grace_time].to_msgpack)
#    $stdout.flush
#  end

  puts pods.to_msgpack
end
