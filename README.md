# Docker Compose to K3s Migration Template

A quick-reference workflow for converting `docker-compose.yml` stacks into K3s Kubernetes manifests.

---

## 1. Concept Mapping Cheat Sheet

| Docker Compose | Kubernetes (K3s) Equivalent | When to Use |
| :--- | :--- | :--- |
| Project name | **`Namespace`** | Always create 1 namespace per stack to isolate resources. |
| `.env` variables (passwords/keys) | **`Secret`** (applied via `envsubst`) | Passwords, API tokens, DB credentials. Never commit raw values. |
| Config files (`./seed:/init.d`) | **`ConfigMap`** | Read-only config files, init scripts, or non-sensitive env vars. |
| Named volume / `./data:/path` | **`PersistentVolumeClaim` (PVC)** | Stateful data (`local-path` for single-node; `longhorn`/NFS for multi-node). |
| `services.<name>` (container) | **`Deployment`** | Runs the container image, env vars, health probes, and volume mounts. |
| Internal Docker DNS (`db:3306`) | **`Service`** (`ClusterIP`) | Gives Pods a permanent internal DNS name (`<svc-name>:<port>`). |
| `ports: ["8080:80"]` / Caddy | **`Ingress`** (Traefik) | Routes public domains (`Host: app.domain.com`) to an internal `Service`. |
| `healthcheck:` | **`startupProbe` / `readinessProbe` / `livenessProbe`** | Replaces `depends_on: condition: service_healthy`. |
| Scaling (`--scale`) | **`HorizontalPodAutoscaler` (HPA)** | Auto-scales stateless web apps based on CPU/RAM (requires `resources.requests`). |

---

## 2. Standard Directory & 3-Phase Numbering Rule

All stacks follow a strict numeric convention so the generic `deploy.sh` script can deploy any stack without modification:

1. **`00` – `09` (Pre-Environment):** Applied directly before secrets (e.g., `00-namespace.yaml`).
2. **`10-environment.yaml` (Environment Seeding):** Automatically populated from `.env` in-memory via `envsubst` and piped into `kubectl apply`.
3. **`11` – `99` (Application Resources):** Applied in numerical order after secrets exist (`20-mysql.yaml`, `30-wordpress-kupa.yaml`, etc.).

```text
k3s/<stack-name>/
├── .gitignore                   # Ignores .env
├── .env                         # Local secret values (not committed to Git)
├── deploy.sh                    # Reusable 3-phase deployment script
├── 00-namespace.yaml            # Phase 1 (<10): Stack namespace
├── 10-environment.yaml          # Phase 2 (10): Secret template with ${VAR} placeholders
├── 20-<database>.yaml           # Phase 3 (>10): ConfigMap + PVC + Deployment + Service
└── 30-<webapp>.yaml             # Phase 3 (>10): PVC + Deployment + Service + Ingress (+ HPA)
```

---

## 3. Step-by-Step Migration Checklist

1. **Create Namespace (`00-namespace.yaml`):**
   - Put `namespace: <stack-name>` in the `metadata` of every resource in the stack.
2. **Extract Secrets (`10-environment.yaml`):**
   - Move all `${...}` variables from `docker-compose.yml` into a `Secret` under `stringData:`.
   - Reference them in Deployments using `valueFrom.secretKeyRef`.
3. **Convert Volumes (`20+`):**
   - **Small config/seed files** -> Put file contents inside a `ConfigMap` and mount it.
   - **Persistent data folders** -> Create a `PersistentVolumeClaim` (`storageClassName: local-path`) and mount it.
4. **Convert Containers to `Deployment` + `Service` (`20+`):**
   - Every container that other containers talk to needs a `Service`.
   - Use `strategy: Recreate` for single-instance databases, and `strategy: RollingUpdate` for web apps.
5. **Expose Public Web Apps via `Ingress` (`30+`):**
   - Remove host `ports: ["8181:80"]`.
   - Add an `Ingress` rule matching `host: sub.yourdomain.com` pointing to the web app's `Service` on port `80`.
   - Point your Cloudflare Tunnel to `http://<K3S-NODE-IP>:80` (Traefik).
6. **Add Auto-Scaling (Optional, Stateless Apps Only):**
   - Add `resources.requests.cpu` to the Deployment.
   - Add a `HorizontalPodAutoscaler` (`minReplicas` / `maxReplicas` / target CPU `%`).

---

## 4. Standard Deployment & Debugging Commands

```bash
# 1. Deploy the entire stack (runs <10, seeds 10-environment.yaml with .env, then runs >10)
./k3s/deploy.sh

# (Or pass another stack folder to the same script)
./k3s/deploy.sh /path/to/another-stack

# 2. Check status of everything in the namespace
sudo k3s kubectl get pods,pvc,svc,ingress,hpa -n wordpress

# 3. View logs or debug a crashing pod
sudo k3s kubectl logs -n wordpress deploy/wordpress-kupa -f
sudo k3s kubectl describe pod -n wordpress -l app=wordpress-kupa

# 4. Access an internal database locally (replaces phpMyAdmin)
sudo k3s kubectl port-forward -n wordpress svc/db 3306:3306
```
