# Gitea Setup & Verification

Gitea runs in the `gitea` namespace with SQLite3 persistence (`/data` on `gitea-data-pvc`), Web UI/HTTPS Git exposed via Traefik at `https://git.francvok.from.hr/`, and Git SSH exposed through the Cloudflare Tunnel at `git-ssh.francvok.from.hr` (configured in [../cloudflared/config.yaml](../cloudflared/config.yaml)).

---

## 1. Deploy Gitea & Reload `cloudflared`

Ensure your `*.francvok.from.hr` wildcard `CNAME` points to your K3s Cloudflare Tunnel and no stale `git` / `git-ssh` `CNAME` points to `pc-dev`.

```bash
# Deploy Gitea
./deploy.sh ./gitea

# Sync cloudflared config.yaml (with git-ssh.francvok.from.hr -> gitea-svc:22) and restart pods
./deploy.sh ./cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflared
```

---

## 2. Verify Cluster Resources

```bash
kubectl get pods,pvc,svc,ingress -n gitea
kubectl logs -n gitea deploy/gitea --tail=100
kubectl logs -n cloudflared deploy/cloudflared --tail=100
```

Expected state:
- `gitea` pod is `Running` and `1/1` Ready.
- `gitea-data-pvc` is `Bound` (`10Gi`, `local-path`).
- `gitea-svc` exposes ports `80/TCP` and `22/TCP`.
- `gitea-ingress` shows host `git.francvok.from.hr`.

---

## 3. Initial Web Setup

1. Open `https://git.francvok.from.hr/` and complete Gitea's initial setup wizard (SQLite3, `git.francvok.from.hr`, and `git-ssh.francvok.from.hr` are pre-populated from [20-gitea.yaml](./20-gitea.yaml)).
2. Create your user account and add your SSH public key under **Settings -> SSH / GPG Keys**.

---

## 4. Client SSH Setup & Verification (`cloudflared access ssh`)

Install `cloudflared` on each client machine that pushes/pulls via SSH, then add the following to `~/.ssh/config`:

```sshconfig
Host git-ssh.francvok.from.hr
  User git
  ProxyCommand cloudflared access ssh --hostname %h
```

*(If your SSH client cannot find `cloudflared` on its default `$PATH`, replace `cloudflared` with the full path from `which cloudflared`.)*

Test the SSH handshake and clone a repository:

```bash
# Should greet you by Gitea username (interactive shell is disabled by design)
ssh -T git@git-ssh.francvok.from.hr

# Test cloning over SSH through the Cloudflare Tunnel
git clone git@git-ssh.francvok.from.hr:<user>/<repo>.git
```
