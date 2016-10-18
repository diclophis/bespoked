#

module Bespoked
  class DebugWatch < Watch
    attr_accessor :run_loop

    def initialize(run_loop_in)
      self.run_loop = run_loop_in
    end

    def create(resource_kind, defer, json_parser)
      defer.resolve(true)

      [
        {
          "type": "ADDED",
          "object": {
              "kind": "Ingress",
              "apiVersion": "extensions/v1beta1",
              "metadata": {
                  "name": "z04b6f-ven-unicorn-vhost",
                  "resourceVersion": "20361",
                  "labels": {
                      "ttl": "24"
                  },
                  "annotations": {
                  }
              },
              "spec": {
                  "rules": [
                      {
                          "host": "z437a2-d-ldm-update-6796.instastage.cash",
                          "http": {
                              "paths": [
                                  {
                                      "backend": {
                                          "serviceName": "bardin.haus",
                                          "servicePort": 80
                                      }
                                  }
                              ]
                          }
                      }
                  ]
              },
              "status": {
                  "loadBalancer": {}
              }
          }
        },
        {
          "type": "ADDED",
          "object": {
              "kind": "Service",
              "apiVersion": "v1",
              "metadata": {
                  "name": "z494d5-bigmaven-unicorn",
                  "resourceVersion": "20289",
                  "labels": {
                      "ttl": "24"
                  },
                  "annotations": {
                  }
              },
              "spec": {
                  "ports": [
                      {   
                          "protocol": "TCP",
                          "port": 3001,
                          "targetPort": 3001
                      }
                  ],
                  "selector": {
                      "name": "zbea5d-d-ldm-update-6796"
                  },
                  "clusterIP": "10.254.145.20",
                  "type": "ClusterIP",
                  "sessionAffinity": "None"
              },
              "status": {
                  "loadBalancer": {}
              }
          }
        }
      ].each do |obj|
        json_parser << Yajl::Encoder.encode(obj)
      end

      retry_defer = @run_loop.defer
      return retry_defer.promise
    end
  end
end
