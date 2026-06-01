package manifest

import (
	"fmt"
	"os"
	"regexp"

	"gopkg.in/yaml.v3"
)

// validName matches Kubernetes DNS label rules: lowercase alphanumeric and hyphens,
// must start AND end with a letter or digit, ≤63 characters total.
var validName = regexp.MustCompile(`^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$`)

func Load(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading manifest: %w", err)
	}
	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parsing manifest: %w", err)
	}
	return &m, validate(&m)
}

func validate(m *Manifest) error {
	if m.Name == "" {
		return fmt.Errorf("name is required")
	}
	if !validName.MatchString(m.Name) {
		return fmt.Errorf("name %q is invalid: must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be ≤63 characters", m.Name)
	}
	if m.Environment == "" {
		return fmt.Errorf("environment is required (dev|stage|prod)")
	}
	if m.Image == "" {
		return fmt.Errorf("image is required")
	}
	if m.Service.Port == 0 {
		return fmt.Errorf("service.port is required")
	}
	if m.Service.Type != "public" && m.Service.Type != "private" {
		return fmt.Errorf("service.type must be 'public' or 'private', got %q", m.Service.Type)
	}
	if m.Replicas <= 0 {
		m.Replicas = 1
	}
	if m.Resources.CPU == "" {
		m.Resources.CPU = "250m"
	}
	if m.Resources.Memory == "" {
		m.Resources.Memory = "256Mi"
	}
	return nil
}
