#!/bin/bash
# ==============================================================================
# Script CI/CD Local pour Ubuntu Linux (DevSecOps HelpDesk)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==========================================================${NC}"
echo -e "${CYAN}    PIPELINE DEVSECOPS COMPLET SUR UBUNTU (HelpDesk)      ${NC}"
echo -e "${CYAN}==========================================================${NC}"
echo ""

# 1. Tests unitaires
echo -e "${YELLOW}[1/7] Lancement des tests unitaires...${NC}"
python3 -m pytest backend/tests/ -v --tb=short
echo -e "${GREEN}✅ Tests unitaires validés.${NC}\n"

# 2. Détection de secrets
echo -e "${YELLOW}[2/7] Analyse des secrets avec Gitleaks...${NC}"
if command -v gitleaks &> /dev/null; then
    gitleaks detect --source=. --no-git --report-format=json --report-path=gitleaks-report.json --redact
    echo -e "${GREEN}✅ Aucun secret exposé.${NC}\n"
else
    echo -e "${YELLOW}⚠️ Gitleaks non installé, étape ignorée.${NC}\n"
fi

# 3. SAST avec Semgrep
echo -e "${YELLOW}[3/7] Analyse statique SAST avec Semgrep...${NC}"
if command -v semgrep &> /dev/null; then
    semgrep --config=auto backend/ --metrics=off
    echo -e "${GREEN}✅ Scan SAST terminé.${NC}\n"
fi

# 4. Scan dépendances Trivy
echo -e "${YELLOW}[4/7] Scan des dépendances avec Trivy...${NC}"
if command -v trivy &> /dev/null; then
    trivy fs --severity CRITICAL --exit-code 1 --no-progress backend/
    echo -e "${GREEN}✅ Aucune CVE critique dans les dépendances.${NC}\n"
fi

# 5. Build Docker
echo -e "${YELLOW}[5/7] Construction de l'image Docker durcie...${NC}"
docker build -t helpdesk-backend:latest ./backend
echo -e "${GREEN}✅ Image Docker construite.${NC}\n"

# 6. Scan Image Trivy
echo -e "${YELLOW}[6/7] Scan de sécurité de l'image Docker...${NC}"
if command -v trivy &> /dev/null; then
    trivy image --severity CRITICAL --exit-code 1 --no-progress helpdesk-backend:latest
    echo -e "${GREEN}✅ Image Docker validée sans vulnérabilité critique.${NC}\n"
fi

# 7. Déploiement Kubernetes Minikube
echo -e "${YELLOW}[7/7] Déploiement sur Minikube...${NC}"
if command -v minikube &> /dev/null && command -v kubectl &> /dev/null; then
    minikube image load helpdesk-backend:latest
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/secret.yaml
    kubectl apply -f k8s/backend-deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl apply -f k8s/networkpolicy.yaml
    
    echo "Attente de la disponibilité des pods..."
    kubectl rollout status deployment/helpdesk-backend -n helpdesk --timeout=90s
    
    POD=$(kubectl get pod -n helpdesk -l app=helpdesk-backend -o jsonpath='{.items[0].metadata.name}')
    RUN_USER=$(kubectl exec -n helpdesk $POD -- whoami)
    echo -e "${CYAN}Utilisateur dans le conteneur K8s : $RUN_USER${NC}"
    if [ "$RUN_USER" == "root" ]; then
        echo -e "${RED}🚨 ALERTE : Conteneur en root !${NC}"
        exit 1
    else
        echo -e "${GREEN}🛡️ SÉCURITÉ CONFORME : Exécution en non-root ($RUN_USER).${NC}"
    fi
fi

echo -e "\n${CYAN}==========================================================${NC}"
echo -e "${GREEN}🎉 TOUT LE PIPELINE DEVSECOPS S'EST DÉROULÉ AVEC SUCCÈS !${NC}"
echo -e "${CYAN}==========================================================${NC}"
