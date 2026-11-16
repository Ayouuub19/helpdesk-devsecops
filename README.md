# 🎫 HelpDesk — Projet DevSecOps ING-5-SSIR

Application de gestion de tickets sécurisée, développée dans le cadre du cours DevSecOps.

## 🏗️ Architecture

- **Backend**: Python Flask + SQLAlchemy
- **Base de données**: SQLite (dev) / PostgreSQL (prod)
- **Conteneurisation**: Docker multi-stage
- **Orchestration**: Kubernetes (Minikube)
- **CI/CD**: GitLab CI
- **Sécurité**: Semgrep, Gitleaks, Trivy, OWASP ZAP
- **Observabilité**: Prometheus + Grafana + Loki

## 🚀 Démarrage rapide

```bash
# 1. Cloner le dépôt
git clone <repo-url>
cd helpdesk

# 2. Configurer les variables d'environnement
cp .env.example .env
# Éditer .env avec vos valeurs (fictives pour le dev)

# 3. Lancer l'application
docker-compose up --build

# 4. Accéder à l'application
# http://localhost:5000
# Login: admin / Admin123!
```

## 🔐 Comptes de test (fictifs)

| Utilisateur | Mot de passe | Rôle |
|-------------|-------------|------|
| admin | Admin123! | Administrateur |
| alice | Alice123! | Utilisateur |
| bob | Bob123! | Utilisateur |

## 🛡️ Pipeline de sécurité

```
Build → Tests → SAST (Semgrep) → Secrets (Gitleaks) →
Dépendances (Trivy) → Build Image → Scan Image →
Déploiement K8s → DAST (OWASP ZAP)
```

## ⚠️ Vulnérabilités initiales (intentionnelles)

Voir le rapport de sécurité pour les détails des 4 vulnérabilités introduites
intentionnellement et leurs corrections.

## 📂 Structure du projet

```
.
├── backend/           # Application Flask
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── templates/
│   └── tests/
├── k8s/               # Manifestes Kubernetes
├── monitoring/        # Config Prometheus/Loki
├── db/                # Scripts SQL
├── .gitlab-ci.yml     # Pipeline CI/CD
└── docker-compose.yml
```

## ☸️ Déploiement Kubernetes

Voir [k8s/README.md](k8s/README.md) pour les instructions détaillées.

## 📊 Monitoring

```bash
# Lancer le stack de monitoring
docker-compose -f docker-compose.monitoring.yml up -d

# Grafana: http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9090
# Loki: http://localhost:3100
```
