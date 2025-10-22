## 🧠 1. What’s the Task?

You’re asked to build a **robot (a Bash script)** that can:

1. Go to a **GitHub repo** (where your app lives),
2. Bring that app to a **remote computer** (your EC2 server),
3. Install everything it needs (Docker, Nginx),
4. Start the app automatically inside a container,
5. Set up a web “door” (Nginx) so people can visit it with a browser,
6. Write everything it does in a **log book** (so we can check what happened).

So instead of you typing 30 commands one by one,
your **robot (deploy.sh)** types them all **for you** in the right order — fast, repeatable, and with no mistakes. ⚙️

---

## 🧩 2. The Big Picture (The Flow)

Here’s what happens behind the scenes — imagine each step as a “LEGO block” that clicks into the next one:

| Step | What Happens                                      | Why It’s Important                            |
| ---- | ------------------------------------------------- | --------------------------------------------- |
| 🧱 1 | Script asks you questions (repo URL, IP, SSH key) | It needs to know what app to deploy and where |
| 🧱 2 | Script uses `git clone` to get your app           | Brings your code from GitHub to your EC2      |
| 🧱 3 | It SSHs into your EC2 (`ssh ubuntu@<ip>`)         | Logs into your remote server                  |
| 🧱 4 | It installs Docker, Docker Compose, Nginx         | Prepares your EC2 with the right tools        |
| 🧱 5 | It builds and runs your app with Docker           | Starts your app inside a container            |
| 🧱 6 | It writes an Nginx config file                    | Makes your app visible from the web           |
| 🧱 7 | It checks if the app is running                   | Makes sure deployment worked                  |
| 🧱 8 | It writes logs and finishes                       | Keeps records for debugging later             |

That’s all it does — one big sequence of smaller terminal commands.

---

## ⚙️ 3. What’s Inside `deploy.sh`

Let’s peek at the **key commands** and explain what they do like story steps:

---

### 🪄 Step 1: Ask for Inputs

```bash
read -p "Enter Git repo URL: " REPO_URL
read -p "Enter your EC2 IP: " REMOTE_IP
```

🧍‍♂️ → The robot asks you questions. You give it the “map” (repo) and the “destination” (server IP).

---

### 🪄 Step 2: Clone or Update Code

```bash
if [ -d "app" ]; then
  git -C app pull
else
  git clone $REPO_URL app
fi
```

🧱 → If the folder already exists, it just updates (`git pull`).
If not, it creates it (`git clone`).
This prevents duplicate folders and keeps the latest version.

---

### 🪄 Step 3: Log Into Your Server

```bash
ssh -i ~/.ssh/mykey.pem ubuntu@$REMOTE_IP "echo Connected!"
```

🔐 → Logs into your EC2 instance using your SSH key.
The `-i` flag means “use this identity file (key).”

---

### 🪄 Step 4: Prepare Environment

```bash
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx
```

🧰 → Installs the three tools your app needs.
The `-y` just says “yes to all confirmations.”

---

### 🪄 Step 5: Run the App

```bash
docker build -t myapp .
docker run -d -p 80:5000 myapp
```

🐳 → This builds the app’s **Docker image** and runs it inside a **container**.
The `-p 80:5000` means:
“Take traffic from outside (port 80) → send to inside app (port 5000).”

---

### 🪄 Step 6: Set Up Nginx

```bash
sudo tee /etc/nginx/sites-available/myapp.conf > /dev/null <<EOF
server {
  listen 80;
  location / {
    proxy_pass http://localhost:5000;
  }
}
EOF
```

🌍 → This creates a **doorway** for your app.
Anyone who visits your EC2’s IP (port 80) gets redirected to your app (port 5000 inside Docker).

Then it runs:

```bash
sudo ln -s /etc/nginx/sites-available/myapp.conf /etc/nginx/sites-enabled/
sudo systemctl reload nginx
```

That **activates** the config and reloads Nginx.

---

### 🪄 Step 7: Validate Everything

```bash
curl -I http://localhost
```

🤖 → The robot “visits” the site itself.
If it gets a **200 OK**, deployment worked!

---

### 🪄 Step 8: Logging

```bash
exec > >(tee -i logs/deploy_$(date +%F).log)
exec 2>&1
```

📝 → Everything the robot says gets written into a **log file** with today’s date.
`exec > >(tee …)` means “show output and save it.”

---

### 🪄 Step 9: Cleanup Option

```bash
if [[ "$1" == "--cleanup" ]]; then
  docker stop $(docker ps -q)
  docker rm $(docker ps -a -q)
  sudo rm /etc/nginx/sites-enabled/myapp.conf
fi
```

