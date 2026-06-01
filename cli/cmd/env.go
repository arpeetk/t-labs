package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/summiteight/t-labs/cli/pkg/deployer"
)

// envConfig returns deployer config for a named environment.
// Project IDs are read from environment variables so the CLI works without
// any config file — CI/CD sets them; developers set them locally.
//
// Override any value:
//
//	TLD_DEV_PROJECT=my-project tld deploy -f deploy.yaml
func envConfig(env string) (deployer.Config, error) {
	type envDef struct {
		projectVar string
		region     string
	}

	defs := map[string]envDef{
		"dev":   {"TLD_DEV_PROJECT", "us-central1"},
		"stage": {"TLD_STAGE_PROJECT", "us-east4"},
		"prod":  {"TLD_PROD_PROJECT", "us-west1"},
	}

	def, ok := defs[env]
	if !ok {
		return deployer.Config{}, fmt.Errorf("unknown environment %q; must be dev, stage, or prod", env)
	}

	projectID := os.Getenv(def.projectVar)
	if projectID == "" {
		// Fall back to reading from gcloud config / terraform output
		projectID = lookupProjectID(env)
	}
	if projectID == "" {
		return deployer.Config{}, fmt.Errorf(
			"project ID for %s not set; export %s=<project-id>", env, def.projectVar)
	}

	region := os.Getenv("TLD_REGION")
	if region == "" {
		region = def.region
	}

	return deployer.Config{
		ProjectID:   projectID,
		Region:      region,
		ClusterName: fmt.Sprintf("t-labs-%s-gke", env),
	}, nil
}

// lookupProjectID tries to infer the project ID from gcloud.
func lookupProjectID(env string) string {
	// Try the convention: t-labs-<env>-2 (or t-labs-<env>)
	candidates := []string{
		"t-labs-" + env + "-2",
		"t-labs-" + env,
	}
	for _, candidate := range candidates {
		cmd := exec.Command("gcloud", "projects", "describe", candidate,
			"--format=value(projectId)")
		out, err := cmd.Output()
		if err == nil && strings.TrimSpace(string(out)) != "" {
			return strings.TrimSpace(string(out))
		}
	}
	return ""
}

func runKubectl(args ...string) error {
	cmd := exec.Command("kubectl", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
