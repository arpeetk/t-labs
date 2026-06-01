package cmd

import (
	"github.com/spf13/cobra"
	"github.com/summiteight/t-labs/cli/pkg/deployer"
	"github.com/summiteight/t-labs/cli/pkg/manifest"
)

var statusFile string

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show the status of a deployed service",
	RunE: func(cmd *cobra.Command, args []string) error {
		mf, err := manifest.Load(statusFile)
		if err != nil {
			return err
		}
		cfg, err := envConfig(mf.Environment)
		if err != nil {
			return err
		}
		return deployer.New(cfg, mf).Status()
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
	statusCmd.Flags().StringVarP(&statusFile, "file", "f", "deploy.yaml", "path to the manifest file")
}
