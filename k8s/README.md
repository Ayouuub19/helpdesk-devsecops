# Kubernetes Deployment — HelpDesk

## Prerequisites
- Minikube installed and running
- kubectl configured

## Setup

```bash
# Start Minikube
minikube start --driver=docker --memory=4096 --cpus=2

# Build image inside Minikube (so it doesn't need a registry)
eval $(minikube docker-env)   # On Linux/Mac
# On Windows PowerShell:
& minikube -p minikube docker-env --shell powershell | Invoke-Expression

# Build the Docker image
docker build -t helpdesk-backend:latest ./backend

# Deploy
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/networkpolicy.yaml

# Check deployment
kubectl get pods -n helpdesk
kubectl get services -n helpdesk
kubectl get networkpolicies -n helpdesk

# Access the application
minikube service helpdesk-backend-nodeport -n helpdesk --url

# Verify security (must NOT show 'root')
kubectl exec -n helpdesk -it $(kubectl get pod -n helpdesk -l app=helpdesk-backend -o jsonpath='{.items[0].metadata.name}') -- whoami

# Check logs
kubectl logs -n helpdesk -l app=helpdesk-backend -f
```

## Security Checks
- securityContext: runAsNonRoot=true ✅
- capabilities: drop ALL ✅  
- allowPrivilegeEscalation: false ✅
- NetworkPolicy: default-deny-all ✅
- Secrets: injected from Kubernetes Secrets (not hardcoded) ✅
