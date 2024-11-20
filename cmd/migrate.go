package cmd

import (
	"context"
	"fmt"
	"sync"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"go.infratographer.com/x/crdbx"
	"database/sql"

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
		action := "up"
		if 0 < len(args) {
			action = args[0]
		}
		migrate(cmd.Context(), action)
	},
}

func migrateUp(db *sql.DB) error {
	err := goose.Up(db, "migrations")
	return err
}

func migrateDown(db *sql.DB) error {
        err := goose.Down(db, "migrations")
        return err
}

func migrate(_ context.Context, action string) {
	fmt.Println("running database migrations")

	if action != "up" && action != "down" {
		fmt.Printf("invalid migration command: %s", action)
                return
	}

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
	if action == "down" {
		err = migrateDown(db)
	} else {
		err = migrateUp(db)
	}

	if err != nil {
		fmt.Printf("error running migrations: %s\n", err)
		return
	}

	fmt.Println("success")
}
