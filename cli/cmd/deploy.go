package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/summiteight/t-labs/cli/pkg/deployer"
	"github.com/summiteight/t-labs/cli/pkg/manifest"
)

var deployFile string

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy a service from a manifest file",
	Example: `  tld deploy -f deploy.yaml
  tld deploy -f ./my-service/deploy.yaml`,
	RunE: func(cmd *cobra.Command, args []string) error {
		mf, err := manifest.Load(deployFile)
		if err != nil {
			return fmt.Errorf("loading manifest: %w", err)
		}

		cfg, err := envConfig(mf.Environment)
		if err != nil {
			return err
		}

		fmt.Printf("Deploying %q to %s (%s)\n", mf.Name, mf.Environment, cfg.ProjectID)
		d := deployer.New(cfg, mf)
		if err := d.Deploy(); err != nil {
			return fmt.Errorf("deploy: %w", err)
		}
		fmt.Printf("\nDone. Service %q deployed to namespace %q.\n", mf.Name, mf.Namespace())

		if mf.Service.Type == "public" {
			fmt.Println("Waiting for LoadBalancer IP...")
			_ = runKubectl("get", "service", mf.Name, "-n", mf.Namespace(),
				"--watch", "--output-watch-events",
				"-o", "jsonpath={.status.loadBalancer.ingress[0].ip}")
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployCmd.Flags().StringVarP(&deployFile, "file", "f", "deploy.yaml", "path to the manifest file")
}
