# The GitOps configuration

All desired configurations are stored in the `manifests` directory. The structure of this directory follows the [kustomize directory layout](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/helloWorld/README.md):

* **base** contains the base deployment template of the network device agent responsible for configuration updates.
* **overlays** contains deviations, paths and device-specific configs for different environments. This is the directory that will be reconciled by the GitOps engine.

```bash
manifests
├── base
│   ├── deployment.yaml
│   └── kustomization.yaml
└── overlays
    └── dc1
        ├── kustomization.yaml
        ├── leaf1
        │   ├── interfaces.cfg
        │   ├── kustomization.yaml
        │   ├── nodeselectors.yaml
        │   └── volumes.yaml
        ├── leaf2
        │   ├── interfaces.cfg
        │   ├── kustomization.yaml
        │   ├── nodeselectors.yaml
        │   └── volumes.yaml
        ├── namespace.yaml
        └── spine
            ├── config_db.json
            ├── kustomization.yaml
            ├── nodeselectors.yaml
            └── volumes.yaml
```

The final network state is built out of a hierarchy of files that are reconciled by the [Kustomize Controller](https://fluxcd.io/docs/components/kustomize/). This is how the `manifests/overlays/dc1/kustomization.yaml` file (the root of that hierarchy) looks like:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  k8s-app: dc-network
namespace: dc1
resources:
- leaf1/
- leaf2/
- spine/
- namespace.yaml
```

This file simply references additional subdirectories that need to be accumulated before all manifests are applied. Each subdirectory represents a single device and contains another `kustomization.yaml` file that does the following:


* Patches the **base** resource with node-specific selectors to ensure that the agent runs only on the device we need.
* Generates a ConfigMap resource with the content of specified files, e.g. `interfaces.cfg` for leaf1.
* Paths the **base** resource with node-specific volumes, for example, we're mounting the `/etc/network` directory from the host in order to make changes in `interfaces.cfg` persistent.

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
nameSuffix: "-leaf1"
resources:
- ../../../base

patchesStrategicMerge:
- nodeselectors.yaml
- volumes.yaml

generatorOptions:
 disableNameSuffixHash: true

configMapGenerator:
- name: interfaces
  files:
  - interfaces.cfg
- name: frr
  files:
  - frr.conf
  - daemons
```

Once all manifests are assembled, Kustomization controller applies them on a local Kubernetes cluster. 