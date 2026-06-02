// Package deployer translates a tl manifest into GKE/GCP resources.
// It shells out to gcloud and kubectl rather than embedding full SDK clients,
// keeping the binary small and auth straightforward (both tools are already
// configured in any environment where someone runs deploys).
package deployer

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"text/template"
	"time"

	"github.com/summiteight/t-labs/cli/pkg/manifest"
)

// Per-command timeout. Long enough for a regional cluster credential fetch
// or a kubectl rollout wait, short enough to not hang a CI job forever.
const cmdTimeout = 6 * time.Minute

type Config struct {
	ProjectID   string // GCP project ID for the environment
	Region      string // GCP region
	ClusterName string // GKE cluster name (default: <prefix>-<env>-gke)
}

type Deployer struct {
	cfg Config
	mf  *manifest.Manifest
	ctx context.Context
}

// New returns a Deployer bound to the supplied environment config and manifest.
// It also installs a SIGINT/SIGTERM handler so Ctrl-C cancels any in-flight
// kubectl/gcloud subprocess instead of leaving them as zombies.
func New(cfg Config, mf *manifest.Manifest) *Deployer {
	ctx, _ := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	return &Deployer{cfg: cfg, mf: mf, ctx: ctx}
}

// Deploy provisions GCP resources then applies Kubernetes manifests.
func (d *Deployer) Deploy() error {
	steps := []struct {
		name string
		fn   func() error
	}{
		{"configure kubectl context", d.configureKubeContext},
		{"create namespace", d.createNamespace},
		{"provision GCP service account", d.provisionGCPServiceAccount},
		{"fetch secrets", d.fetchAndCreateSecrets},
		{"apply Kubernetes manifests", d.applyKubernetesManifests},
		{"wait for rollout", d.waitForRollout},
	}

	for _, step := range steps {
		fmt.Printf("  → %s...\n", step.name)
		if err := step.fn(); err != nil {
			return fmt.Errorf("%s: %w", step.name, err)
		}
	}
	return nil
}

// Delete removes Kubernetes resources and optionally the GCP service account.
func (d *Deployer) Delete() error {
	// kubeContext must succeed — without it, kubectl operates against whatever cluster
	// happens to be active in the current kubeconfig, which could be the wrong environment.
	fmt.Printf("  → configure kubectl context...\n")
	if err := d.configureKubeContext(); err != nil {
		return fmt.Errorf("configure kubectl context: %w", err)
	}

	// Remaining steps are best-effort cleanup; warn but continue on failure.
	cleanupSteps := []struct {
		name string
		fn   func() error
	}{
		{"delete Kubernetes resources", d.deleteKubernetesResources},
		{"delete GCP service account", d.deleteGCPServiceAccount},
	}
	for _, step := range cleanupSteps {
		fmt.Printf("  → %s...\n", step.name)
		if err := step.fn(); err != nil {
			fmt.Printf("    warning: %v\n", err)
		}
	}
	return nil
}

func (d *Deployer) Status() error {
	if err := d.configureKubeContext(); err != nil {
		return err
	}
	ns := d.mf.Namespace()
	return d.run("kubectl", "get", "deployment,service,pods,pdb",
		"-n", ns, "-l", "app="+d.mf.Name)
}

// ── kubectl context ───────────────────────────────────────────────────────────

func (d *Deployer) configureKubeContext() error {
	cluster := d.cfg.ClusterName
	if cluster == "" {
		cluster = fmt.Sprintf("t-labs-%s-gke", d.mf.Environment)
	}
	return d.run("gcloud", "container", "clusters", "get-credentials",
		cluster, "--region", d.cfg.Region, "--project", d.cfg.ProjectID)
}

// ── namespace ─────────────────────────────────────────────────────────────────

func (d *Deployer) createNamespace() error {
	ns := d.mf.Namespace()
	// create only if it doesn't exist
	err := d.run("kubectl", "get", "namespace", ns)
	if err == nil {
		return nil
	}
	return d.run("kubectl", "create", "namespace", ns)
}

// ── GCP service account + Workload Identity ───────────────────────────────────

