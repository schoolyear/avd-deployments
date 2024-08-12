package commands

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/embeddedfiles"
	"github.com/urfave/cli/v2"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
)

var ImageNewCommand = cli.Commands{
	{
		Name:  "new",
		Usage: "create a new image folder structure",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:     "name",
				Usage:    "path-safe name of the new image",
				Required: true,
			},
			&cli.PathFlag{
				Name:  "base-path",
				Value: "./",
				Usage: "Path in which the new image folder should be created",
			},
		},
		Action: func(c *cli.Context) error {
			name := c.String("name")
			basePath := c.Path("base-path")

			targetPath := path.Join(basePath, name)

			fileInfo, err := os.Stat(targetPath)
			if err != nil {
				if !os.IsNotExist(err) {
					return errors.Wrapf(err, "failed to check new folder path: %s", targetPath)
				}
			} else {
				if fileInfo.IsDir() {
					return fmt.Errorf("target directory already exists: %s", targetPath)
				} else {
					return fmt.Errorf("target directory is already a file: %s", targetPath)
				}
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
			sourceFile, err := sourceFs.Open(sourcePath)
			if err != nil {
				return errors.Wrapf(err, "failed to open source file for copying %s", targetPath)
			}
			defer sourceFile.Close()

			targetFile, err := os.Create(targetPath)
			if err != nil {
				return errors.Wrapf(err, "failed to create new file %s", targetPath)
			}
			defer targetFile.Close()

			if _, err := io.Copy(targetFile, sourceFile); err != nil {
				return errors.Wrapf(err, "failed to write template file %s", targetPath)
			}
			fmt.Printf(" - OK\n")
		}

		return nil
	})
}
