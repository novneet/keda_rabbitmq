#!/usr/bin/bash

# Global Variables
rabbitmq_connstring=""  # Stores RabbitMQ connection string
queue_name=""           # Stores the queue name for RabbitMQ
resource_namespace=""   # Stores the namespace where resources will be deployed


# Function: Print available Kubernetes contexts and allow the user to select one
choose_context() {
  echo -e "Context present in this machine: \n"
  kubectl config get-contexts -oname  # List available Kubernetes contexts
  echo
  read -p "Enter context to deploy in (default: minikube): " kube_context
  kube_context=${kube_context:-minikube}  # Set default to 'minikube' if not provided
  if ! kubectl config get-contexts -o name | grep -q "^$kube_context$"; then
    echo "Invalid context selected. Exiting."
    exit 1
  fi
  kubectl config use-context "$kube_context"  # Switch to the selected context
}

# Function: Check if Helm is installed, and install it if not present
install_prereq() {
  echo -e "\nChecking if Helm is installed..."
  if ! command -v helm &> /dev/null; then  # Check if Helm command is available
    echo -e "Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh  # Make the Helm install script executable
    ./get_helm.sh  # Run the Helm install script
  else
    echo -e "Helm is already installed.\n"
  fi
# }

# Function: Install KEDA using Helm
# install_keda() {
  read -p "Enter the namespace for KEDA installation (default: keda): " keda_ns
  keda_ns=${keda_ns:-keda}  # Set default namespace for KEDA installation
  echo -e "\nInstalling KEDA in $keda_ns namespace\n"
  helm repo add kedacore https://kedacore.github.io/charts  # Add KEDA Helm chart repo
  helm repo update  # Update Helm repositories
  helm install keda kedacore/keda --namespace "$keda_ns" --create-namespace  # Install KEDA
}

# Function: Deploy RabbitMQ (optional) and a publisher job for testing
deploy_app() {
  read -p "Would you like to install RabbitMQ (yes/no)? If not, be ready with RabbitMQ connection string when prompted: " install_rabbitmq
  install_rabbitmq=${install_rabbitmq:-yes}

  if [[ "$install_rabbitmq" == "yes" ]]; then  # Install RabbitMQ if user opts for it
    read -p "Enter the RabbitMQ namespace (default: default): " rabbitmq_ns
    rabbitmq_ns=${rabbitmq_ns:-default}  # Default namespace for RabbitMQ

    echo "Installing RabbitMQ in namespace: $rabbitmq_ns..."
    helm repo add bitnami https://charts.bitnami.com/bitnami  # Add Bitnami Helm chart repo for RabbitMQ
    helm repo update  # Update Helm repositories
    helm install rabbitmq bitnami/rabbitmq --namespace "$rabbitmq_ns" --create-namespace --wait  # Install RabbitMQ and wait for it to be ready

    # Fetch RabbitMQ password and construct the connection string
    rabbitmq_password=$(kubectl get secret --namespace "$rabbitmq_ns" rabbitmq -o jsonpath="{.data.rabbitmq-password}" | base64 -d)
    rabbitmq_connstring="amqp://user:$rabbitmq_password@rabbitmq.$rabbitmq_ns.svc.cluster.local:5672"
    echo "Connection string: $rabbitmq_connstring"

    # Deploy a job that sends 300 messages to the "hello" queue in RabbitMQ
    echo -e "\n\nDeploying a publisher job for queue 'hello' with 300 messages.\n"
    echo -e "\nDeleting job rabbitmq-publish before creating one"
    kubectl delete job rabbitmq-publish  # Delete existing publisher job if it exists

    # Create a Kubernetes Job YAML for publishing messages to RabbitMQ
    cat > publisher-job.yaml <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: rabbitmq-publish
spec:
  template:
    spec:
      containers:
        - name: rabbitmq-client
          image: ghcr.io/kedacore/rabbitmq-client:v1.0
          imagePullPolicy: Always
          command:
            [
              "send",
              "$rabbitmq_connstring",
              "300"
            ]
      restartPolicy: Never
EOF
    queue_name="hello"  # Set queue name to "hello"
    kubectl apply -f publisher-job.yaml  # Apply the job to Kubernetes
  else
    # If RabbitMQ is not installed, ask the user for the connection string and queue name
    echo -e "Skipping RabbitMQ installation."
    read -p "Provide RabbitMQ connection string ('amqp://user:password@rabbitmq.<ns>.svc.cluster.local:5672'): " rabbitmq_connstring
    read -p "Enter the queue name you created with your RabbitMQ server: (default: hello)" queue_name
    queue_name=${queue_name:-hello}
    echo -e "Remote RabbitMQ queue name: $queue_name"
  fi
}