func (d *Deployer) provisionGCPServiceAccount() error {
	if !d.mf.NeedsGCPServiceAccount() {
		return nil
	}
	// GCP service account IDs must be 6-30 characters.
	if l := len(d.mf.Name); l < 6 || l > 30 {
		return fmt.Errorf("service name %q has %d characters; GCP service account IDs must be 6-30 characters", d.mf.Name, l)
	}
	gsaName := d.mf.Name
	gsaEmail := fmt.Sprintf("%s@%s.iam.gserviceaccount.com", gsaName, d.cfg.ProjectID)
	ns := d.mf.Namespace()

	// Create GCP SA (idempotent — ignore already-exists)
	_ = d.run("gcloud", "iam", "service-accounts", "create", gsaName,
		"--project", d.cfg.ProjectID,
		"--display-name", d.mf.Name+" deployer SA")

	// Grant requested IAM roles
	for _, role := range d.mf.IAM.Roles {
		if err := d.run("gcloud", "projects", "add-iam-policy-binding", d.cfg.ProjectID,
			"--member", "serviceAccount:"+gsaEmail,
			"--role", role,
			"--condition=None"); err != nil {
			return fmt.Errorf("granting role %s: %w", role, err)
		}
	}

	// Bind GCP SA to Kubernetes SA via Workload Identity
	ksaMember := fmt.Sprintf("serviceAccount:%s.svc.id.goog[%s/%s]",
		d.cfg.ProjectID, ns, d.mf.Name)
	if err := d.run("gcloud", "iam", "service-accounts", "add-iam-policy-binding", gsaEmail,
		"--project", d.cfg.ProjectID,
		"--role", "roles/iam.workloadIdentityUser",
		"--member", ksaMember); err != nil {
		return fmt.Errorf("workload identity binding: %w", err)
	}
	return nil
}

func (d *Deployer) deleteGCPServiceAccount() error {
	if !d.mf.NeedsGCPServiceAccount() {
		return nil
	}
	gsaEmail := fmt.Sprintf("%s@%s.iam.gserviceaccount.com", d.mf.Name, d.cfg.ProjectID)
	return d.run("gcloud", "iam", "service-accounts", "delete", gsaEmail,
		"--project", d.cfg.ProjectID, "--quiet")
}

// ── secrets ───────────────────────────────────────────────────────────────────

// fetchAndCreateSecrets pulls each referenced secret from Secret Manager and
// applies a Kubernetes Secret containing the values.
//
// Important: the secret values are NEVER passed as kubectl arguments. We
// template a Secret manifest in-process (base64 data) and pipe it to
// `kubectl apply` on stdin. Earlier versions used `--from-literal=KEY=VALUE`,
// which leaked values via /proc/<pid>/cmdline to any local user.
func (d *Deployer) fetchAndCreateSecrets() error {
	if len(d.mf.Secrets) == 0 {
		return nil
	}

	values := make(map[string]string, len(d.mf.Secrets))
	for _, s := range d.mf.Secrets {
		v, err := d.fetchSecretManagerValue(s.Secret)
		if err != nil {
			return fmt.Errorf("fetching secret %s: %w", s.Secret, err)
		}
		values[s.EnvVar] = v
	}

	yaml, err := renderSecretManifest(d.mf.Name+"-secrets", d.mf.Namespace(), d.mf.Name, values)
	if err != nil {
		return err
	}
	return d.kubectlApplyYAML(yaml)
}

func (d *Deployer) fetchSecretManagerValue(secretID string) (string, error) {
	out, err := d.output("gcloud", "secrets", "versions", "access", "latest",
		"--secret", secretID, "--project", d.cfg.ProjectID)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// renderSecretManifest produces a v1/Secret with base64-encoded values.
// Stays as a separate function so it's straightforward to unit-test without
// shelling out to anything.
func renderSecretManifest(name, namespace, appLabel string, values map[string]string) (string, error) {
	var buf bytes.Buffer
	fmt.Fprintf(&buf, "apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\n  labels:\n    app: %s\ntype: Opaque\ndata:\n",
		name, namespace, appLabel)
	// Iterate in a stable order so the rendered output is deterministic
	// (tests rely on this and apply diffs stay clean).
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sortStrings(keys)
	for _, k := range keys {
		enc := base64.StdEncoding.EncodeToString([]byte(values[k]))
		fmt.Fprintf(&buf, "  %s: %s\n", k, enc)
	}
	return buf.String(), nil
}

// sortStrings is a tiny inline sort so we don't pull in "sort" just for one call.
func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j-1] > s[j]; j-- {
			s[j-1], s[j] = s[j], s[j-1]
		}
	}
}

// ── Kubernetes manifests ──────────────────────────────────────────────────────

func (d *Deployer) applyKubernetesManifests() error {
	yaml, err := d.renderManifests()
	if err != nil {
		return err
	}
	return d.kubectlApplyYAML(yaml)
}

