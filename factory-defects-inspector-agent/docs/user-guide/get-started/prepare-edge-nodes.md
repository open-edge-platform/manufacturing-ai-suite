# Prepare the Edge Nodes

Do the tasks on this page on each edge node. Use an existing administrator account. Do not use the central Hermes host.

1. [Create or reuse the deployment account](#create-or-reuse-the-deployment-account)
2. [Configure a proxy](#configure-a-proxy-only-if-required) (only if your network needs one)

## Create or reuse the deployment account

**Caution:** Do not delete and recreate an existing deployment account. This removes its home directory, keys, configuration, and application data.

1. Check if the account exists:

   ```bash
   id deploy
   ```

2. If the account does not exist, create it. Enter the password when the command asks for it. Do not put the password in a script or a chat.

   ```bash
   sudo useradd -m -s /bin/bash deploy
   sudo passwd deploy
   ```

3. Give the account Docker access. Do this after Docker is installed and the `docker` group exists:

   ```bash
   sudo usermod -aG docker deploy
   ```

4. If the installer must install packages, give the account `sudo` access. Follow the policy of your site.

   **Caution:** The next command gives broad administrative access. If possible, install the packages and configure Docker access yourself. Remove the `sudo` access after preparation.

   On Ubuntu or Debian, this command gives temporary access:

   ```bash
   sudo usermod -aG sudo deploy
   ```

5. Open a login session so that the new group memberships apply. Do not use `su deploy`. It can keep the working directory and environment of the previous user.

   ```bash
   sudo -iu deploy
   id
   docker info
   docker compose version
   ```

6. Make sure that the commands succeed. Then run `exit` to return to the administrator session.

**Caution:** Do not do these actions during routine preparation:

- Kill all processes of `deploy`.
- Delete the account.
- Remove all Docker containers and images.

These actions can stop other workloads and destroy data. Plan, back up, and limit each reset to the intended deployment resources.

## Configure a proxy (only if required)

Skip this section if the node has direct outbound access.

In the examples, replace `proxy.example.invalid` and port `8080` with the approved proxy host and port of your site. Do not put proxy credentials in files or chats.

Do the steps in this order:

1. [Set the shell proxy](#set-the-shell-proxy)
2. [Set the Docker client proxy](#set-the-docker-client-proxy)
3. [Set the Docker daemon proxy](#set-the-docker-daemon-proxy)
4. [Set the apt and Git proxy](#set-the-apt-and-git-proxy)

### Set the shell proxy

1. Run these commands as `deploy`:

   ```bash
   export HTTP_PROXY="http://proxy.example.invalid:8080"
   export HTTPS_PROXY="$HTTP_PROXY"
   export NO_PROXY="127.0.0.1,localhost,::1"
   export http_proxy="$HTTP_PROXY"
   export https_proxy="$HTTPS_PROXY"
   export no_proxy="$NO_PROXY"
   ```

2. Add node hostnames and internal service destinations to `NO_PROXY` as your network needs.

**Note:** These settings apply only to this shell and its child processes. Later SSH sessions, Hermes commands, `sudo`, system services, and containers do not inherit them. Configure each of these contexts separately.

### Set the Docker client proxy

This setting affects new containers and Docker build arguments. It does not affect image pulls, existing containers, host package managers, or Git.

1. Create the Docker configuration directory as `deploy`:

   ```bash
   install -d -m 0700 "$HOME/.docker"
   ```

2. Add this `proxies` object to `$HOME/.docker/config.json`. If the file exists, merge the object into it. Do not overwrite registry credentials or credential-helper settings.

   ```json
   {
     "proxies": {
       "default": {
         "httpProxy": "http://proxy.example.invalid:8080",
         "httpsProxy": "http://proxy.example.invalid:8080",
         "noProxy": "127.0.0.1,localhost,::1"
       }
     }
   }
   ```

3. Restrict access to the file:

   ```bash
   chmod 600 "$HOME/.docker/config.json"
   ```

### Set the Docker daemon proxy

The Docker daemon pulls the images. It does not read the client configuration. Use a systemd drop-in file.

**Caution:** Restarting Docker stops the running containers, unless live restore is on. Do this when it does not interrupt running workloads.

1. Create the drop-in file as an administrator. If the file exists, edit it. Do not overwrite it.

   ```bash
   sudo mkdir -p /etc/systemd/system/docker.service.d
   sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
   [Service]
   Environment="HTTP_PROXY=http://proxy.example.invalid:8080"
   Environment="HTTPS_PROXY=http://proxy.example.invalid:8080"
   Environment="NO_PROXY=127.0.0.1,localhost,::1"
   EOF
   ```

2. Reload systemd and restart Docker:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart docker
   ```

3. Make sure that the daemon uses the settings:

   ```bash
   systemctl show --property=Environment docker
   ```

For more information, see [Docker daemon proxy configuration](https://docs.docker.com/engine/daemon/proxy/#systemd-unit-file).

### Set the apt and Git proxy

1. If the node installs packages through the proxy, configure `apt` as an administrator:

   ```bash
   sudo tee /etc/apt/apt.conf.d/95proxy >/dev/null <<'EOF'
   Acquire::http::Proxy "http://proxy.example.invalid:8080";
   Acquire::https::Proxy "http://proxy.example.invalid:8080";
   EOF
   ```

2. If `deploy` clones repositories over HTTP(S) through the proxy, configure Git as `deploy`:

   ```bash
   git config --global http.proxy "http://proxy.example.invalid:8080"
   git config --global https.proxy "http://proxy.example.invalid:8080"
   ```