# Function: Deploy RabbitMQ consumer and create an HPA (Horizontal Pod Autoscaler)
deploy_consumer() {
  read -p "Enter namespace where ScaledObject and RabbitMQ consumer should be deployed (default: default): " resource_namespace
  resource_namespace=${resource_namespace:-default}  # Set default namespace for consumer deployment
  kubectl create ns "$resource_namespace" || true  # Create namespace if it doesn't exist

  echo -e "\nDeploying RabbitMQ consumer.\n"
  
  # Create a Kubernetes Deployment for the RabbitMQ consumer
  cat > rabbitmq-consumer.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-consumer
  namespace: $resource_namespace
  labels:
    app: rabbitmq-consumer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq-consumer
  template:
    metadata:
      labels:
        app: rabbitmq-consumer
    spec:
      containers:
        - name: rabbitmq-consumer
          image: novneet3/rabbitmq-client:v1.0
          imagePullPolicy: Always
          command:
            - receive
          args:
            - $rabbitmq_connstring
          resources:
            requests:
              cpu: "100m"
              memory: "100Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          ports:
            - containerPort: 5672
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-consumer-svc
  namespace: $resource_namespace
spec:
  selector:
    app: rabbitmq-consumer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5672
  type: ClusterIP
EOF

  kubectl apply -f rabbitmq-consumer.yaml  # Deploy the RabbitMQ consumer and service
  echo -e "\nDeployment Details\n"
  kubectl get ep rabbitmq-consumer-svc -n $resource_namespace  # Display the service endpoint
  kubectl get hpa keda-hpa-rabbitmq-consumer -n $resource_namespace  # Display the HPA details if available
}

# Function: Create a KEDA ScaledObject to auto-scale based on RabbitMQ queue length
create_scaledobject() {
  read -p "Enter maximum replica count (default: 5): " max_replica 
  read -p "Enter maximum queue length (default: 5): " queue_length
  max_replica=${max_replica:-5}  # Set default max replicas
  queue_length=${queue_length:-5}  # Set default queue length

  # Create a ScaledObject YAML for KEDA
  cat > scaledobject.yaml <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: rabbitmq-consumer
  namespace: $resource_namespace
spec:
  scaleTargetRef:
    name: rabbitmq-consumer
  pollingInterval: 5
  cooldownPeriod: 30
  maxReplicaCount: $max_replica
  triggers:
    - type: rabbitmq
      metadata:
        queueName: $queue_name
        queueLength: "$queue_length"
        host: $rabbitmq_connstring
EOF

  kubectl apply -f scaledobject.yaml  # Apply the ScaledObject to Kubernetes
  kubectl get ep  # Display the endpoint information
}

# Function: Perform a health check on the RabbitMQ consumer deployment
health_check() {
  read -p "Enter deployment name (default: rabbitmq-consumer): " deployment_name
  read -p "Enter Namespace (default: default): "
  deployment_name=${deployment_name:-"rabbitmq-consumer"}  # Set default deployment name
  namespace=${namespace:-default}  # Set default namespace

  # Check if the deployment exists
  if ! kubectl get deployment "$deployment_name" -n "$namespace" &> /dev/null; then
    echo -e "Deployment '$deployment_name' not found in namespace '$namespace'.\n"
    exit 1
  fi

  # Get deployment status
  deployment_status=$(kubectl get deployment "$deployment_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
  echo -e "Deployment Status: $deployment_status \n"

  # Get the status of the associated pods
  echo
  pods=$(kubectl get pods -l app="$deployment_name" -n "$namespace" -o jsonpath='{.items[*].status.containerStatuses[*].lastState}')
  echo -e "Pod Statuses: $pods \n"

  # Retrieve CPU and Memory usage metrics for the pods
  echo -e "\nRetrieving resource usage metrics... provided pod is labeled app=$deployment_name"
  kubectl top pods -n "$namespace" --selector=app="$deployment_name"

  # Check if any pods are in a state other than "Running"
  for pod in $(kubectl get pods -l app="$deployment_name" -n "$namespace" -o jsonpath='{.items[*].metadata.name}'); do
    pod_status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}')
    if [[ "$pod_status" != "Running" ]]; then
      echo "Issue: Pod '$pod' is in status '$pod_status'."
    fi
  done
}

# Main Menu for user input
echo -e "Starting KEDA and RabbitMQ setup on Kubernetes cluster...\n"

# Present the user with a menu of options to perform different actions
echo 'Please select the step to run: '
options=("Choose Kubernetes context" "Install prerequisites (Helm and KEDA using Helm)" "Initialize Queue reference by Installing RabbitMQ (optional), deploy publisher to the queue (optional), deploy consumer/application with HPA and scaled object" "Healthcheck" "Quit")
select opt in "${options[@]}"
do
  case $opt in
    "Choose Kubernetes context")
      choose_context  # Call function to select Kubernetes context
      ;;
    "Install prerequisites (Helm and KEDA using Helm)")
      install_prereq  # Call function to install Helm and KEDA
      ;;
    "Initialize Queue reference by Installing RabbitMQ (optional), deploy publisher to the queue (optional), deploy consumer/application with HPA and scaled object")
      deploy_app  # Call function to deploy RabbitMQ, publisher, consumer, and ScaledObject
      ;;
    "Healthcheck")
      health_check  # Call function to perform a health check on the deployment
      ;;
    "Quit")
      break  # Exit the script
      ;;
    *) echo "Invalid option $REPLY";;  # Handle invalid menu options
  esac
done
