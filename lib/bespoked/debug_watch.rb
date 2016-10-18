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
                  "name": "example-vhost",
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
                          "host": "example.ingress",
                          "http": {
                              "paths": [
                                  {
                                      "backend": {
                                          "serviceName": "w3.org",
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
                  "name": "w3.org",
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
                          "port": 80,
                          "targetPort": 80
                      }
                  ],
                  "selector": {
                      "name": "www.w3.org"
                  },
                  "clusterIP": "127.0.0.1",
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
