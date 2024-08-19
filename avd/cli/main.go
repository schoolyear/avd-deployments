package main

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"github.com/go-ozzo/ozzo-validation/v4"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/commands"
	"github.com/urfave/cli/v2"
	"os"
	"time"
)

func main() {
	app := &cli.App{
		Name:    "avdcli",
		Usage:   "managed you AVD deployment",
		Version: "1.87.1",
		Suggest: true,
		Commands: cli.Commands{
			{
				Name:  "image",
				Usage: "manage images",
				Subcommands: cli.Commands{
					commands.ImageNewCommand,
					commands.ImageMergeCommand,
				},
			},
		},
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "deployment",
				Value:   "prod",
				Usage:   "Schoolyear deployment: dev/testing/beta/prod",
				Aliases: []string{"d"},
				Action: func(ctx *cli.Context, value string) error {
					return errors.Wrap(validation.Validate(value, validation.Required, validation.In("dev", "testing", "beta", "prod")), "invalid deployment flag")
				},
			},
		},
		EnableBashCompletion: true,
		Compiled:             time.Time{},
		Authors: []*cli.Author{
			{
				Name:  "Schoolyear",
				Email: "support@schoolyear.com",
			},
		},
		Copyright: "Schoolyear",
	}

	if err := app.Run(os.Args); err != nil {
		fmt.Println("Error:", err.Error())
		os.Exit(1)
	}
}
