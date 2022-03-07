# MQ Gitops

# Architecture

![Custom Image Pipeline](/readme-images/custom-image.png)

![Dynamic MQSC Pipeline](/readme-images/dynamic-mqsc-pipeline.png)

![ArgoCD deployment](/readme-images/argocd-app.png)

![different-envs](/readme-images/different-envs.png)

## Git Repository Setup

We have three repositories for MQ pipeline:

1. [Base MQ image repository](https://github.com/IBMMQAutomation/base-image) to build MQ custom base image for every MQ release/fix pack
   - Access: Admins only
2. [Dynamic MQSC repository](https://github.com/IBMMQAutomation/dynamic-mqsc) for MQSC Changes.
   - Access:
     - Developers (create PR)
     - Admins (approve PR)
3. [Curent GitOps repository](https://github.com/IBMMQAutomation/mq-pipeline.git) for ArgoCD
   - Access: Admins only

## CI/CD Setup

1. [Build MQ base image using Tekton](#MQ-Base-Image)
   - Build, Scan and Push base image to nexus repository
2. [Tekton to push MQSC changes from Dynamic MQSC repo to ArgoCD repo](#Dynamic-MQSC-Tekton-Task)
3. [ArgoCD setup to watch GitOps repository](#GitOps-with-ArgoCD)

## **Prerequisites**

Already have an Openshift cluster with the following operators:

- MQ
- Openshift Pipelines
- Openshift Gitops
- Secrets: `ibm-entitlement-key` and `git-credentials`

  - To create `ibm-entitlement-key`

    ```
    oc create secret docker-registry ibm-entitlement-key \
    --docker-username=cp \
    --docker-password= <entitlement-key> \
    --docker-server=cp.icr.io \
    --namespace=<namespace>
    ```

  - To create `git-credentials`

    ```
    oc create secret generic git-credentials \
    --from-literal=username=<username> \
    --from-literal=password=<personal-access-token> \
    --type=kubernetes.io/basic-auth \
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
  - Note: You can easily add scan task to scan base image before pushing the base image to your nexus/other registry
    ```
    cd base-iamge
    oc apply -f tekton/pipeline
    oc apply -f tekton/tasks
    ```

* Either add webhook to trigger the pipeline or manually start your pipeline

## Dynamic MQSC Tekton Task

#### **Purpose of Dynamic MQSC repository is for your development team to create PR for changes to MQSC. Once the PR is approved, tekton pipeline is triggered to copy the changes to GitOps repostiory**

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

#### Go to your ArgoCD instance. On top left, click `New App` and fill out necessary information such as:

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
