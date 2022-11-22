#

require './lib/bespoked'

client = Bespoked.new

client.watch!("pods", "services", "ingresses", "deployments", "jobs", "replicasets", "cronjobs")

client.ingest! do |pods, services, ingresses, deployments, jobs, replicasets, cronjobs|
  puts pods.to_msgpack
end
