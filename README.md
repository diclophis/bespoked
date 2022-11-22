# bespoked - A Ruby/Kube resource stream api

![bespoked](images/bespoked.png)

## example use as nginx ingress controller

The `simple-watch-export-nginx-conf-controller.rb` file contains an example implementation of watching several resources, combined, make up a rudimentary ingress controller

```ruby
client = Bespoked.new

client.watch!("pods", "services", "ingresses")

client.ingest! do |pods, services, ingresses|
  # calculate /etc/nginx/conf.d files based on
  # the collection of pods, services, ingress resources
  # see source for full implementation
end
```

To run, install as start as follows ...

```shell
bundle install --path=vendor/bundle
sudo cp nginx/empty.nginx.conf /etc/nginx/nginx.conf
sudo ruby simple-watch-export-nginx-conf-controller.rb
```

## example streaming kube resources to msgpack stream

The `wkndr-msgpack-dream-machine.rb` and `msgpack-mirror.rb` files outline a sample use case of a real-time bridge of kubernetes resources through a msgpack byte stream
