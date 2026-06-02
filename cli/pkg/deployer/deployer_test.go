package deployer

import (
	"strings"
	"testing"

	"github.com/summiteight/t-labs/cli/pkg/manifest"
	"gopkg.in/yaml.v3"
)

func baseMF() *manifest.Manifest {
	return &manifest.Manifest{
		Name:        "my-svc",
		Environment: "dev",
		Image:       "us-central1-docker.pkg.dev/proj/repo/my-svc:latest",
		Replicas:    2,
		Resources:   manifest.Resources{CPU: "250m", Memory: "256Mi"},
		Service:     manifest.Service{Type: "public", Port: 8080},
		Health:      manifest.Health{Path: "/health", Port: 8080},
	}
}

func render(t *testing.T, mf *manifest.Manifest, projectID string) string {
	t.Helper()
	d := New(Config{ProjectID: projectID, Region: "us-central1"}, mf)
	out, err := d.renderManifests()
	if err != nil {
		t.Fatalf("renderManifests: %v", err)
	}
	return out
}

// parseYAMLDocs splits a multi-document YAML string and unmarshals each into a map.
func parseYAMLDocs(t *testing.T, s string) []map[string]interface{} {
	t.Helper()
	var docs []map[string]interface{}
	for _, chunk := range strings.Split(s, "\n---") {
		chunk = strings.TrimSpace(chunk)
		if chunk == "" {
			continue
		}
		var doc map[string]interface{}
		if err := yaml.Unmarshal([]byte(chunk), &doc); err != nil {
			t.Fatalf("YAML parse error: %v\n---\n%s", err, chunk)
		}
		if doc != nil {
			docs = append(docs, doc)
		}
	}
	return docs
}

func kindDoc(docs []map[string]interface{}, kind string) map[string]interface{} {
	for _, d := range docs {
		if d["kind"] == kind {
			return d
		}
	}
	return nil
}

func TestRenderManifests_Basic(t *testing.T) {
	out := render(t, baseMF(), "my-project")

	docs := parseYAMLDocs(t, out)
	// SA + Deployment + Service + PDB (PDB present because replicas > 1).
	if len(docs) != 4 {
		t.Fatalf("expected 4 YAML documents (ServiceAccount, Deployment, Service, PDB), got %d", len(docs))
	}

	sa := kindDoc(docs, "ServiceAccount")
	if sa == nil {
		t.Fatal("missing ServiceAccount document")
	}
	meta := sa["metadata"].(map[string]interface{})
	if meta["name"] != "my-svc" {
		t.Errorf("ServiceAccount name = %v, want my-svc", meta["name"])
	}
	if meta["namespace"] != "dev" {
		t.Errorf("ServiceAccount namespace = %v, want dev", meta["namespace"])
	}

	dep := kindDoc(docs, "Deployment")
	if dep == nil {
		t.Fatal("missing Deployment document")
	}
	spec := dep["spec"].(map[string]interface{})
	if spec["replicas"] != 2 {
		t.Errorf("replicas = %v, want 2", spec["replicas"])
	}

	svc := kindDoc(docs, "Service")
	if svc == nil {
		t.Fatal("missing Service document")
	}
	svcSpec := svc["spec"].(map[string]interface{})
	if svcSpec["type"] != "LoadBalancer" {
		t.Errorf("service type = %v, want LoadBalancer", svcSpec["type"])
	}
}

func TestRenderManifests_PrivateService(t *testing.T) {
	mf := baseMF()
	mf.Service.Type = "private"
	out := render(t, mf, "my-project")

	docs := parseYAMLDocs(t, out)
	svc := kindDoc(docs, "Service")
	svcSpec := svc["spec"].(map[string]interface{})
	if svcSpec["type"] != "ClusterIP" {
		t.Errorf("service type = %v, want ClusterIP", svcSpec["type"])
	}
}

func TestRenderManifests_WithGSA(t *testing.T) {
	mf := baseMF()
	mf.IAM = manifest.IAMConfig{Roles: []string{"roles/secretmanager.secretAccessor"}}
	out := render(t, mf, "my-project")

	docs := parseYAMLDocs(t, out)
	sa := kindDoc(docs, "ServiceAccount")
	meta := sa["metadata"].(map[string]interface{})
	annotations, ok := meta["annotations"].(map[string]interface{})
	if !ok {
		t.Fatal("ServiceAccount has no annotations but GSA was expected")
	}
	wantAnnotation := "my-svc@my-project.iam.gserviceaccount.com"
	if annotations["iam.gke.io/gcp-service-account"] != wantAnnotation {
		t.Errorf("GSA annotation = %v, want %v", annotations["iam.gke.io/gcp-service-account"], wantAnnotation)
	}
}

func TestRenderManifests_NoGSA(t *testing.T) {
	out := render(t, baseMF(), "my-project") // no IAM roles

	docs := parseYAMLDocs(t, out)
	sa := kindDoc(docs, "ServiceAccount")
	meta := sa["metadata"].(map[string]interface{})
	if _, hasAnnotations := meta["annotations"]; hasAnnotations {
		t.Error("ServiceAccount should have no annotations when no GCP SA is needed")
	}
}

