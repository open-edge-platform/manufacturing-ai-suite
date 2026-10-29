# Prepare the Edge Nodes

Run the following on each edge node from an existing administrator account, not on the central Hermes host.

## Create or reuse the deployment account

Check whether the account already exists:

```bash
id deploy
```

If it does not exist, create it:

```bash
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy
```

Set the password interactively; do not put it in a script or chat. Reuse an existing deployment account rather than deleting and recreating it, which would remove its home directory, keys, configuration, and application data.

Once Docker is installed and its `docker` group exists, grant the account Docker access:

```bash
sudo usermod -aG docker deploy
```

If the installer must install packages or change group membership, arrange the required `sudo` permissions under your site's policy. On Ubuntu/Debian, an administrator can grant temporary membership in the `sudo` group:

```bash
sudo usermod -aG sudo deploy
```

This grants broad administrative access, so prefer having an administrator preinstall packages and configure Docker access where possible. Remove temporary sudo access after preparation if it is no longer needed. Docker group membership itself remains root-equivalent.

Open a fresh login session so the new group memberships take effect:

```bash
sudo -iu deploy
id
docker info
docker compose version
```

Use a login session rather than `su deploy`, which can retain the previous user's working directory and environment. Return to the administrator session with `exit` when finished. The fleet installer itself still runs on the central host.

Do not kill all processes belonging to `deploy`, delete the account, or remove all Docker containers and images as part of routine preparation. These actions can interrupt unrelated workloads and destroy data. Any reset must be separately planned, backed up, and limited to the intended deployment resources.

## Configure a proxy only if required

Skip this section on networks with direct outbound access. Replace `proxy.example.invalid` and the example port `8080` below with your site's approved proxy hostname and port.

For commands in the deployment user's current shell, set:

```bash
export HTTP_PROXY="http://proxy.example.invalid:8080"
export HTTPS_PROXY="$HTTP_PROXY"
export NO_PROXY="127.0.0.1,localhost,::1"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export no_proxy="$NO_PROXY"
```

Add node hostnames and internal service destinations to `NO_PROXY` as required by your network. These exports apply only to this shell and its child processes: later SSH sessions, Hermes commands, `sudo`, system services, and containers do not automatically inherit them. Configure the appropriate environment for each context that requires the proxy. Do not embed proxy credentials in committed files or chats.

For new containers and Docker build arguments, configure the Docker client as `deploy`:

```bash
install -d -m 0700 "$HOME/.docker"
```

Create or edit `$HOME/.docker/config.json` to include the following `proxies` object. If the file already exists, merge this object into it rather than overwriting registry credentials, credential-helper settings, or other configuration:

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

After saving, restrict access to the file:

```bash
chmod 600 "$HOME/.docker/config.json"
```

This Docker client configuration affects new containers and builds; it does **not** configure the Docker daemon's image pulls, existing containers, host package managers, or Git. Configure those separately, as described below.

### Docker daemon proxy

Image pulls are performed by the Docker daemon, which does not read the client configuration. Configure the daemon through a systemd drop-in, as an administrator with `sudo`:

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://proxy.example.invalid:8080"
Environment="HTTPS_PROXY=http://proxy.example.invalid:8080"
Environment="NO_PROXY=127.0.0.1,localhost,::1"
EOF
```

Reload systemd and restart Docker, then confirm that the daemon picked up the settings:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
systemctl show --property=Environment docker
```

Restarting Docker stops running containers unless live restore is enabled, so schedule it to avoid disrupting running workloads. If a drop-in file already exists, edit it instead of overwriting it. See [Docker daemon proxy configuration](https://docs.docker.com/engine/daemon/proxy/#systemd-unit-file) for details.

### Host package manager and Git

If the node installs packages through a proxy, configure `apt` as an administrator:

```bash
sudo tee /etc/apt/apt.conf.d/95proxy >/dev/null <<'EOF'
Acquire::http::Proxy "http://proxy.example.invalid:8080";
Acquire::https::Proxy "http://proxy.example.invalid:8080";
EOF
```

If the deployment user clones repositories over HTTP(S) through the proxy, configure Git as `deploy`:

```bash
git config --global http.proxy "http://proxy.example.invalid:8080"
git config --global https.proxy "http://proxy.example.invalid:8080"
```

Use only the approved proxy address; do not put proxy credentials in these files or in chats.
