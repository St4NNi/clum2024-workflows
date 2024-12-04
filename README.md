## CLUM 2024 Workflows

### Argo Workflows  

[Argo Workflows](https://argoproj.github.io/workflows/) is a Kubernetes native workflow engine that fully integrates in the Kubernetes cluster.

A simple workflow:
```yaml

apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-  # Name of this Workflow
spec:
  entrypoint: hello-world     # Defines "hello-world" as the "main" template
  templates:
  - name: hello-world         # Defines the "hello-world" template
    container:
      image: busybox
      command: [echo]
      args: ["hello world"]
```

Since all resources are built-into the cluster you can just use `kubectl` and the Kubernetes API to manage them.

```bash

kubectl apply -f workflow.yaml
```


Argo has different template types:

Like script:

```yaml
  - name: gen-random-int
    script:
      image: python:alpine3.6
      command: [python]
      source: |
        import random
        i = random.randint(1, 100)
        print(i)
```

or K8s resource:

```yaml

  - name: k8s-owner-reference
    resource:
      action: create
      manifest: |
        apiVersion: v1
        kind: ConfigMap
        metadata:
          generateName: owned-eg-
        data:
          some: value
```

Templates:

Step based templates

```yaml
  - name: hello-hello-hello
    steps:
    - - name: step1
        template: prepare-data
    - - name: step2a
        template: run-data-first-half
      - name: step2b
        template: run-data-second-half
```

DAG based templates

```yaml

  - name: diamond
    dag:
      tasks:
      - name: A
        template: echo
      - name: B
        dependencies: [A]
        template: echo
      - name: C
        dependencies: [A]
        template: echo
      - name: D
        dependencies: [B, C]
        template: echo

```

Play around with it and see: https://github.com/argoproj/argo-workflows/tree/main/examples
For a lot more examples.

Argo UI:

Get a Bearer Token:

```bash
ARGO_TOKEN="Bearer $(kubectl get secret -n argo workflows.service-account-token -o=jsonpath='{.data.token}' | base64 --decode)"
```

Port forward the Dashboard:

```bash
kubectl port-forward -n argo services/argo-server 2746:2746
```

Login via local browser on:

http://localhost:2746


### Nextflow

#### Creating a nextflow workflow


#### Prerequisites

Create a service account in your namespace:

`kubectl create sa nextflow -n <yournamespace>`
```

apiVersion: v1
kind: ServiceAccount
metadata:
  name: nextflow
  namespace: <yournamespace>

```


Create a role to create watch and update pods:


`kubectl create role pod-creator -n <yournamespace> --verb=get,list,update,create,delete,watch --resource=pods,pods/status`

```

apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: <yournamespace>
  name: pod-creator
rules:
- apiGroups: [""]
  resources: ["pods", "pods/status"]
  verbs: ["create", "get", "watch", "list", "update", "patch", "delete"]

```


Add a RoleBinding to your ServiceAccount

`kubectl create rolebinding pod-creator -n <yournamespace> --role=pod-creator --serviceaccount=<yournamespace>:nextflow`

```
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-creator
  namespace: <yournamespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-creator
subjects:
- kind: ServiceAccount
  name: nextflow
  namespace: <yournamespace>
```





#### New way of running nextflow on K8s


Run an in-cluster nextflow pod:

```
kubectl run nextflow --overrides='{ "spec": { "serviceAccount": "nextflow" }  }' --rm -i --tty --image=nextflow/nextflow:24.10.2 -- /bin/bash
```



Create a nextflow.config


```

process {
    executor = 'k8s'
}

aws {
    accessKey = 'minio'
    secretKey = 'miniopwd'
    client {
        endpoint = 'http://minio-service.minio.svc.cluster.local:9000'
        s3PathStyleAccess = true
    }
}

wave {
    enabled = true
}

fusion {
    enabled = true
    exportStorageCredentials = true
}

k8s {
    namespace = '<yournamespace>'
    serviceAccount = 'nextflow'
}

```


Copy or create your nextflow workflow file:


```
#! /usr/bin/env nextflow

greetings = params.input.toLowerCase().split(',')
System.out.println(greetings.size())
System.out.println(greetings)
greeting_ch = Channel.from(greetings)


process splitLetters{

    container 'ubuntu'

    input:
    val x

    output:
    path 'chunk_*'

    """
    printf '$x' | split -b 6 - chunk_
    """
}

process convertToUpper{

    container 'ubuntu'

    input:
    file x

    output:
    stdout

    """
    cat $x | tr '[a-z]' '[A-Z]'
    """
}

workflow{
    words_ch = splitLetters(greeting_ch)
    result_ch = convertToUpper(words_ch.flatten())
    result_ch.view{it}
}
```



Run the workflow:

```
nextflow run workflow.nf --input foo,bar,baz -work-dir s3://test/scratch
```


#### Old way to schedule nextflow jobs

Nextflow config

```

process {
    executor = 'k8s'
}

k8s {
    storageClaimName = 'nextflow-rw-many'
    storageMountPath = '/workspace'
}

```

A `ReadWriteMany` storage provider and PVC must be in place.
You can use NFS for this. The NFS volume must be mounted to the same
place as your workflow path.


```yaml

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextflow-rw-many
spec:
  storageClassName: nfs-storage
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi

---

apiVersion: v1
kind: Pod
metadata:
  name: nextflow
spec:
  serviceAccountName: nextflow
  volumes:
    - name: nf-pvc
      persistentVolumeClaim:
        claimName: nextflow-rw-many
  containers:
    - name: nextflow
      image: nextflow/nextflow:24.10.2
      command: ["sleep"]
      args: ["1000"]
      volumeMounts:
        - mountPath: "/workspace"
          name: nf-pvc
```