func TestRenderManifests_WithEnvVars(t *testing.T) {
	mf := baseMF()
	mf.Env = []manifest.EnvVar{
		{Name: "FOO", Value: "bar"},
		{Name: "PORT", Value: "8080"},
	}
	out := render(t, mf, "my-project")

	if !strings.Contains(out, "FOO") {
		t.Error("rendered YAML missing env var FOO")
	}
	if !strings.Contains(out, `"bar"`) {
		t.Error("rendered YAML missing env var value bar")
	}
}

func TestRenderManifests_WithSecrets(t *testing.T) {
	mf := baseMF()
	mf.Secrets = []manifest.SecretRef{
		{EnvVar: "DB_PASSWORD", Secret: "my-db-secret"},
	}
	out := render(t, mf, "my-project")

	if !strings.Contains(out, "DB_PASSWORD") {
		t.Error("rendered YAML missing secret env var DB_PASSWORD")
	}
	if !strings.Contains(out, "secretKeyRef") {
		t.Error("rendered YAML missing secretKeyRef")
	}
	if !strings.Contains(out, "my-svc-secrets") {
		t.Error("rendered YAML missing k8s Secret name my-svc-secrets")
	}
}

func TestRenderManifests_NoProxySidecar(t *testing.T) {
	// Cloud SQL proxy has been removed — the template must never emit it.
	out := render(t, baseMF(), "my-project")
	if strings.Contains(out, "cloud-sql-proxy") {
		t.Error("rendered YAML must not contain cloud-sql-proxy sidecar")
	}
}

func TestRenderManifests_ResourceLimits(t *testing.T) {
	mf := baseMF()
	mf.Resources = manifest.Resources{CPU: "500m", Memory: "512Mi"}
	out := render(t, mf, "my-project")

	if !strings.Contains(out, "500m") {
		t.Error("rendered YAML missing cpu 500m")
	}
	if !strings.Contains(out, "512Mi") {
		t.Error("rendered YAML missing memory 512Mi")
	}
}

func TestRenderManifests_ValidYAML(t *testing.T) {
	// Fully loaded manifest — verify the whole output is parseable YAML.
	mf := baseMF()
	mf.IAM = manifest.IAMConfig{Roles: []string{"roles/secretmanager.secretAccessor"}}
	mf.Env = []manifest.EnvVar{{Name: "ENV", Value: "dev"}}
	mf.Secrets = []manifest.SecretRef{{EnvVar: "SECRET_KEY", Secret: "my-secret"}}
	out := render(t, mf, "my-project")

	docs := parseYAMLDocs(t, out)
	if len(docs) != 4 {
		t.Errorf("expected 4 docs, got %d", len(docs))
	}
}

func TestRenderManifests_NoPDBForSingleReplica(t *testing.T) {
	mf := baseMF()
	mf.Replicas = 1
	out := render(t, mf, "my-project")

	docs := parseYAMLDocs(t, out)
	if len(docs) != 3 {
		t.Fatalf("expected 3 docs (SA, Deployment, Service) without PDB, got %d", len(docs))
	}
	for _, doc := range docs {
		if doc["kind"] == "PodDisruptionBudget" {
			t.Error("PDB should not be emitted when replicas == 1")
		}
	}
}

func TestRenderManifests_PodSecurityDefaults(t *testing.T) {
	out := render(t, baseMF(), "my-project")
	// Every public service must run as non-root with seccomp + dropped caps,
	// or the cluster's restricted PodSecurity admission will reject it.
	wantSubstrings := []string{
		"runAsNonRoot: true",
		"readOnlyRootFilesystem: true",
		"allowPrivilegeEscalation: false",
		`drop: ["ALL"]`,
		"seccompProfile",
		"topologySpreadConstraints",
		"livenessProbe",
		"readinessProbe",
	}
	for _, want := range wantSubstrings {
		if !strings.Contains(out, want) {
			t.Errorf("rendered YAML missing %q", want)
		}
	}
}

func TestRenderSecretManifest_Base64AndStableOrder(t *testing.T) {
	yaml1, err := renderSecretManifest("svc-secrets", "dev", "svc", map[string]string{
		"DB_PASSWORD": "p4ssw0rd!",
		"API_KEY":     "abc123",
	})
	if err != nil {
		t.Fatal(err)
	}
	yaml2, _ := renderSecretManifest("svc-secrets", "dev", "svc", map[string]string{
		"API_KEY":     "abc123",
		"DB_PASSWORD": "p4ssw0rd!",
	})
	if yaml1 != yaml2 {
		t.Errorf("renderSecretManifest output is not deterministic across input map orderings")
	}
	// Raw values must not appear in the rendered manifest — they should be base64-encoded.
	if strings.Contains(yaml1, "p4ssw0rd!") {
		t.Error("secret value appears un-encoded in rendered manifest")
	}
	if strings.Contains(yaml1, "abc123") {
		t.Error("secret value appears un-encoded in rendered manifest")
	}
	// And the encoded form must be present.
	if !strings.Contains(yaml1, "cDRzc3cwcmQh") {
		t.Error("expected base64-encoded DB_PASSWORD value missing from rendered manifest")
	}
}
