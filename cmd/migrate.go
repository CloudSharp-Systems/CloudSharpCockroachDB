package cmd

import (
	"context"
	"fmt"
	"sync"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"go.infratographer.com/x/crdbx"

	"github.com/pressly/goose/v3"
	"github.com/CloudSharp-Systems/CloudSharpCockroachDB/config"
)


var migrationMutex sync.Mutex


func init() {
	rootCmd.AddCommand(migrateCmd)

	v := viper.GetViper()
	flags := migrateCmd.Flags()

	crdbx.MustViperFlags(v, flags)

}

var migrateCmd = &cobra.Command{
	Use:   "migrate",
	Short: "runs cloudsharp cockroach database migrations",
	Run: func(cmd *cobra.Command, args []string) {
		migrate(cmd.Context())
	},
}

func migrate(_ context.Context) {
	fmt.Println("running database migrations")

	db, err := crdbx.NewDB(config.Config.CRDB, false)
	if err != nil {
		fmt.Printf("error at initial connection to db: %s", err)
		return
	}
	defer db.Close()

	if err = goose.SetDialect("postgres"); err != nil {
		fmt.Printf("error at db dialect setting: %s", err)
		return
	}

	migrationMutex.Lock()
	defer migrationMutex.Unlock()
	if err = goose.Up(db, "migrations"); err != nil {
		fmt.Printf("error running migrations: %s\n", err)
		return
	}

	fmt.Println("success")
}