🧹 → Removes all containers and Nginx configs.
The `--cleanup` flag tells your robot to “undo” everything.

---

## 🧠 4. How the Syntaxes Work Together

Bash commands = like small puzzle pieces 🧩

They connect with:

* `;` → do one after another
* `&&` → do next only **if previous succeeded**
* `||` → do next only **if previous failed**
* `$VAR` → a “box” storing data (like your repo URL)
* `<<EOF ... EOF` → writes a file using text inside
* `$(...)` → runs a command and saves its result
* `|` → takes output of one command and feeds it into another (like a pipe)

Example:

```bash
ssh -i $SSH_KEY $USER@$IP "sudo apt update && sudo apt install -y docker.io"
```

Means:

> “Connect to my server, then only if updating works, install Docker.”

---

## 🎯 5. So What Did You Actually Build?

You created an **auto-deployment pipeline** — but manually, in Bash.

It:

1. Pulls the latest code →
2. Builds Docker image →
3. Starts the container →
4. Configures Nginx →
5. Validates →
6. Logs results

That’s basically what tools like **Jenkins**, **Ansible**, or **GitHub Actions** do behind the scenes.
This is the **manual version** — the foundation for all DevOps automation.

---

## 🧩 6. How to Think for Next Time

When building a new script:

1. **Plan the steps** you would do by hand.
2. **Turn each step into one Bash command.**
3. **Add variables** for things that change (repo, port, IP).
4. **Add checks and logs.**
5. **Run line by line, fix errors, then chain together.**




## 🧠 Simplified `deploy.sh` (Local-on-EC2 version)

```bash
#!/bin/bash
# ===============================
# DevOps Stage 1: Automated Deployment Script
# ===============================

# 1️⃣ Turn on safe mode — stops the script when any command fails
set -e

# 2️⃣ Create a timestamped log file
LOG_FILE="deploy_$(date +%F_%H-%M-%S).log"
exec > >(tee -i $LOG_FILE)
exec 2>&1

echo "[INFO] === Automated Deployment Started ==="

# 3️⃣ Ask user for key info (input prompts)
read -p "Enter Git repository URL: " REPO_URL
read -p "Enter GitHub Personal Access Token (leave empty if public): " PAT
read -p "Enter branch name (default: main): " BRANCH
read -p "Enter application port (e.g., 5000): " APP_PORT
BRANCH=${BRANCH:-main}

# 4️⃣ Clone the repository (using PAT if private)
if [ -d "app" ]; then
    echo "[INFO] Repository exists. Pulling latest changes..."
    git -C app pull origin $BRANCH
else
    echo "[INFO] Cloning repository..."
    if [ -z "$PAT" ]; then
        git clone -b $BRANCH $REPO_URL app
    else
        AUTH_URL=$(echo $REPO_URL | sed "s#https://#https://$PAT@#")
        git clone -b $BRANCH $AUTH_URL app
    fi
fi

cd app

# 5️⃣ Confirm Dockerfile or docker-compose.yml exists
if [ -f "docker-compose.yml" ]; then
    APP_TYPE="compose"
    echo "[INFO] docker-compose.yml found."
elif [ -f "Dockerfile" ]; then
    APP_TYPE="dockerfile"
    echo "[INFO] Dockerfile found."
else
    echo "[ERROR] No Dockerfile or docker-compose.yml found!"
    exit 1
fi

# 6️⃣ Update the system and install Docker, Docker Compose, and Nginx
echo "[INFO] Installing dependencies..."
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx

# 7️⃣ Enable Docker and Nginx to run on boot
sudo systemctl enable docker
sudo systemctl enable nginx
sudo systemctl start docker
sudo systemctl start nginx

# 8️⃣ Build and run the container
if [ "$APP_TYPE" == "compose" ]; then
    echo "[INFO] Starting with docker-compose..."
    sudo docker-compose down || true
    sudo docker-compose up -d --build
else
    echo "[INFO] Building and running Dockerfile..."
    sudo docker build -t myapp .
    sudo docker rm -f myapp-container || true
    sudo docker run -d -p $APP_PORT:$APP_PORT --name myapp-container myapp
fi

# 9️⃣ Configure Nginx reverse proxy
echo "[INFO] Setting up Nginx reverse proxy..."
NGINX_CONF="/etc/nginx/sites-available/myapp.conf"
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 🔟 Validate deployment
echo "[INFO] Validating deployment..."
sleep 5
curl -I http://localhost || echo "[WARN] Validation failed — check logs."

echo "[SUCCESS] Deployment complete!"
```

---

## 🪄 Step-by-Step Explanation (like you’re 5 🧸)

---

### 🧱 1️⃣ The Shebang Line

```bash
#!/bin/bash
```

