# bespoked - A Ruby Kubernetes ingress controller

![bespoked](images/bespoked.png)

## experimental in-cluster dev workflow

`kubectl create configmap ingress-controller --from-file=ingress-controller.rb`, then just use:

        command: [ "bundle", "exec", "/code/ingress-controller.rb" ]
        volumeMounts:
        - name: config-volume
          mountPath: /code
    volumes:
      - name: config-volume
        configMap:
          name: ingress-controller

kubectl create configmap ingress-controller --from-file=ingress-controller.rb --dry-run -o yaml | kubectl replace configmap ingress-controller -f -
