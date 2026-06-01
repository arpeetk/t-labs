package manifest

// Manifest is the tl deployer manifest schema.
// Engineers fill this out; the deployer handles all Kubernetes and GCP details.
type Manifest struct {
	Name        string `yaml:"name"`
	Environment string `yaml:"environment"` // dev | stage | prod

	Image    string `yaml:"image"`
	Replicas int    `yaml:"replicas"`

	Resources Resources `yaml:"resources"`
	Service   Service   `yaml:"service"`

	Env     []EnvVar  `yaml:"env"`
	Secrets []SecretRef `yaml:"secrets"`
	IAM     IAMConfig   `yaml:"iam"`
}

type Resources struct {
	CPU    string `yaml:"cpu"`    // e.g. "500m"
	Memory string `yaml:"memory"` // e.g. "512Mi"
}

type Service struct {
	// Type is "public" (LoadBalancer with external IP) or "private" (ClusterIP, in-cluster only).
	Type string `yaml:"type"`
	Port int    `yaml:"port"`
}

type EnvVar struct {
	Name  string `yaml:"name"`
	Value string `yaml:"value"`
}

// SecretRef maps a Secret Manager secret to an env var in the container.
// The deployer fetches the secret value and creates a Kubernetes Secret.
type SecretRef struct {
	// EnvVar is the name of the env var injected into the container.
	EnvVar string `yaml:"envVar"`
	// Secret is the Secret Manager secret ID (without the full resource path).
	Secret string `yaml:"secret"`
}

type IAMConfig struct {
	// Roles are GCP IAM roles to grant to this service's Google Service Account.
	Roles []string `yaml:"roles"`
}

func (m *Manifest) Namespace() string {
	if m.Environment == "" {
		return "default"
	}
	return m.Environment
}

func (m *Manifest) GCPServiceAccountName(projectID string) string {
	return m.Name + "@" + projectID + ".iam.gserviceaccount.com"
}

func (m *Manifest) NeedsGCPServiceAccount() bool {
	return len(m.IAM.Roles) > 0
}

func (m *Manifest) ServiceType() string {
	if m.Service.Type == "public" {
		return "LoadBalancer"
	}
	return "ClusterIP"
}
