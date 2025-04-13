# KEDA and RabbitMQ Setup Script

This script automates the installation of KEDA and RabbitMQ on a Kubernetes cluster. It also deploys a publisher job and a consumer application with Horizontal Pod Autoscaler (HPA) and ScaledObject configuration.

## Prerequisites

Before running this script, ensure that you have the following:

1. **Kubernetes Cluster**: A running Kubernetes cluster (e.g., Minikube, GKE, EKS, AKS).
2. **kubectl**: Installed and configured to access your Kubernetes cluster.
3. **Helm**: If Helm is not installed, the script will install it for you.
4. **Internet Access**: Required for downloading Helm and Helm charts.
5. **RabbitMQ Image**: The script uses a RabbitMQ client image from novneet3 dockerhub repo which is public.

## Script Overview

### Global Variables
- **`rabbitmq_connstring`**: Holds the connection string for RabbitMQ.
- **`queue_name`**: The name of the RabbitMQ queue to use. default.
- **`resource_namespace`**: The namespace for deploying the RabbitMQ consumer and related resources.

### Functions
- **`is_number`**: Checks if a given argument is a number.
- **`choose_context`**: Displays available Kubernetes contexts and allows the user to select one.
- **`install_prereq`**: Checks for and installs Helm.
- **`install_keda`**: Installs KEDA using Helm.
- **`deploy_app`**: Optionally installs RabbitMQ and deploys a publisher job and consumer application.
- **`health_check`**: Checks the health status of the specified deployment, including pod statuses and resource usage metrics.

### Main Menu
The script provides a menu for users to select which step to execute:
1. Choose Kubernetes context.
2. Install prerequisites (Helm and KEDA).
3. Install RabbitMQ (optional), deploy a publisher to the queue (optional), and deploy the consumer application with HPA and ScaledObject.
4. Perform a health check on the deployment.
5. Quit the script.

## Usage Instructions

1. **Make the script executable**:
   ```bash
   chmod +x script.sh
   ```

2. **Run the script**:
   ```bash
   ./script.sh
   ```

3. **Follow the prompts**:
   - **Choose Kubernetes Context**: Select the appropriate context for your Kubernetes cluster. The default is `minikube`.
   - **Install Prerequisites**: The script checks for Helm and installs KEDA using Helm. It will also prompt you for a namespace.
   - **Initialize Queue reference by Installing RabbitMQ (optional), deploy publisher to the queue (optional), deploy consumer/application with HPA and scaled object**: Choose whether to install RabbitMQ or provide an existing connection string. If installing, specify the namespace for RabbitMQ.
   - **Health Check**: You can check the health status of the RabbitMQ consumer deployment and view the resource usage metrics.

### Example Workflow

1. **Choose a Kubernetes context**:
   ```
   Enter context to deploy in (default: minikube): if left empty will pick minikube as current context
   ```

2. **Install prerequisites**:
   ```
   Checking if Helm is installed...
   Helm not found. Installing Helm...

   Enter the namespace for KEDA installation (default: keda): default namespace is keda and release name is keda, if already installed, Error: INSTALLATION FAILED: cannot re-use a name that is still in use
   ```

3. **Initialize Queue reference by Installing RabbitMQ (optional), deploy publisher to the queue (optional), deploy consumer/application with HPA and scaled object**:
   ```
   Run this step to initialize your rabbitmq connection string and queue name and when asked to install rabbitmq choose appropriate response.

   Would you like to install RabbitMQ (yes/no)? If not, be ready with RabbitMQ connection string when prompted: default is yes and installtion namespace default is "default". any other inputs other than yes/no will skip the installtion.
   
   If installed through this script a publisher job will be created to deploy 300 messages in queue "hello".

   Credentials:
    echo "Username      : user"
    echo "Password      : $(kubectl get secret --namespace <ns> rabbitmq -o jsonpath="{.data.rabbitmq-password}" | base64 -d)"
    echo "ErLang Cookie : $(kubectl get secret --namespace <ns> rabbitmq -o jsonpath="{.data.rabbitmq-erlang-cookie}" | base64 -d)"

   if not 

   Provide RabbitMQ connection string ('amqp://user:password@rabbitmq.<ns>.svc.cluster.local:5672'): enter remote rabbitmq url such as "amqp://user:password@<remote ip>:<port>"

   Enter the queue name you created with your RabbitMQ server (default: hello): enter the queue name you want to read message from 
   ```

4. **Perform a health check**:
   ```
   Enter deployment name (default: rabbitmq-consumer): 
   Enter Namespace (default: default) : 
   ```

### Notes
- Ensure that you have the necessary permissions to create resources in your Kubernetes cluster.
- Adjust resource requests and limits as needed based on your cluster’s capacity.
- If you encounter issues, check the logs of the relevant pods using:
  ```bash
  kubectl logs <pod-name> -n <namespace>
  ```

## Conclusion
This script simplifies the deployment of KEDA and RabbitMQ in a Kubernetes environment. Follow the usage instructions carefully and monitor your resources to ensure optimal performance.