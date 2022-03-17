## Overview

<img src="/readme-images/custom-image.png" width="45%" height="10%">
<img src="/readme-images/dynamic-mqsc-pipeline.png" width="45%" height="10%">
<img src="/readme-images/argocd-app.png" width="45%" height="10%">
<img src="/readme-images/different-envs.png" width="45%" height="10%">

**Description**: This Gitops repo has a specific folder structure. It has 5 different folder for 5 environments such as DEV, SIT, UAT, PTE, PRD. Each environment has different QM folders and each QM folder has OCP/MQ configuration files. Lets take UAT folder as an example, it has QM01 (queue manager name) and it contains the following:

- certs: contains MQ certificates
- dynamic.mqsc: All the dynamic.mqsc changes come from [Dynamic MQSC](https://github.com/IBMMQAutomation/dynamic-mqsc) that your developer has pushed so do not make changes directly to your dynamic.mqsc files in this repo. Tekton pipeline takes mqsc files from "Dynamic MQSC" repo injects environment variables and pushes all the mqsc files for each QM into GitOps repo
- kustomization.yaml: Used for deploying `resources` on OpenShift. It generates configMaps for dynamic.mqsc, static-qm.mqsc and qm.ini as well as a secret for mq certificates. It also contains patches for QM
- qm.ini: One time deployment of INI file. It also has `namePrefix` and the prefix is used for all the resources
- qm.yaml: YAML for creating a QM on Opensift which points to MQSC confimaps, secret and QM name. ALl these will have `namePrefix` from kustomization.yaml
- static-qm.mqsc: One time MQSC deployment that can't be edited later

**`base` folder**

- generic/kustomization.yaml: It contains resources to deploy such as generic QM and components which will be used across all the QMs in all the enviornments. It has a script that keeps checking for changes in dynamic MQSC configmaps and applies those changes if there is a change.
- generic/qm.yaml: Contains generic values for QM. Rest of the environments and QueueManagers will patch to this generic base QM
- generic-route/kustomize.yaml: It contains resources to deploy SNI route for external connection
- generic-route/route.yaml: This is a template for route and will be used for patches in other environments

**IMPORTANT**:

- If you are using OpenShift secret to store LDAP password then make sure you have the following section in either `base/generic/qm.yaml` if the password is same across all the queue managers and all the enviornments. If LDAP password is different for each queue manager then add the following section for each environemnt in each queue manager patching. For example, open `dev/qm01/qm.yaml` to see how to add secret reference for each QueueManager per enviornment.
- If LDAP passwords expires every year and you have to update the secret then the recommendation is to create a new secret with a new name and change the name of the secret in `base/generic/qm.yaml` or change patching for the QMs per ENV such as `dev/qm01/qm.yaml`

```
pod:
  containers:
        - name: qmgr
          envFrom:
            - secretRef:
                name: <secert-name>

```

```
uat
├── qm01
│   ├── certs
│   │   ├── tls.crt
│   │   └── tls.key
│   ├── dynamic.mqsc
│   ├── kustomization.yaml
│   ├── qm.ini
│   ├── qm.yaml
│   ├── route.yaml
│   └── static-qm.mqsc
└── qm02
    ├── certs
    │   ├── tls.crt
    │   └── tls.key
    ├── dynamic.mqsc
    ├── kustomization.yaml
    ├── qm.ini
    ├── qm.yaml
    ├── route.yaml
    └── static-qm.mqsc


base
├── generic
│   ├── kustomization.yaml
│   └── qm.yaml
└── generic-route
    ├── kustomization.yaml
    └── route.yaml
```

## Git Repositories

We have three repositories for whole end to end pipeline:

1. Base MQ image [repository](https://github.com/IBMMQAutomation/base-image) to build MQ custom base image for every MQ release/fix pack
   - Access: Admins only
2. Dynamic MQSC [repository](https://github.com/IBMMQAutomation/dynamic-mqsc) for MQSC Changes.
   - Access:
     - Developers (create PR)
     - Admins (approve PR)
3. Curent GitOps [repository](https://github.com/IBMMQAutomation/mq-pipeline.git) for ArgoCD
   - Access: Admins only (approve PR)

# Steps

0. [Prerequisites](#prerequisites)
1. [Build MQ base image](#MQ-Base-Image)
   - Create Tekton pipeline to build, scan and push custom base image to your nexus/ocp/private registry (In this demo, we will build and push an image to openshift registry however you can add scan and push to your private registry to your tekton tasks and pipeline)
2. [Dynamic MQSC](#Dynamic-MQSC-Tekton-Task)
   - Create Tekton pipeline to push MQSC changes from Dynamic MQSC repo to ArgoCD repo
3. [Gitops setup](#GitOps-with-ArgoCD)
   - Create ArgoCD app to watch for git changes and apply yamls to your cluster

## **Prerequisites**

Already have an Openshift cluster with the following operators:

- MQ
- Openshift Pipelines
- Openshift Gitops
- Secrets: `ibm-entitlement-key`

  - To create `ibm-entitlement-key`

    ```
    oc create secret docker-registry ibm-entitlement-key \
    --docker-username=cp \
    --docker-password= <entitlement-key> \
    --docker-server=cp.icr.io \
    --namespace=<namespace>
    ```

## MQ Base Image

#### **Purpose of MQ Base Image repository is for your admin team to build custom image with security exit files every new MQ release or fix pack**

- Make sure prerequisites are met

  - Now lets link our `ibm-entitlement-key` to `pipeline` and `default` service accounts so it can pull MQ base image from ibm private registry

  ```
  oc project <namespace>
  oc secret link pipeline ibm-entitlement-key --for=pull
  oc secret link pipeline ibm-entitlement-key
  oc secret link default ibm-entitlement-key --for=pull
  oc secret link default ibm-entitlement-key
  ```

* Git clone and copy it to your Github/Bitbucket. Then make necessary changes to all the parameters in `pipeline.yaml`.
  ```
  git clone https://github.com/IBMMQAutomation/base-image.git
  cd base-iamge
  ```

- Apply Tekton pipeline and tasks to build and push custom image
  - Note: In this demo, we will build and push an image to openshift registry however you can add scan and push to your private registry to your tekton tasks and pipeline
    ```
    cd base-iamge
    oc apply -f tekton/pipeline
    oc apply -f tekton/tasks
    ```

* Either add webhook to trigger the pipeline or manually start your pipeline

## Dynamic MQSC Tekton Task

#### **Purpose of Dynamic MQSC repository is for your development team to create PR for changes to MQSC. Once the PR is approved, tekton pipeline is triggered to copy the changes to GitOps repostiory**

- Make sure prerequisites are met

- Git clone and copy it to your Github/BitBucket
  ```
  git clone https://github.com/IBMMQAutomation/dynamic-mqsc.git
  ```
- Make necessary changes to all the parameters in `pipeline.yaml`. Then apply tekton pipeline and tekton task on your OpenShift cluster

  ```
  cd dynamic-mqsc
  oc apply -f pipeline.yaml
  oc apply -f git-task.yaml
  ```

* Either add webhook to trigger the pipeline or manually start your pipeline

## GitOps with ArgoCD

#### **Purpose of GitOps repository is for your admin team to appove PR for changes to MQSC. Once the PR is approved, ArgoCD will apply chagnes to your OpenShift cluster**

- Git clone and copy it to your Github/Bitbucket

  - Make necessary changes to mqsc files

- Create ArgoCD Application
  - Note: Before creating ArgoCD, please contact cluster admin to give ArgoCD permission to create resources in your namespace using Cluster Role and Cluster Role Binding as well as private git repository

#### Go to your ArgoCD instance. On top left, click `New App` and fill out necessary values such as:

- To deploy `QM01` for `DEV` environment
  - Application Name: `dev-qm01` (ArgoCD app name)
  - Project: default (ArgoCD project name)
  - Sync Policy: `Automatic` for dev but `Manual` for production
  - Select `Skip Schema Validation` (this is needed for kind:QueueManager)
  - Repository URL: `<your-git-url>` example: https://github.com/IBMMQAutomation/mq-pipeline.git
  - Revision: `<your-branch>` example: HEAD for master
  - Path: `dev/qm01` (subfolder you want to deploy)
  - Cluster URL: `https://kubernetes.default.svc`
    - Note: kubernetes.default.svc is to deploy yamls to the current cluster where ArgoCD is installed. You can also setup ArgoCD to deploy yamls to a different openshift cluster
  - Namespace: `dev` (namespace for your development environment)
  - Click `Create` on top left
- Repeat above steps for other Queue Managers and for other environments. For example, path:
  - `dev/qm02`
  - `uat/qm01`
  - more...
