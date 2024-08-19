package commands

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/embeddedfiles"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
	"github.com/urfave/cli/v2"
	"io/fs"
	"os"
	"path/filepath"
)

var ImageNewCommand = &cli.Command{
	Name:  "new",
	Usage: "create a new image folder structure",
	Flags: []cli.Flag{
		&cli.PathFlag{
			Name:    "output",
			Value:   "./",
			Usage:   "Path in which the new image folder should be created",
			Aliases: []string{"o"},
		},
	},
	Action: func(c *cli.Context) error {
		targetPath := c.Path("output")

		if err := lib.EnsureEmptyDirectory(targetPath); err != nil {
			return errors.Wrap(err, "failed to create target directory")
		}

		absTargetPath, err := filepath.Abs(targetPath)
		if err != nil {
			return errors.Wrapf(err, "failed to convert target path to absolute path")
		}

		if err := copyDirectory(embeddedfiles.ImageTemplate, embeddedfiles.ImageTemplateBasePath, targetPath); err != nil {
			return errors.Wrap(err, "failed to copy image template directory")
		}

		fmt.Println("created new image folder at", absTargetPath)

		return nil
	},
}

func copyDirectory(sourceFs fs.FS, sourceBasePath string, targetBasePath string) error {
	defer func() {
		fmt.Println("")
	}()
	return fs.WalkDir(sourceFs, sourceBasePath, func(sourcePath string, d fs.DirEntry, err error) error {
		if err != nil {
			return errors.Wrapf(err, "failed to walk path %s", sourcePath)
		}

		rel, err := filepath.Rel(sourceBasePath, sourcePath)
		if err != nil {
			return errors.Wrapf(err, "failed to get rel to base path for %s", sourcePath)
		}
		targetPath := filepath.Join(targetBasePath, rel)
		targetPathBase := filepath.Base(targetBasePath)

		if d.IsDir() {
			fmt.Printf("[DIR ]: %s", filepath.Join(targetPathBase, rel))
			var mkDirFn = os.Mkdir
			if rel == "." {
				mkDirFn = os.MkdirAll
			}
			if err := mkDirFn(targetPath, os.ModePerm); err != nil {
				return errors.Wrapf(err, "failed to create directory: %s", targetPath)
			}
			fmt.Printf(" - OK\n")
		} else {
			fmt.Printf("[FILE]: %s", filepath.Join(targetPathBase, rel))
			if err := lib.CopyFile(sourceFs, sourcePath, targetPath); err != nil {
				return errors.Wrap(err, "failed to copy file")
			}
			fmt.Printf(" - OK\n")
		}

		return nil
	})
}