👶 Means “Use Bash to run this script.”
It tells Linux: “This file contains Bash commands, not text.”

---

### 🧱 2️⃣ `set -e`

```bash
set -e
```

🧯 Means: “If any command fails, stop everything immediately.”
Prevents the robot from continuing when something breaks.

---

### 🧱 3️⃣ Logging

```bash
LOG_FILE="deploy_$(date +%F_%H-%M-%S).log"
exec > >(tee -i $LOG_FILE)
exec 2>&1
```

🪶

* `$(date +%F_%H-%M-%S)` → prints date/time like `2025-10-21_15-10-22`
* `tee` → shows and saves everything you see on screen into a file.
* `2>&1` → redirects both normal output and errors into one stream.

So all your progress gets saved in a nice log file automatically.

---

### 🧱 4️⃣ Asking for Inputs

```bash
read -p "Enter Git repository URL: " REPO_URL
```

🧍‍♂️ → Script pauses and asks you for the repo link.
What you type gets stored in `$REPO_URL`.

Example:

```
Enter Git repository URL: https://github.com/john/myapp.git
```

Now `$REPO_URL = "https://github.com/john/myapp.git"`

---

### 🧱 5️⃣ Handling Optional Inputs

```bash
BRANCH=${BRANCH:-main}
```

📦 Means: “If the user didn’t type a branch name, use ‘main’ by default.”

---

### 🧱 6️⃣ Cloning or Updating the Repo

```bash
if [ -d "app" ]; then
  git -C app pull origin $BRANCH
else
  git clone -b $BRANCH $REPO_URL app
fi
```

🧱 → If the folder already exists, go inside it and pull new code.
If not, clone it fresh.
This prevents double cloning.

If it’s a private repo, it replaces the link with your token:

```bash
AUTH_URL=$(echo $REPO_URL | sed "s#https://#https://$PAT@#")
```

That’s just Bash magic using `sed` to inject your PAT into the link.

---

### 🧱 7️⃣ Check for Docker File

```bash
if [ -f "docker-compose.yml" ]; then
```

🔍 Means: “If a file named docker-compose.yml exists...”
Otherwise check for Dockerfile.
If none exist → print error and stop.

---

### 🧱 8️⃣ Install Dependencies

```bash
sudo apt update -y
sudo apt install -y docker.io docker-compose nginx
```

🛠️ Updates the system and installs the three major tools:

* **Docker** → runs containers
* **Docker Compose** → runs multi-container apps
* **Nginx** → acts as web gate (reverse proxy)

---

### 🧱 9️⃣ Enable and Start Services

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

🚀 Ensures Docker and Nginx automatically start every time the server reboots.

---

### 🧱 🔟 Run the Container

```bash
sudo docker build -t myapp .
sudo docker run -d -p $APP_PORT:$APP_PORT --name myapp-container myapp
```

🐳

* `docker build` → builds your app’s image.
* `-t myapp` → gives it a name.
* `docker run -d` → starts it detached (in background).
* `-p 5000:5000` → connects your server’s port to the app inside.

---

### 🧱 11️⃣ Set Up Nginx Reverse Proxy

```bash
sudo bash -c "cat > /etc/nginx/sites-available/myapp.conf" <<EOF
```

📜 This creates a new Nginx config file using text that follows until `EOF`.

Inside, it says:

```nginx
server {
  listen 80;
  location / {
    proxy_pass http://localhost:$APP_PORT;
  }
}
```

Meaning:

> “When people visit port 80, send traffic to my app’s port inside Docker.”

Then it links and activates it:

```bash
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

### 🧱 12️⃣ Validation

```bash
curl -I http://localhost
```

👀 “Knock on the app’s door.”
If you get “200 OK,” it means it’s running.

---

### 🧱 13️⃣ Success Message

```bash
echo "[SUCCESS] Deployment complete!"
```

🎉 Prints confirmation.

---

## 🧩 7. In Simple English Summary

Here’s what your Bash robot does:

1. 🗣️ Asks you where your app lives.
2. 📦 Downloads it.
3. 🧰 Installs what’s missing.
4. 🐳 Runs your app inside Docker.
5. 🌍 Opens a web doorway with Nginx.
6. 🧪 Checks if it works.
7. 🧾 Saves everything in a log file.

---

## 🧠 8. What You Learned

* **`set -e`** stops errors from being ignored.
* **Variables (`$VAR`)** store info you can reuse.
* **`if ... then ... else`** controls flow.
* **`sudo`** gives permission for admin tasks.
* **`cat <<EOF ... EOF`** writes config files dynamically.
* **`docker`** and **`nginx`** make your app accessible from the web.
* **`curl`** is like a robot web browser to test sites.