func (d *Deployer) deleteKubernetesResources() error {
	ns := d.mf.Namespace()
	// Delete by label selector — catches all resources created for this service
	_ = d.run("kubectl", "delete", "deployment", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = d.run("kubectl", "delete", "service", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = d.run("kubectl", "delete", "serviceaccount", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = d.run("kubectl", "delete", "pdb", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = d.run("kubectl", "delete", "secret", d.mf.Name+"-secrets", "-n", ns, "--ignore-not-found")
	return nil
}

func (d *Deployer) waitForRollout() error {
	return d.run("kubectl", "rollout", "status",
		"deployment/"+d.mf.Name, "-n", d.mf.Namespace(), "--timeout=5m")
}

// ── manifest rendering ────────────────────────────────────────────────────────

type templateData struct {
	*manifest.Manifest
	ProjectID  string
	HasSecrets bool
	HasGSA     bool
	WantPDB    bool
	PullPolicy string
}

func imagePullPolicy(image string) string {
	if strings.HasSuffix(image, ":latest") || !strings.Contains(image, ":") {
		return "Always"
	}
	return "IfNotPresent"
}

func (d *Deployer) renderManifests() (string, error) {
	data := templateData{
		Manifest:   d.mf,
		ProjectID:  d.cfg.ProjectID,
		HasSecrets: len(d.mf.Secrets) > 0,
		HasGSA:     d.mf.NeedsGCPServiceAccount(),
		WantPDB:    d.mf.Replicas > 1,
		PullPolicy: imagePullPolicy(d.mf.Image),
	}

	tmpl, err := template.New("manifests").Funcs(template.FuncMap{
		"sub1": func(n int) int { return n - 1 },
	}).Parse(manifestTemplate)
	if err != nil {
		return "", err
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// The template renders:
//   - ServiceAccount with WI annotation when iam.roles is set
//   - Deployment with restricted Pod Security defaults, liveness + readiness probes,
//     and zone-spread constraints when replicas > 1
//   - Service (type=LoadBalancer for `service.type: public`, ClusterIP otherwise)
//   - PodDisruptionBudget when replicas > 1
//
// Note: public services emit a vanilla Service type=LoadBalancer. For prod,
// front them with a Global HTTPS LB + Cloud Armor security policy; the
// Service-as-LoadBalancer path is intentionally only used in dev. README →
// Future Work tracks the Cloud Armor + managed cert wiring.
const manifestTemplate = `
{{- $ns := .Namespace -}}
{{- $name := .Name -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
{{- if .HasGSA }}
  annotations:
    iam.gke.io/gcp-service-account: {{ $name }}@{{ .ProjectID }}.iam.gserviceaccount.com
{{- end }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
spec:
  replicas: {{ .Replicas }}
  selector:
    matchLabels:
      app: {{ $name }}
  template:
    metadata:
      labels:
        app: {{ $name }}
    spec:
      serviceAccountName: {{ $name }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
{{- if gt .Replicas 1 }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: {{ $name }}
{{- end }}
      containers:
        - name: {{ $name }}
          image: {{ .Image }}
          imagePullPolicy: {{ .PullPolicy }}
          ports:
            - containerPort: {{ .Service.Port }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: {{ .Resources.CPU }}
              memory: {{ .Resources.Memory }}
            limits:
              cpu: {{ .Resources.CPU }}
              memory: {{ .Resources.Memory }}
          livenessProbe:
            httpGet:
              path: {{ .Health.Path }}
              port: {{ .Health.Port }}
            initialDelaySeconds: 10
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: {{ .Health.Path }}
              port: {{ .Health.Port }}
            initialDelaySeconds: 2
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
{{- if or .Env .HasSecrets }}
          env:
{{- range .Env }}
            - name: {{ .Name }}
              value: {{ printf "%q" .Value }}
{{- end }}
{{- range .Secrets }}
            - name: {{ .EnvVar }}
              valueFrom:
                secretKeyRef:
                  name: {{ $name }}-secrets
                  key: {{ .EnvVar }}
{{- end }}
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
spec:
  type: {{ .ServiceType }}
  selector:
    app: {{ $name }}
  ports:
    - port: {{ .Service.Port }}
      targetPort: {{ .Service.Port }}
      protocol: TCP
{{- if .WantPDB }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: {{ $name }}
{{- end }}
`

// ── helpers ───────────────────────────────────────────────────────────────────

// run executes a command with the deployer's cancellation context and a
// per-command timeout. Stdout/stderr are streamed to the user.
func (d *Deployer) run(name string, args ...string) error {
	ctx, cancel := context.WithTimeout(d.ctx, cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// output is the same as run but captures stdout into a string. Stderr still
// streams to the user so failures are visible.
func (d *Deployer) output(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(d.ctx, cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func (d *Deployer) kubectlApplyYAML(yaml string) error {
	ctx, cancel := context.WithTimeout(d.ctx, cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "kubectl", "apply", "-f", "-")
	cmd.Stdin = strings.NewReader(yaml)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
