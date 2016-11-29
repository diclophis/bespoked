#

module Bespoked
  class DebugWatchFactory < WatchFactory
    DEBUG_JSON_STREAM =
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
    ]

    def create(resource_kind, authentication_timeout = 100)
      http_ok = false
      retries = 0

      new_watch = Watch.new(@run_loop)

      fake_authentication_timeout = @run_loop.timer
      fake_authentication_timeout.progress do
        retries += 1
        http_ok = (retries > 3)

        if http_ok
          new_watch.waiting_for_authentication.resolve(http_ok)

          fake_authentication_timeout.stop

          DEBUG_JSON_STREAM.each do |obj|
            new_watch.json_parser << Yajl::Encoder.encode(obj)
          end
        end
      end
      fake_authentication_timeout.start(0, authentication_timeout)

      return new_watch
    end
  end
end
