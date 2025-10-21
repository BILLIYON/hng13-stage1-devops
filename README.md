# 🚀 DevOps Stage 1 — Automated Deployment Script (`deploy.sh`)

## 📖 Overview

This project automates end-to-end application deployment on a remote Ubuntu 22.04 EC2 instance using **Docker** and **Nginx**.
It supports both **Dockerfile** and **docker-compose.yml** workflows, sets up all required dependencies, and validates the deployment automatically.

## 🧩 Features

* ✅ Remote environment preparation (Docker, Docker Compose, Nginx)
* ✅ Repository cloning or updating (HTTPS / SSH + PAT supported)
* ✅ Docker build and container run with auto-port detection
* ✅ Nginx reverse-proxy configuration (auto-generated)
* ✅ Deployment validation via `curl`
* ✅ Logging and error handling
* ✅ Idempotent re-execution (safe to rerun)
* ✅ Cleanup option (`--cleanup`)

---

## ⚙️ Prerequisites

Before running the script, ensure:

1. You have an **Ubuntu 22.04 EC2 instance** accessible via SSH.
2. Your **local machine** has:

   * `bash`, `git`, and `curl`
   * Access to your EC2 via SSH (key-pair configured)
3. A **GitHub repository** containing:

   * A `Dockerfile` or `docker-compose.yml`
   * Any required app files
4. Optional: a **GitHub Personal Access Token (PAT)** if using HTTPS cloning for private repos.

---

## 🪄 Usage

### 🧠 Interactive Mode

Run the script directly and follow the prompts:

```bash
chmod +x deploy.sh
./deploy.sh
```

You’ll be asked for:

* Repository URL
* GitHub PAT (if required)
* Remote EC2 IP
* SSH username (e.g., ubuntu)
* SSH key path (e.g., ~/.ssh/mykey.pem)
* Application port (e.g., 5000)

---

### ⚡ Non-Interactive Mode

You can also pass all parameters as flags:

```bash
./deploy.sh \
  --repo https://github.com/username/myapp.git \
  --pat ghp_XXXXXXXXXXXXXXXXXXXX \
  --remote_ip 18.222.45.123 \
  --ssh_user ubuntu \
  --ssh_key ~/.ssh/mykey.pem \
  --app_port 5000
```

---

## 🧰 What Happens Under the Hood

1. **Connectivity Check:**
   The script verifies SSH and `sudo` access to your EC2.

2. **Environment Setup:**
   Installs `docker`, `docker-compose`, and `nginx` if missing.

3. **Code Deployment:**

   * If the repo exists → runs `git pull`
   * Otherwise → runs `git clone`
   * Supports HTTPS + PAT and SSH methods

4. **Containerization:**

   * Builds Docker image and runs container
   * Or starts services using `docker-compose up -d`

5. **Reverse Proxy Setup:**

   * Creates `/etc/nginx/sites-available/deploy_app_<timestamp>.conf`
   * Links it to `sites-enabled/` and reloads Nginx

6. **Validation:**

   * Confirms Docker and Nginx are active
   * Tests the app endpoint using `curl`

7. **Logging:**

   * Logs all actions to `logs/deploy_<timestamp>.log`
   * Displays key progress updates with colorized output

---

## 🧹 Cleanup Mode

To remove all deployed containers, Nginx configs, and logs:

```bash
./deploy.sh --cleanup
```

This deletes:

* All containers and images
* Nginx configuration files related to the app
* Temporary logs and working directories

---

## 🧾 Example Output

```
[INFO] Starting deployment...
[INFO] Connecting to 18.222.45.123...
[INFO] Docker and Nginx installed.
[INFO] Application deployed successfully at http://18.222.45.123
```

---

## 🧠 Notes

* The script is **idempotent** — re-running it redeploys safely.
* All errors are logged to `logs/` for debugging.
* For production, avoid passing PAT directly; use SSH cloning instead.
* Designed for evaluation on **Ubuntu 22.04 EC2**.

---

## ✅ Submission Checklist

* [x] `deploy.sh` is executable and self-contained
* [x] `README.md` explains usage, parameters, and cleanup
* [x] Works with a new EC2 instance without manual prep
* [x] Logs outputs and exits cleanly with `exit 0` on success
