package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "tld",
	Short: "t-labs deployer — deploy services to GKE from a manifest",
	Long: `tld deploys containerized services to the t-labs GKE infrastructure.

Engineers write a deploy.yaml that specifies what a service needs (image,
resources, public/private, secrets, IAM roles) and tld handles the rest:
Kubernetes Deployment + Service + ServiceAccount, GCP IAM, Secret Manager.

Example:
  tld deploy -f deploy.yaml
  tld status -f deploy.yaml
  tld delete -f deploy.yaml`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
