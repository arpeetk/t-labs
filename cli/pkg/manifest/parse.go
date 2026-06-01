package manifest

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

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
