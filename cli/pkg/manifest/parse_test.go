// Package manifest provides manifest parsing and validation.
package manifest

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeManifest(t *testing.T, content string) string {
	t.Helper()
	f := filepath.Join(t.TempDir(), "deploy.yaml")
	if err := os.WriteFile(f, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestLoad_FileNotFound(t *testing.T) {
	_, err := Load("/nonexistent/deploy.yaml")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestLoad_InvalidYAML(t *testing.T) {
	f := writeManifest(t, "name: [unclosed")
	_, err := Load(f)
	if err == nil {
		t.Fatal("expected error for invalid YAML")
	}
}

func TestLoad_Valid(t *testing.T) {
	f := writeManifest(t, `
name: my-service
environment: dev
image: us-central1-docker.pkg.dev/proj/repo/my-service:latest
service:
  type: public
  port: 8080
`)
	mf, err := Load(f)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if mf.Name != "my-service" {
		t.Errorf("name = %q, want %q", mf.Name, "my-service")
	}
	// defaults applied
	if mf.Replicas != 1 {
		t.Errorf("replicas = %d, want 1 (default)", mf.Replicas)
	}
	if mf.Resources.CPU != "250m" {
		t.Errorf("cpu = %q, want %q (default)", mf.Resources.CPU, "250m")
	}
	if mf.Resources.Memory != "256Mi" {
		t.Errorf("memory = %q, want %q (default)", mf.Resources.Memory, "256Mi")
	}
}

func TestLoad_ExplicitValues_NotOverriddenByDefaults(t *testing.T) {
	f := writeManifest(t, `
name: svc
environment: dev
image: img:latest
replicas: 3
resources:
  cpu: "500m"
  memory: "512Mi"
service:
  type: private
  port: 9090
`)
	mf, err := Load(f)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if mf.Replicas != 3 {
		t.Errorf("replicas = %d, want 3", mf.Replicas)
	}
	if mf.Resources.CPU != "500m" {
		t.Errorf("cpu = %q, want 500m", mf.Resources.CPU)
	}
	if mf.Resources.Memory != "512Mi" {
		t.Errorf("memory = %q, want 512Mi", mf.Resources.Memory)
	}
}

var validationCases = []struct {
	name    string
	yaml    string
	wantErr string
}{
	{
		name: "missing name",
		yaml: `environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "name is required",
	},
	{
		name: "missing environment",
		yaml: `name: svc
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "environment is required",
	},
	{
		name: "missing image",
		yaml: `name: svc
environment: dev
service: {type: public, port: 8080}`,
		wantErr: "image is required",
	},
	{
		name: "missing port",
		yaml: `name: svc
environment: dev
image: img:latest
service: {type: public, port: 0}`,
		wantErr: "service.port is required",
	},
	{
		name: "invalid service type",
		yaml: `name: svc
environment: dev
image: img:latest
service: {type: internal, port: 8080}`,
		wantErr: "service.type must be",
	},
	{
		name: "name with uppercase",
		yaml: `name: MyService
environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "invalid",
	},
	{
		name: "name with underscore",
		yaml: `name: my_service
environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "invalid",
	},
	{
		name: "name starts with digit",
		yaml: `name: 1svc
environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "invalid",
	},
	{
		name: "name with trailing hyphen",
		yaml: `name: my-svc-
environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "invalid",
	},
	{
		name: "name exactly 64 chars (one over limit)",
		yaml: "name: a234567890123456789012345678901234567890123456789012345678901234\nenvironment: dev\nimage: img:latest\nservice: {type: public, port: 8080}",
		wantErr: "invalid",
	},
	{
		name: "name exceeds 63 chars",
		yaml: `name: this-name-is-way-too-long-for-kubernetes-and-gcp-resource-naming-rules
environment: dev
image: img:latest
service: {type: public, port: 8080}`,
		wantErr: "invalid",
	},
}

func TestLoad_ValidationErrors(t *testing.T) {
	for _, tc := range validationCases {
		t.Run(tc.name, func(t *testing.T) {
			f := writeManifest(t, tc.yaml)
			_, err := Load(f)
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.wantErr)
			}
			if tc.wantErr != "" {
				if !strings.Contains(err.Error(), tc.wantErr) {
					t.Errorf("error = %q, want it to contain %q", err.Error(), tc.wantErr)
				}
			}
		})
	}
}

var validNameCases = []string{
	"svc",
	"my-service",
	"api-service-v2",
	"a",
	"hello-world",
	"svc123",
}

func TestLoad_ValidNames(t *testing.T) {
	for _, name := range validNameCases {
		t.Run(name, func(t *testing.T) {
			content := "name: " + name + "\nenvironment: dev\nimage: img:latest\nservice:\n  type: public\n  port: 8080\n"
			f := writeManifest(t, content)
			if _, err := Load(f); err != nil {
				t.Errorf("unexpected error for valid name %q: %v", name, err)
			}
		})
	}
}
