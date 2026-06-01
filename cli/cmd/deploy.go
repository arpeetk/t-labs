package cmd

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

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
			printLoadBalancerIP(mf.Name, mf.Namespace())
		}
		return nil
	},
}

// printLoadBalancerIP polls kubectl until the LoadBalancer IP is assigned (up to 2 minutes).
// kubectl get --watch never exits on its own, so we poll instead.
func printLoadBalancerIP(name, namespace string) {
	fmt.Print("Waiting for LoadBalancer IP")
	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		out, err := exec.Command("kubectl", "get", "service", name,
			"-n", namespace,
			"-o", "jsonpath={.status.loadBalancer.ingress[0].ip}").Output()
		if err == nil {
			ip := strings.TrimSpace(string(out))
			if ip != "" {
				fmt.Printf("\nLoadBalancer IP: %s\n", ip)
				return
			}
		}
		fmt.Print(".")
		time.Sleep(5 * time.Second)
	}
	fmt.Println("\nLoadBalancer IP not yet assigned — check with: kubectl get service", name, "-n", namespace)
}

func init() {
	rootCmd.AddCommand(deployCmd)
	deployCmd.Flags().StringVarP(&deployFile, "file", "f", "deploy.yaml", "path to the manifest file")
}
