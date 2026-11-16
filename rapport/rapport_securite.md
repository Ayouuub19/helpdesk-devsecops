# Rapport de Sécurité — HelpDesk DevSecOps
**Projet ING-5-SSIR | TEK-UP University**  
**Encadrant : Malek Ferchichi**  
**Année Universitaire : 2025 - 2026**

---

## Sommaire
1. [Architecture du système](#1-architecture-du-système)
2. [Modèle de menace STRIDE](#2-modèle-de-menace-stride)
3. [Vulnérabilités initiales et remédiations](#3-vulnérabilités-initiales-avant-correction)
4. [Pipeline CI/CD — Contrôles et politique de blocage](#4-pipeline-cicd--contrôles-et-politique-de-blocage)
5. [Kubernetes — Durcissement et sécurité de la plateforme](#5-kubernetes--durcissement)
6. [Tests DAST — OWASP ZAP](#6-tests-dast--owasp-zap)
7. [Observabilité et réponse à incident](#7-observabilité-et-réponse-à-incident)
8. [Limites et perspectives d'amélioration](#8-limites-et-perspectives)

---

## 1. Architecture du système

Le projet **HelpDesk** est une plateforme applicative de gestion de tickets d'assistance technique, conçue selon une approche **DevSecOps** native ("Shift-Left Security"). La sécurité est intégrée à chaque étape du cycle de vie logiciel, depuis l'écriture du code source jusqu'au déploiement et à l'exploitation en production.

### 1.1 Description des composants

- **Code Source & Gestion de versions** : Dépôt GitLab hébergeant l'application Flask, les spécifications d'infrastructure as Code (IaC) Kubernetes, les fichiers de configuration de sécurité et les scripts de déploiement.
- **Pipeline CI/CD GitLab** : Orchestrateur automatisé exécutant 9 étapes séquentielles intégrant des outils de contrôle statique (SAST), de détection de secrets, d'analyse de dépendances (SCA), d'analyse d'images conteneurs et de tests dynamiques (DAST).
- **Registre de conteneurs (Docker Registry / GitLab Registry)** : Stockage sécurisé des artefacts de conteneurs immuables étiquetés avec le commit SHA et `latest`.
- **Plateforme d'exécution (Kubernetes / Minikube)** : Cluster d'orchestration exécutant les pods applicatifs dans un namespace dédié et durci (`helpdesk`).
- **Application HelpDesk** : Service web Flask (Python 3.11) adossé à un serveur WSGI Gunicorn et une base de données SQLite (migrable vers PostgreSQL), intégrant une gestion de sessions basée sur des rôles (`admin`, `user`).
- **Stack d'observabilité** : Collecte des métriques via Prometheus, centralisation des journaux d'événements via Grafana Loki, et tableaux de bord de visualisation Grafana pour la détection proactive d'incidents.

### 1.2 Diagramme textuel d'architecture

```
+---------------+
|   Développeur |
+-------+-------+
        | (git push)
        v
+------------------------------------------------------------------------+
|                      GitLab CI/CD Pipeline                             |
|                                                                        |
|  [1. Build]  -->  [2. Unit Tests]  -->  [3. SAST (Semgrep)]            |
|       |                                         |                      |
|       v                                         v                      |
|  [4. Secret Scan] -> [5. Dep Scan]  -->  [6. Docker Build]             |
|    (Gitleaks)          (Trivy SCA)              |                      |
|                                                 v                      |
|  [8. Deploy K8s] <-- [7. Image Scan] <----------+                      |
|   (Minikube)           (Trivy Container)                               |
|       |                                                                |
|       v                                                                |
|  [9. DAST Scan] (OWASP ZAP)                                            |
+-------+----------------------------------------------------------------+
        |
        v Déploiement sécurisé
+------------------------------------------------------------------------+
|                 Cluster Kubernetes (Namespace: helpdesk)               |
|                                                                        |
|   +----------------------------------------------------------------+   |
|   |                       NetworkPolicy                            |   |
|   |  - Default Deny All                                            |   |
|   |  - Ingress: Port 5000 restreint                                |   |
|   |  - Egress: DNS (53 UDP/TCP) + HTTPS externe (443)              |   |
|   +----------------------------------------------------------------+   |
|                               |                                        |
|                               v                                        |
|   +----------------------------------------------------------------+   |
|   |                       Pod HelpDesk                             |   |
|   |  securityContext:                                              |   |
|   |    - runAsNonRoot: true (UID 1001)                             |   |
|   |    - allowPrivilegeEscalation: false                           |   |
|   |    - drop capabilities: ["ALL"]                                |   |
|   |    - readOnlyRootFilesystem: false (volume monté /app/data)    |   |
|   |                                                                |   |
|   |  [Container Gunicorn / Flask]  <--->  [SQLite Database]        |   |
|   +----------------------------------------------------------------+   |
|                               |                                        |
+-------------------------------|----------------------------------------+
                                | Logs & Métriques
                                v
+------------------------------------------------------------------------+
|                    Monitoring & Observabilité                          |
|                                                                        |
|   [Prometheus] (Métriques HTTP & Pod)  <--+                            |
|   [Grafana Loki] (Logs structurés JSON) <-+--> [Grafana Dashboards]    |
|                                                - Alertes Suspicious    |
|                                                - Taux d'erreurs 4xx/5xx|
+------------------------------------------------------------------------+
```

---

## 2. Modèle de menace STRIDE

L'analyse de risques et la modélisation des menaces selon la méthodologie **STRIDE** (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege) permettent de cartographier systématiquement les vulnérabilités du système HelpDesk par rapport au référentiel international **OWASP Top 10 (2021)**.

### 2.1 Matrice STRIDE & Cartographie OWASP Top 10

| Catégorie STRIDE | Menace identifiée dans HelpDesk | Composant vulnérable | Impact potentiel | Catégorie OWASP Top 10 | Criticité |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Spoofing** *(Usurpation d'identité)* | Vol de cookies de session via script malveillant ou session sans expiration stricte | Module d'authentification Flask-Login / Cookies | Prise de contrôle de compte utilisateur ou administrateur | **A07:2021** – Identification and Authentication Failures | Élevée (HIGH) |
| **Tampering** *(Altération de données)* | Injection SQL dans la fonctionnalité de recherche permettant la modification ou destruction de tickets | Route `/api/tickets/search` | Altération de l'intégrité de la base de données, écriture non autorisée | **A03:2021** – Injection | Critique (CRITICAL) |
| **Repudiation** *(Répudiation)* | Absence de journalisation immuable lors des suppressions de tickets ou des actions de gestion des utilisateurs | Routes `/admin` et `/ticket/<id>/delete` | Impossibilité de tracer l'auteur d'un acte malveillant ou d'une suppression frauduleuse | **A09:2021** – Security Logging and Monitoring Failures | Moyenne (MEDIUM) |
| **Information Disclosure** *(Divulgation d'informations)* | Fuite d'une clé API sensible dans le code source versionné et fuite de données via XSS | Racine du dépôt (`backend/app.py`) et templates | Accès non autorisé à des API tierces, exfiltration de données de tickets confidentiels | **A02:2021** – Cryptographic Failures / **A01:2021** | Critique (CRITICAL) |
| **Denial of Service** *(Déni de service)* | Absence de limitation de requêtes (rate limiting) sur l'endpoint d'authentification et de recherche | Routes `/login` et `/api/tickets/search` | Épuisement des ressources CPU/mémoire du pod, blocage de l'accès aux utilisateurs légitimes | **A05:2021** – Security Misconfiguration | Moyenne (MEDIUM) |
| **Elevation of Privilege** *(Élévation de privilèges)* | Accès direct non contrôlé aux identifiants d'objets (IDOR / BOLA) sur les détails de tickets | Route `/ticket/<int:ticket_id>` | Un utilisateur standard lit ou manipule les tickets d'administrateurs ou d'autres utilisateurs | **A01:2021** – Broken Access Control | Élevée (HIGH) |

---

## 3. Vulnérabilités initiales (avant correction)

Cette section documente de manière exhaustive les 4 vulnérabilités intentionnelles introduites dans le cadre pédagogique du projet, leur démonstration d'exploitabilité, les correctifs appliqués et les preuves de vérification.

```
+-------------------------------------------------------------------------+
|                  VULNÉRABILITÉS TRAITÉES DANS LE PROJET                 |
|                                                                         |
|  [V1] Injection SQL (CWE-89 / OWASP A03)                                |
|  [V2] Cross-Site Scripting (XSS) stocké (CWE-79 / OWASP A03)            |
|  [V3] Broken Access Control / IDOR (CWE-639 / OWASP A01)                |
|  [V4] Exposition de secrets dans le code source (CWE-798 / OWASP A02)   |
+-------------------------------------------------------------------------+
```

---

### V1 — Injection SQL (OWASP A03:2021 – Injection / CWE-89)

- **Localisation** : `backend/app.py`, route `GET /api/tickets/search`
- **Cause fondamentale** : Concaténation directe et non assainie de paramètres fournis par l'utilisateur (`request.args.get('q')`) au sein d'une chaîne SQL exécutée directement par le moteur SQLAlchemy.
- **Code vulnérable** :
  ```python
  @app.route('/api/tickets/search')
  def api_search_tickets():
      q = request.args.get('q', '')
      # VULNÉRABILITÉ : Concaténation de chaînes dans la requête SQL
      query = text("SELECT id, title, status FROM ticket WHERE title LIKE '%" + q + "%'")
      result = db.session.execute(query)
      tickets = [{"id": row[0], "title": row[1], "status": row[2]} for row in result]
      return jsonify(tickets)
  ```
- **Impact métier et technique** : Extraction totale des données confidentielles de la table `ticket` et `user` (y compris hash de mots de passe via `UNION SELECT`), contournement des logiques applicatives, risque d'altération ou de destruction des données.
- **Preuve de concept (PoC)** :
  L'envoi de la charge utile `' OR '1'='1` via la requête HTTP :
  ```bash
  curl -s "http://localhost:5000/api/tickets/search?q='%20OR%20'1'='1"
  ```
  Retourne la liste intégrale des tickets existants en base, indépendamment du terme recherché.
- **Correction apportée** : Remplacement de la concaténation brute par une requête préparée paramétrée utilisant la syntaxe de liaison de variables `:param` de SQLAlchemy.
- **Code corrigé** :
  ```python
  @app.route('/api/tickets/search')
  def api_search_tickets():
      q = request.args.get('q', '')
      # CORRECTION : Requête préparée avec bind parameters
      query = text("SELECT id, title, status FROM ticket WHERE title LIKE :pattern")
      result = db.session.execute(query, {"pattern": f"%{q}%"})
      tickets = [{"id": row[0], "title": row[1], "status": row[2]} for row in result]
      return jsonify(tickets)
  ```
- **Vérification** : La même requête avec le payload `' OR '1'='1` recherche désormais littéralement la chaîne de caractères et retourne une liste vide `[]`. Aucun enregistrement parasite n'est divulgué.

---

### V2 — Cross-Site Scripting (XSS) stocké (OWASP A03:2021 – Injection / CWE-79)

- **Localisation** : `backend/templates/ticket.html` (affichage de la description du ticket)
- **Cause fondamentale** : Utilisation explicite du filtre Jinja2 `| safe` qui neutralise l'échappement automatique des caractères HTML sensibles (`<`, `>`, `&`, `"`, `'`).
- **Template vulnérable** :
  ```html
  <div class="card-body">
      <!-- VULNÉRABILITÉ : Désactivation de l'échappement HTML via | safe -->
      <p class="card-text">{{ ticket.description | safe }}</p>
  </div>
  ```
- **Impact métier et technique** : Exécution de code JavaScript arbitraire dans le contexte du navigateur des utilisateurs (notamment de l'administrateur consultant le ticket), vol de jetons de session, redirection vers des sites d'hameçonnage, manipulation du DOM.
- **Preuve de concept (PoC)** :
  Création d'un ticket avec la charge utile suivante dans la description :
  ```html
  <img src="x" onerror="alert('XSS-VULNERABILITY-DEMO')">
  ```
  Lors de la consultation de la page `/ticket/3`, la boîte de dialogue JavaScript s'exécute immédiatement.
- **Correction apportée** : Suppression intégrale du filtre `| safe`, réactivant le mécanisme de sécurisation par défaut de Jinja2 qui convertit les balises en entités HTML sûres (`&lt;`, `&gt;`).
- **Code corrigé** :
  ```html
  <div class="card-body">
      <!-- CORRECTION : Échappement HTML automatique activé -->
      <p class="card-text">{{ ticket.description }}</p>
  </div>
  ```
- **Vérification** : Le payload injecté est rendu sous la forme de texte brut visible `&lt;img src=x onerror=...&gt;`. Aucun script ne s'exécute dans le navigateur.

---

### V3 — Contrôle d'accès défaillant / IDOR (OWASP A01:2021 – Broken Access Control / CWE-639)

- **Localisation** : `backend/app.py`, route `GET /ticket/<int:ticket_id>`
- **Cause fondamentale** : Absence de vérification d'autorisation entre l'utilisateur actuellement authentifié (`current_user.id`) et le propriétaire de la ressource demandée (`ticket.user_id`).
- **Code vulnérable** :
  ```python
  @app.route('/ticket/<int:ticket_id>')
  @login_required
  def view_ticket(ticket_id):
      ticket = Ticket.query.get_or_404(ticket_id)
      # VULNÉRABILITÉ : Tout utilisateur authentifié peut voir n'importe quel ticket
      return render_template('ticket.html', ticket=ticket)
  ```
- **Impact métier et technique** : Violation directe de la confidentialité des données (Insecure Direct Object References). Un utilisateur authentifié standard peut accéder aux requêtes de support, réinitialisations de mot de passe et données personnelles de tous les autres utilisateurs ou administrateurs.
- **Preuve de concept (PoC)** :
  1. Connexion en tant qu'utilisateur standard `alice` (ID: 2).
  2. Navigation forcée vers l'URL `/ticket/4` (ticket confidentiel appartenant à `admin`). Le contenu s'affiche sans restriction.
- **Correction apportée** : Implémentation d'une règle de contrôle d'accès strict autorisant la consultation uniquement si l'utilisateur est le créateur du ticket OU s'il possède le rôle `admin`. Tout accès non légitime renvoie une exception HTTP 403 Forbidden.
- **Code corrigé** :
  ```python
  @app.route('/ticket/<int:ticket_id>')
  @login_required
  def view_ticket(ticket_id):
      ticket = Ticket.query.get_or_404(ticket_id)
      # CORRECTION : Contrôle strict de propriété ou rôle administrateur
      if ticket.user_id != current_user.id and current_user.role != 'admin':
          logger.warning(f"UNAUTHORIZED_ACCESS_ATTEMPT: User {current_user.username} tried accessing ticket {ticket_id}")
          abort(403)
      return render_template('ticket.html', ticket=ticket)
  ```
- **Vérification** : Lorsque `alice` tente d'accéder à `/ticket/4`, le serveur répond avec un code d'erreur `HTTP 403 Forbidden` et journalise l'événement de sécurité.

---

### V4 — Secret d'authentification exposé dans le code (OWASP A02:2021 – Cryptographic Failures / CWE-798)

- **Localisation** : `backend/app.py`, ligne 1 en en-tête de fichier
- **Cause fondamentale** : Présence d'un secret d'API codé en dur directement dans le code source versionné sur le gestionnaire de code.
- **Code vulnérable** :
  ```python
  # FAKE_API_KEY = "sk-test-FAKESECRETKEY1234567890abcdef"
  ```
- **Impact métier et technique** : En environnement réel, la compromission d'une clé API permet l'usurpation totale du service tiers associé (fournisseur de messagerie, paiement, infrastructure cloud), entraînant d'importantes fuites de données et des coûts financiers imprévus.
- **Preuve de détection** :
  L'outil de détection statique de secrets **Gitleaks** lève une alerte bloquante lors de l'exécution du stage `secret-scan` :
  ```json
  {
    "Description": "Generic API Key",
    "Secret": "sk-test-FAKESECRETKEY1234567890abcdef",
    "File": "backend/app.py",
    "Line": 1,
    "Commit": "a1b2c3d4e5f6..."
  }
  ```
- **Procédure de remédiation et de rotation de clés** :
  1. **Révocation immédiate** : Invalidité déclarée de la clé compromise auprès du fournisseur tiers ou remplacement immédiat dans les variables sécurisées du projet (`GitLab CI/CD Variables` masquées et protégées).
  2. **Nettoyage du code** : Suppression de l'affectation ou du commentaire dans le code source.
  3. **Externalisation de la configuration** : Lecture dynamique des secrets via les variables d'environnement (`os.getenv("SECRET_KEY")`).
  4. **Réécriture de l'historique** (si applicable en environnement de production via `git-filter-repo` ou `BFG Repo-Cleaner`).
- **Vérification** : Après retrait du secret du code source et rejeu du stage `secret-scan`, Gitleaks s'exécute avec le statut de sortie `exit code 0`, attestant qu'aucun secret n'est présent.

---

## 4. Pipeline CI/CD — Contrôles et politique de blocage

Le pipeline DevSecOps implémenté dans `.gitlab-ci.yml` repose sur le principe de validation continue par jalons de sécurité.

### 4.1 Description des 9 étapes du pipeline

```
+---------------------------------------------------------------------------------+
|                              ÉTAPES DU PIPELINE CI/CD                           |
|                                                                                 |
|  1. build            Installation des dépendances Python (requirements.txt)     |
|  2. test             Tests unitaires et fonctionnels automatisés (pytest)       |
|  3. sast             Analyse statique du code source applicatif (Semgrep)       |
|  4. secret-scan      Détection de secrets et identifiants exposés (Gitleaks)    |
|  5. dependency-scan  Recherche de vulnérabilités et CVEs connues (Trivy SCA)   |
|  6. docker-build     Construction de l'image Docker immuable                    |
|  7. image-scan       Analyse des vulnérabilités de l'image de conteneur (Trivy) |
|  8. deploy           Déploiement sur cluster Kubernetes (Minikube / manifests)  |
|  9. dast             Analyse dynamique de l'application déployée (OWASP ZAP)    |
+---------------------------------------------------------------------------------+
```

1. **build** : Vérification de la compatibilité des paquets et compilation des artefacts Python au sein d'un environnement hermétique.
2. **test** : Exécution de la suite de tests unitaires avec `pytest` garantissant l'intégrité fonctionnelle et les règles de validation métier.
3. **sast (Static Application Security Testing)** : Scan du code Python avec **Semgrep** ciblant les règles de sécurité `p/python`, `p/owasp-top-ten` et `p/flask`.
4. **secret-scan** : Exécution de **Gitleaks** sur l'historique et le commit courant pour prévenir toute fuite de token, clé privée ou certificat.
5. **dependency-scan (SCA)** : Scan de composition logicielle réalisé par **Trivy** sur `requirements.txt` pour identifier les composants tiers vulnérables.
6. **docker-build** : Construction d'une image Docker multi-stage optimisée basée sur Python Alpine/Slim, avec tagging strict.
7. **image-scan** : Analyse approfondie par **Trivy** des couches du conteneur et des paquets système de l'OS sous-jacent.
8. **deploy** : Application déclarative des manifests Kubernetes durcis dans le namespace isolé `helpdesk`.
9. **dast (Dynamic Application Security Testing)** : Analyse de vulnérabilités en boîte noire exécutée par **OWASP ZAP** contre l'instance en ligne.

---

### 4.2 Politique de blocage (justification opérationnelle)

La politique de blocage définit les seuils d'acceptation du risque ("Security Quality Gates") régissant le passage d'une étape à la suivante.

| Condition détectée | Action déclenchée | Justification de la politique |
| :--- | :--- | :--- |
| **Secret détecté (Gitleaks)** | ❌ **Bloquant** (`allow_failure: false`) | Un secret exposé dans le code compromet immédiatement l'infrastructure ou les services associés ; aucun déploiement ne peut être toléré. |
| **CVE CRITICAL dans dépendances (Trivy SCA)** | ❌ **Bloquant** (`allow_failure: false`) | Une vulnérabilité critique dans une librairie tierce est activement exploitable à distance sans authentification préalable. |
| **CVE CRITICAL dans image Docker (Trivy)** | ❌ **Bloquant** (`allow_failure: false`) | Un conteneur dont la base OS contient des failles critiques expose le cluster Kubernetes à des risques d'évasion de conteneur. |
| **Finding ERROR dans SAST (Semgrep)** | ❌ **Bloquant** (`allow_failure: false`) | Les motifs de programmation dangereux (injections SQL, désactivation CSRF, XSS) ne doivent jamais franchir la branche principale. |
| **Tests unitaires en échec (pytest)** | ❌ **Bloquant** (`allow_failure: false`) | La stabilité applicative est un prérequis indispensable ; un correctif de sécurité ne doit pas introduire de régression fonctionnelle. |
| **Findings HIGH (non-CRITICAL)** | ⚠️ **Avertissement** (`allow_failure: true`) | Génère un artefact d'audit pour revue d'équipe sans bloquer la livraison continue, permettant une remédiation planifiée. |

---

### 4.3 Preuve de blocage (Scénario de démonstration pour soutenance)

Pour démontrer l'efficacité des gardes-fous du pipeline lors de la soutenance :

1. **Injection d'un secret factice** : Ajout volontaire de la chaîne `FAKE_API_KEY = "sk-test-FAKESECRETKEY1234567890abcdef"` dans `backend/app.py`.
2. **Déclenchement du pipeline** : Commit et push sur la branche de test.
3. **Résultat observé** : 
   - Les étapes `build`, `test` et `sast` s'exécutent avec succès.
   - L'étape `secret-scan` échoue immédiatement avec code d'erreur `1` :
     ```text
     [FAIL] Gitleaks detected 1 secret leak in commit 4b8d7f2!
     RuleID: generic-api-key
     Path: backend/app.py
     Line: 1
     Job failed: exit code 1
     ```
   - Les étapes ultérieures (`docker-build`, `deploy`, `dast`) sont **automatiquement annulées**, empêchant tout déploiement non sécurisé.
4. **Correction et validation** : Suppression de la ligne problématique et nouveau push. Le job `secret-scan` passe au vert et le déploiement se poursuit normalement.

---

## 5. Kubernetes — Durcissement

Le déploiement applicatif a fait l'objet d'un durcissement multi-niveaux au sein du cluster Kubernetes.

### 5.1 Sécurisation du Pod (`securityContext`)

Le manifest `k8s/deployment.yaml` applique un principe de moindre privilège absolu au conteneur applicatif :

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
      containers:
        - name: helpdesk
          image: helpdesk:latest
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
          resources:
            limits:
              cpu: "500m"
              memory: "512Mi"
            requests:
              cpu: "100m"
              memory: "128Mi"
```

- **`runAsNonRoot: true` & `runAsUser: 1001`** : Interdit impérativement l'exécution du processus avec les privilèges de l'administrateur système `root` (UID 0), prévenant les attaques par évasion de conteneur (*container breakout*).
- **`allowPrivilegeEscalation: false`** : Bloque l'élévation de privilèges via les binaires SUID/SGID au sein du conteneur.
- **`capabilities.drop: ["ALL"]`** : Révoque l'ensemble des privilèges Linux par défaut du noyau (`CAP_NET_RAW`, `CAP_SYS_ADMIN`, etc.), réduisant drastiquement la surface d'attaque.
- **Limitation de ressources (`resources`)** : Empêche les attaques par épuisement de ressources (DDoS interne) pouvant impacter les autres charges de travail du cluster.

---

### 5.2 Segmentation réseau via `NetworkPolicy`

Quatre politiques réseau déclaratives garantissent un cloisonnement étanche :

```
+-------------------------------------------------------------------------+
|                  POLITIQUES RÉSEAU (NetworkPolicy)                      |
|                                                                         |
|  1. default-deny-all              Isolation complète par défaut         |
|  2. allow-backend-ingress         Autorise uniquement le trafic Web     |
|  3. allow-backend-egress-dns      Autorise uniquement les résolutions   |
|                                   DNS vers kube-dns (port 53 UDP/TCP)   |
|  4. allow-backend-egress-internet Autorise les sorties HTTPS vers des   |
|                                   fournisseurs approuvés (port 443)     |
+-------------------------------------------------------------------------+
```

1. **`default-deny-all`** : Politique zéro-trust appliquant un blocage absolu de tout trafic entrant (*ingress*) et sortant (*egress*) pour l'ensemble des pods du namespace `helpdesk`.
2. **`allow-backend-ingress`** : Autorise expressément les connexions entrantes sur le port applicatif TCP `5000` provenant de l'Ingress Controller ou des services de supervision autorisés.
3. **`allow-backend-egress-dns`** : Règle de sortie stricte limitant le trafic sortant au seul service `kube-dns` / `CoreDNS` du namespace `kube-system` sur le port `53` (UDP et TCP).
4. **`allow-backend-egress-internet`** : Restreint le trafic sortant vers l'extérieur aux seuls flux HTTPS légitimes (port `443`), interdisant tout canal de commande et contrôle (C2) arbitraire sur des ports non standard.

---

### 5.3 Gestion des secrets Kubernetes

Aucun secret, token ou chaîne d'authentification n'est stocké en clair dans les dépôts Git ou dans les fichiers manifests :
- Utilisation de manifests Kubernetes de type `Secret` injectés dynamiquement via la directive `secretKeyRef` ou `envFrom`.
- La clé de session Flask `SECRET_KEY` est transmise aux variables d'environnement du pod au runtime sans persistance sur le disque du conteneur.
- Préconisation de chiffrement au repos des secrets dans `etcd` au niveau de l'API Server de Kubernetes.

---

## 6. Tests DAST — OWASP ZAP

Les tests dynamiques de sécurité d'applications (DAST) ont été conduits à l'aide d'**OWASP ZAP** (Zed Attack Proxy) en mode boîte noire contre l'environnement d'exécution déployé.

### 6.1 Résultats avant correction des vulnérabilités

| Alerte de vulnérabilité | Niveau de Risque | CWE / Référence | URL & Paramètre concerné | Impact observé |
| :--- | :--- | :--- | :--- | :--- |
| **SQL Injection** | **Élevé** (High) | CWE-89 | `/api/tickets/search?q=` | Extraction d'enregistrements non sollicités suite à l'injection de méta-caractères SQL (`'`). |
| **Cross-Site Scripting (Stored)** | **Élevé** (High) | CWE-79 | `/ticket/<id>` (champ `description`) | Réflexion et exécution d'instructions JavaScript arbitraires enregistrées en base. |
| **Absence de protection anti-clickjacking** | Moyen (Medium) | CWE-1021 | En-têtes HTTP de toutes les routes | Absence de l'en-tête `X-Frame-Options` ou `Content-Security-Policy: frame-ancestors`. |
| **Attributs de cookie de session incomplets** | Faible (Low) | CWE-614 | Cookie `session` | Manque temporaire des drapeaux `HttpOnly` et `SameSite=Lax`. |

---

### 6.2 Résultats après remédiation

| Alerte de vulnérabilité | Statut après remédiation | Mécanisme de validation |
| :--- | :--- | :--- |
| **SQL Injection** | ✅ **Non détectée / Résolue** | La sonde ZAP injecte des payloads SQL classiques et booléens sans altération du comportement du serveur (code HTTP 200 avec tableau vide). |
| **Cross-Site Scripting (Stored)** | ✅ **Non détectée / Résolue** | Les balises injectées sont rigoureusement converties en texte brut dans le document DOM. |
| **Broken Access Control** | ✅ **Sécurisé** | Tentative de parcours d'ID (fuzzing `/ticket/{id}`) rejetée systématiquement avec le code `HTTP 403 Forbidden`. |
| **Durcissement des en-têtes HTTP** | ✅ **Résolue** | Ajout des en-têtes de sécurité recommandés (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`). |

---

## 7. Observabilité et réponse à incident

Une posture de sécurité efficace repose sur la capacité à détecter immédiatement les signaux faibles d'une attaque et à y répondre de manière structurée.

### 7.1 Journaux d'événements structurés (Logging)

L'application HelpDesk implémente un module de journalisation standardisé (`backend/logger.py`) configuré pour émettre des logs structurés au format JSON :
- **Traçabilité des authentifications** : Chaque tentative de connexion (succès ou échec) est journalisée avec l'adresse IP cliente, l'horodatage précis (UTC ISO 8601), le nom d'utilisateur et le User-Agent.
- **Détection proactive de motifs hostiles** : Interception au niveau applicatif des séquences caractéristiques d'injection SQL (`UNION SELECT`, `' OR '1'='1`, `SLEEP()`) ou de balises de script (`<script>`, `onerror=`).
- **Événements d'autorisation** : Tout accès refusé (`HTTP 403`) ou tentative d'accès à une ressource d'un tiers génère un événement de niveau `WARNING`.
- **Règle de confidentialité des logs** : Masquage systématique des mots de passe, tokens et clés secrètes avant toute écriture de log.

Exemple de log structuré émis lors d'une attaque :
```json
{
  "timestamp": "2026-11-16T14:15:32.418Z",
  "level": "WARNING",
  "event_type": "SUSPICIOUS_INPUT_DETECTED",
  "client_ip": "192.168.49.1",
  "endpoint": "/api/tickets/search",
  "method": "GET",
  "query_param": "' OR '1'='1",
  "action_taken": "INPUT_SANITIZED",
  "user": "anonymous"
}
```

---

### 7.2 Simulation d'attaque fictive

Dans le cadre des scénarios de validation opérationnelle :
1. Une série de requêtes d'injection SQL est envoyée vers `/api/tickets/search?q='%20OR%20'1'='1`.
2. Le système émet immédiatement des alertes `SUSPICIOUS_INPUT_DETECTED`.
3. Les agents de collecte de **Grafana Loki** agrègent les entrées de logs et déclenchent une alerte visible en temps réel sur le tableau de bord de supervision de sécurité.

---

### 7.3 Plan de réponse à incident (Incident Response Playbook)

Le tableau ci-dessous formalise les 5 phases du plan de réponse à incident opérationnel :

| Phase | Objectif opérationnel | Actions concrètes menées | Responsable |
| :--- | :--- | :--- | :--- |
| **1. Détecter** | Identifier l'anomalie ou l'intrusion en cours | Détection d'un pic anormal d'erreurs 403/500 ou alerte Grafana basée sur les patterns suspects dans Loki. | Équipe SOC / DevSecOps |
| **2. Contenir** | Stopper la propagation de l'attaque et préserver les preuves | Isoler le pod ciblé à l'aide de la commande `kubectl cordon` ou modification immédiate de la `NetworkPolicy` pour couper l'accès externe. | Ingénieur DevOps / SecOps |
| **3. Éradiquer** | Supprimer la cause racine de la vulnérabilité | Identification du commit responsable, correction du code source, révocation des accès ou clés potentiellement compromises. | Équipe Développement / Sécurité |
| **4. Rétablir** | Restaurer le service dans un état nominal et validé | Validation du correctif par le pipeline CI/CD complet et redéploiement d'une nouvelle version de conteneur étiquetée. | Équipe DevSecOps |
| **5. Leçons apprises** | Empêcher la récurrence de l'incident | Rédaction d'un rapport post-mortem, enrichissement des règles Semgrep et mise à jour de la politique de blocage du pipeline. | Ensemble de l'équipe projet |

---

## 8. Limites et perspectives

### 8.1 Limites du dispositif actuel
- **Couverture des outils d'analyse statique** : Les outils SAST (Semgrep) et d'analyse de secrets (Gitleaks) s'appuient sur des expressions régulières et des arbres syntaxiques abstraits (AST) ; ils ne garantissent pas l'absence absolue de failles de logique métier complexe et peuvent générer des faux positifs ou négatifs.
- **Limites du DAST en environnement éphémère** : OWASP ZAP explore les routes découvertes par crawling, mais peut omettre des fonctionnalités nécessitant des cinématiques d'authentification multi-étapes complexes (MFA, workflows asynchrones).
- **Surface d'attaque d'infrastructure** : Bien que le pod soit contraint par `securityContext`, l'hôte Minikube sous-jacent partage le noyau de la machine de développement ; un durcissement complet en production requiert un environnement Kubernetes certifié CIS Benchmark.

### 8.2 Perspectives et évolutions futures
1. **Gestion avancée des secrets avec Sealed Secrets ou HashiCorp Vault** : Remplacement des secrets Kubernetes natifs par des secrets chiffrés asymétriquement pouvant être versionnés en toute sécurité dans Git.
2. **Signature cryptographique des images & SBOM (Software Bill of Materials)** : Intégration de **Cosign** (projet Sigstore) pour signer numériquement les images Docker à l'issue de l'étape de scan, et génération de nomenclatures logicielles complètes au format CycloneDX/SPDX via **Syft**.
3. **Contrôleur d'admission dynamique (Kyverno / OPA Gatekeeper)** : Mise en place d'un moteur de règles d'admission interdisant formellement le déploiement sur le cluster de tout pod ne respectant pas les politiques de sécurité (ex. rejet immédiat des images non signées ou conteneurs s'exécutant en root).
4. **Sécurité d'exécution (Runtime Security) avec Falco** : Déploiement d'une sonde de détection au niveau du noyau eBPF pour repérer en temps réel les comportements anormaux au sein des conteneurs (appels système inattendus, modifications de binaires système).

---
*Fin du rapport de sécurité — HelpDesk DevSecOps — TEK-UP University 2026*
