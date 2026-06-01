package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/summiteight/t-labs/cli/pkg/deployer"
	"github.com/summiteight/t-labs/cli/pkg/manifest"
)

var deleteFile string

var deleteCmd = &cobra.Command{
	Use:   "delete",
	Short: "Remove a deployed service",
	RunE: func(cmd *cobra.Command, args []string) error {
		mf, err := manifest.Load(deleteFile)
		if err != nil {
			return err
		}
		cfg, err := envConfig(mf.Environment)
		if err != nil {
			return err
		}
		fmt.Printf("Deleting %q from %s\n", mf.Name, mf.Environment)
		return deployer.New(cfg, mf).Delete()
	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)
	deleteCmd.Flags().StringVarP(&deleteFile, "file", "f", "deploy.yaml", "path to the manifest file")
}
