// Package deployer translates a tl manifest into GKE/GCP resources.
// It shells out to gcloud and kubectl rather than embedding full SDK clients,
// keeping the binary small and auth straightforward (both tools are already
// configured in any environment where someone runs deploys).
package deployer

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"text/template"

	"github.com/summiteight/t-labs/cli/pkg/manifest"
)

type Config struct {
	ProjectID  string // GCP project ID for the environment
	Region     string // GCP region
	ClusterName string // GKE cluster name (default: <prefix>-<env>-gke)
}

type Deployer struct {
	cfg Config
	mf  *manifest.Manifest
}

func New(cfg Config, mf *manifest.Manifest) *Deployer {
	return &Deployer{cfg: cfg, mf: mf}
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
	steps := []struct {
		name string
		fn   func() error
	}{
		{"configure kubectl context", d.configureKubeContext},
		{"delete Kubernetes resources", d.deleteKubernetesResources},
		{"delete GCP service account", d.deleteGCPServiceAccount},
	}
	for _, step := range steps {
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
	return run("kubectl", "get", "deployment,service,pods",
		"-n", ns, "-l", "app="+d.mf.Name)
}

// ── kubectl context ───────────────────────────────────────────────────────────

func (d *Deployer) configureKubeContext() error {
	cluster := d.cfg.ClusterName
	if cluster == "" {
		cluster = fmt.Sprintf("t-labs-%s-gke", d.mf.Environment)
	}
	return run("gcloud", "container", "clusters", "get-credentials",
		cluster, "--region", d.cfg.Region, "--project", d.cfg.ProjectID)
}

// ── namespace ─────────────────────────────────────────────────────────────────

func (d *Deployer) createNamespace() error {
	ns := d.mf.Namespace()
	// create only if it doesn't exist
	err := run("kubectl", "get", "namespace", ns)
	if err == nil {
		return nil
	}
	return run("kubectl", "create", "namespace", ns)
}

// ── GCP service account + Workload Identity ───────────────────────────────────

func (d *Deployer) provisionGCPServiceAccount() error {
	if !d.mf.NeedsGCPServiceAccount() {
		return nil
	}
	gsaName := d.mf.Name
	gsaEmail := fmt.Sprintf("%s@%s.iam.gserviceaccount.com", gsaName, d.cfg.ProjectID)
	ns := d.mf.Namespace()

	// Create GCP SA (idempotent — ignore already-exists)
	_ = run("gcloud", "iam", "service-accounts", "create", gsaName,
		"--project", d.cfg.ProjectID,
		"--display-name", d.mf.Name+" deployer SA")

	// Grant requested IAM roles
	for _, role := range d.mf.IAM.Roles {
		if err := run("gcloud", "projects", "add-iam-policy-binding", d.cfg.ProjectID,
			"--member", "serviceAccount:"+gsaEmail,
			"--role", role,
			"--condition=None"); err != nil {
			return fmt.Errorf("granting role %s: %w", role, err)
		}
	}

	// Bind GCP SA to Kubernetes SA via Workload Identity
	ksaMember := fmt.Sprintf("serviceAccount:%s.svc.id.goog[%s/%s]",
		d.cfg.ProjectID, ns, d.mf.Name)
	if err := run("gcloud", "iam", "service-accounts", "add-iam-policy-binding", gsaEmail,
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
	return run("gcloud", "iam", "service-accounts", "delete", gsaEmail,
		"--project", d.cfg.ProjectID, "--quiet")
}

// ── secrets ───────────────────────────────────────────────────────────────────

// fetchAndCreateSecrets pulls each secret from Secret Manager and stores it
// in a Kubernetes Secret so the container sees it as an env var.
func (d *Deployer) fetchAndCreateSecrets() error {
	if len(d.mf.Secrets) == 0 {
		return nil
	}
	ns := d.mf.Namespace()
	secretName := d.mf.Name + "-secrets"

	// Build the --from-literal flags
	args := []string{
		"create", "secret", "generic", secretName,
		"-n", ns,
		"--save-config",
		"--dry-run=client",
		"-o", "yaml",
	}
	for _, s := range d.mf.Secrets {
		val, err := fetchSecretManagerValue(s.Secret, d.cfg.ProjectID)
		if err != nil {
			return fmt.Errorf("fetching secret %s: %w", s.Secret, err)
		}
		args = append(args, fmt.Sprintf("--from-literal=%s=%s", s.EnvVar, val))
	}

	out, err := output("kubectl", args...)
	if err != nil {
		return err
	}
	return kubectlApplyYAML(out)
}

func fetchSecretManagerValue(secretID, projectID string) (string, error) {
	out, err := output("gcloud", "secrets", "versions", "access", "latest",
		"--secret", secretID, "--project", projectID)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// ── Kubernetes manifests ──────────────────────────────────────────────────────

func (d *Deployer) applyKubernetesManifests() error {
	yaml, err := d.renderManifests()
	if err != nil {
		return err
	}
	return kubectlApplyYAML(yaml)
}

func (d *Deployer) deleteKubernetesResources() error {
	ns := d.mf.Namespace()
	// Delete by label selector — catches all resources created for this service
	_ = run("kubectl", "delete", "deployment", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = run("kubectl", "delete", "service", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = run("kubectl", "delete", "serviceaccount", d.mf.Name, "-n", ns, "--ignore-not-found")
	_ = run("kubectl", "delete", "secret", d.mf.Name+"-secrets", "-n", ns, "--ignore-not-found")
	return nil
}

func (d *Deployer) waitForRollout() error {
	return run("kubectl", "rollout", "status",
		"deployment/"+d.mf.Name, "-n", d.mf.Namespace(), "--timeout=5m")
}

// ── manifest rendering ────────────────────────────────────────────────────────

type templateData struct {
	*manifest.Manifest
	ProjectID  string
	HasSecrets bool
	HasGSA     bool
}

func (d *Deployer) renderManifests() (string, error) {
	data := templateData{
		Manifest:   d.mf,
		ProjectID:  d.cfg.ProjectID,
		HasSecrets: len(d.mf.Secrets) > 0,
		HasGSA:     d.mf.NeedsGCPServiceAccount(),
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
      containers:
        - name: {{ $name }}
          image: {{ .Image }}
          ports:
            - containerPort: {{ .Service.Port }}
          resources:
            requests:
              cpu: {{ .Resources.CPU }}
              memory: {{ .Resources.Memory }}
            limits:
              cpu: {{ .Resources.CPU }}
              memory: {{ .Resources.Memory }}
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
{{- if .NeedsCloudSQL }}
        - name: cloud-sql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2
          args:
            - "--structured-logs"
            - "--port=5432"
            - "{{ .Connect.CloudSQL }}"
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
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
`

// ── helpers ───────────────────────────────────────────────────────────────────

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func output(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func kubectlApplyYAML(yaml string) error {
	cmd := exec.Command("kubectl", "apply", "-f", "-")
	cmd.Stdin = strings.NewReader(yaml)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
