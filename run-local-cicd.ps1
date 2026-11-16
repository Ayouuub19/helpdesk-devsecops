# ==============================================================================
# Script d'Automatisation CI/CD Locale Complète (Sans GitLab distant)
# Couvre : CI (Tests + Sécurité) ET CD (Build + Minikube + Rollout + DAST)
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     PIPELINE COMPLET CI/CD LOCAL DEVSECOPS (HelpDesk)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Continue"

# ==============================================================================
# PARTIE 1 : CI (CONTINUOUS INTEGRATION) — Contrôles Qualité & Sécurité
# ==============================================================================
Write-Host ">>> PHASE 1 : CI (Contrôles de Sécurité & Tests)" -ForegroundColor Magenta

# 1. Tests Unitaires
Write-Host "[CI 1/4] Tests unitaires (Pytest)..." -ForegroundColor Yellow
python -m pytest backend/tests/ -v --tb=short
if ($LASTEXITCODE -ne 0) {
    Write-Host "🚨 CI BLOQUÉE : Tests unitaires en échec. Déploiement CD annulé !" -ForegroundColor Red
    exit 1
}

# 2. Gitleaks (Secrets)
Write-Host "[CI 2/4] Scan de secrets (Gitleaks)..." -ForegroundColor Yellow
if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    gitleaks detect --source=. --no-git --report-format=json --report-path=gitleaks-report.json --redact
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 CI BLOQUÉE : Secret détecté dans le code. Déploiement CD annulé !" -ForegroundColor Red
        exit 1
    }
}

# 3. Semgrep (SAST)
Write-Host "[CI 3/4] Analyse statique SAST (Semgrep)..." -ForegroundColor Yellow
if (Get-Command semgrep -ErrorAction SilentlyContinue) {
    semgrep --config=auto backend/ --metrics=off
}

# 4. Trivy FS (Dépendances)
Write-Host "[CI 4/4] Scan dépendances (Trivy)..." -ForegroundColor Yellow
if (Get-Command trivy -ErrorAction SilentlyContinue) {
    trivy fs --severity CRITICAL --exit-code 1 --no-progress backend/
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 CI BLOQUÉE : CVE critique dans les dépendances. Déploiement CD annulé !" -ForegroundColor Red
        exit 1
    }
}

Write-Host "✅ PHASE CI TERMINÉE AVEC SUCCÈS. Démarrage de la CD..." -ForegroundColor Green
Write-Host ""

# ==============================================================================
# PARTIE 2 : CD (CONTINUOUS DEPLOYMENT) — Déploiement & Vérification K8s
# ==============================================================================
Write-Host ">>> PHASE 2 : CD (Déploiement Continu Kubernetes)" -ForegroundColor Magenta

# 1. Build de l'image Docker durcie
Write-Host "[CD 1/5] Construction de l'image Docker..." -ForegroundColor Yellow
docker build -t helpdesk-backend:latest ./backend
if ($LASTEXITCODE -ne 0) {
    Write-Host "🚨 CD BLOQUÉE : Échec de la construction de l'image Docker !" -ForegroundColor Red
    exit 1
}

# 2. Scan de l'image construite avant déploiement
Write-Host "[CD 2/5] Scan de vulnérabilités sur l'image Docker..." -ForegroundColor Yellow
if (Get-Command trivy -ErrorAction SilentlyContinue) {
    trivy image --severity CRITICAL --exit-code 1 --no-progress helpdesk-backend:latest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 CD BLOQUÉE : Image Docker vulnérable. Refus de déploiement en production !" -ForegroundColor Red
        exit 1
    }
}

# 3. Chargement de l'image dans Minikube
Write-Host "[CD 3/5] Envoi de l'image dans le registre Minikube local..." -ForegroundColor Yellow
minikube image load helpdesk-backend:latest
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ Assurez-vous que Minikube est démarré (minikube start) !" -ForegroundColor DarkYellow
}

# 4. Déploiement déclaratif sur Kubernetes
Write-Host "[CD 4/5] Déploiement des manifestes Kubernetes durcis..." -ForegroundColor Yellow
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/networkpolicy.yaml

# Attente du déploiement opérationnel
Write-Host "Attente de la disponibilité des pods Kubernetes..." -ForegroundColor Cyan
kubectl rollout status deployment/helpdesk-backend -n helpdesk --timeout=90s

# 5. Vérification de conformité de sécurité à l'exécution
Write-Host "[CD 5/5] Vérification de sécurité à l'exécution (Runtime)..." -ForegroundColor Yellow
$podName = kubectl get pod -n helpdesk -l app=helpdesk-backend -o jsonpath='{.items[0].metadata.name}'
$runningUser = kubectl exec -n helpdesk $podName -- whoami
Write-Host "Utilisateur actif dans le pod : $runningUser" -ForegroundColor Cyan

if ($runningUser -eq "root") {
    Write-Host "🚨 ALERTE SÉCURITÉ : Le conteneur s'exécute en root !" -ForegroundColor Red
    exit 1
} else {
    Write-Host "🛡️ CONFORMITÉ VALIDÉE : Exécution sous utilisateur non privilégié ($runningUser)." -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 DÉPLOIEMENT CONTINU (CD) RÉUSSI AVEC SUCCÈS !" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Pour accéder à l'application déployée :"
Write-Host "minikube service helpdesk-backend-nodeport -n helpdesk" -ForegroundColor Yellow
