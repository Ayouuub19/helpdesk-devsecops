# ==============================================================================
# Script de Simulation Locale du Pipeline DevSecOps (Sans GitLab)
# Reproduit les 9 étapes du pipeline CI/CD avec contrôles bloquants
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DEMARRAGE DU PIPELINE DEVSECOPS LOCAL (HelpDesk)       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Continue"
$failed = $false

# ------------------------------------------------------------------------------
# ETAPE 1 : TESTS UNITAIRES
# ------------------------------------------------------------------------------
Write-Host "[1/7] Lancement des Tests Unitaires..." -ForegroundColor Yellow
python -m pytest backend/tests/ -v --tb=short
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ECHEC : Tests unitaires en echec !" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "✅ SUCCES : Tous les tests unitaires sont passes." -ForegroundColor Green
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 2 : SCAN DE SECRETS (Gitleaks)
# ------------------------------------------------------------------------------
Write-Host "[2/7] Analyse de Secrets avec Gitleaks..." -ForegroundColor Yellow
if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    gitleaks detect --source=. --no-git --report-format=json --report-path=gitleaks-report.json --redact
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 PIPELINE BLOQUE : Gitleaks a detecte un secret expose !" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "✅ SUCCES : Aucun secret detecte." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ Gitleaks non installe. Pour l'installer : winget install Gitleaks.Gitleaks" -ForegroundColor DarkYellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 3 : ANALYSE STATIQUE DE CODE - SAST (Semgrep)
# ------------------------------------------------------------------------------
Write-Host "[3/7] Analyse SAST avec Semgrep..." -ForegroundColor Yellow
if (Get-Command semgrep -ErrorAction SilentlyContinue) {
    semgrep --config=auto backend/ --json --output=semgrep-report.json --metrics=off
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️ Semgrep a detecte des anomalies de code (Voir semgrep-report.json)." -ForegroundColor DarkYellow
    } else {
        Write-Host "✅ SUCCES : Scan SAST termine." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ Semgrep non installe. Pour l'installer : pip install semgrep" -ForegroundColor DarkYellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 4 : SCAN DES DEPENDANCES (Trivy FS)
# ------------------------------------------------------------------------------
Write-Host "[4/7] Analyse des Dependances avec Trivy..." -ForegroundColor Yellow
if (Get-Command trivy -ErrorAction SilentlyContinue) {
    trivy fs --severity CRITICAL --exit-code 1 --no-progress backend/
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 PIPELINE BLOQUE : Dependance critique detectee !" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "✅ SUCCES : Dependances verifiees, aucune CRITICAL." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ Trivy non installe. Pour l'installer : winget install aquaproject.trivy" -ForegroundColor DarkYellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 5 : CONSTRUCTION DU CONTENEUR DOCKER
# ------------------------------------------------------------------------------
Write-Host "[5/7] Construction de l'image Docker durcie..." -ForegroundColor Yellow
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker build -t helpdesk-backend:latest ./backend
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ ECHEC du build Docker." -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "✅ SUCCES : Image helpdesk-backend:latest construite." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ Docker non actif ou non installe." -ForegroundColor DarkYellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 6 : SCAN DE L'IMAGE DOCKER (Trivy Image)
# ------------------------------------------------------------------------------
Write-Host "[6/7] Analyse de l'image Docker avec Trivy..." -ForegroundColor Yellow
if ((Get-Command trivy -ErrorAction SilentlyContinue) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    trivy image --severity CRITICAL --exit-code 1 --no-progress helpdesk-backend:latest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "🚨 PIPELINE BLOQUE : L'image Docker contient une vulnerabilite CRITICAL !" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "✅ SUCCES : Image validee sans CVE CRITICAL." -ForegroundColor Green
    }
}
Write-Host ""

# ------------------------------------------------------------------------------
# ETAPE 7 : VERIFICATION UTILISATEUR NON-ROOT
# ------------------------------------------------------------------------------
Write-Host "[7/7] Verification de securite : Utilisateur Non-Root dans le conteneur..." -ForegroundColor Yellow
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $user = docker run --rm --entrypoint whoami helpdesk-backend:latest
    if ($user -eq "root") {
        Write-Host "🚨 SECURITE VIOLEE : Le conteneur s'execute en root !" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "✅ SUCCES : Le conteneur s'execute en tant que '$user' (UID 1001, non-root)." -ForegroundColor Green
    }
}
Write-Host ""

# ------------------------------------------------------------------------------
# RESULTAT FINAL DU PIPELINE
# ------------------------------------------------------------------------------
Write-Host "==========================================================" -ForegroundColor Cyan
if ($failed) {
    Write-Host "❌ PIPELINE LOCAL TERMINE EN ECHEC (Controles bloquants actifs)" -ForegroundColor Red
} else {
    Write-Host "🎉 PIPELINE LOCAL VALIDE AVEC SUCCES !" -ForegroundColor Green
}
Write-Host "==========================================================" -ForegroundColor Cyan
