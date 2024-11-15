
// Package cmd provides the root command for the application.
package cmd

import (
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	//"go.infratographer.com/x/loggingx"
	//"go.infratographer.com/x/viperx"
	//"go.uber.org/zap"

	"github.com/CloudSharp-Systems/CloudSharpCockroachDB/config"
)

var (
	appName = "cscockroach"
	rootCmd = &cobra.Command{
		Use:   "cscockroach",
		Short: "cloudsharp cockroach db migration commands",
	}

	cfgFile string
	//logger  *zap.SugaredLogger
)

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is /etc/config.yaml)")

	//rootCmd.PersistentFlags().String("audit-log-path", "/app-audit/audit.log", "file path to write audit logs")
	//viperx.MustBindFlag(viper.GetViper(), "audit.log.path", rootCmd.PersistentFlags().Lookup("audit-log-path"))
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} // else {
	//	viper.AddConfigPath("/etc/config")
	//	viper.SetConfigType("yaml")
	//	viper.SetConfigName("config")
	//}

	// Allow populating configuration from environment
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.SetEnvPrefix("idapi")
	viper.AutomaticEnv() // read in environment variables that match

	err := viper.ReadInConfig()

	// logger = loggingx.InitLogger(appName, config.Config.Logging)
	/*
	if err == nil {
		logger.Infow("using config file",
			"file", viper.ConfigFileUsed(),
		)
	}
	*/
	err = viper.Unmarshal(&config.Config)
	if err != nil {
		panic(err)
		//logger.Fatalw("unable to decode app config", "error", err)
	}
}

// Execute executes the root command.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}
