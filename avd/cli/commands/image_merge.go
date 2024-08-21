package commands

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
	"github.com/urfave/cli/v2"
	"io/fs"
	"os"
	"path/filepath"
)

var ImageMergeCommand = &cli.Command{
	Name:  "Merge",
	Usage: "Merge image package",
	Flags: []cli.Flag{
		&cli.PathFlag{
			Name:     "image",
			Usage:    "path to the image folder",
			Required: true,
			Aliases:  []string{"i"},
		},
		&cli.PathFlag{
			Name:    "base-layer",
			Usage:   "path to the base layer",
			Aliases: []string{"b"},
			Value:   "default_image_layers/scripts_setup",
		},
		&cli.PathFlag{
			Name:    "output",
			Usage:   "Path to which the image package will be written",
			Value:   "./out",
			Aliases: []string{"o"},
		},
		&cli.BoolFlag{
			Name:  "dry-run",
			Usage: "Don't actually copy files",
		},
	},
	Action: func(c *cli.Context) error {
		imagePath := c.Path("image")
		baseLayerPath := c.Path("base-layer")
		outputPath := c.Path("output")
		dryRun := c.Bool("dry-run")

		cwd, err := os.Getwd()
		if err != nil {
			return errors.Wrap(err, "failed to get current working directory")
		}
		fullOutputPath := filepath.Join(cwd, outputPath)

		layerPaths := []string{
			imagePath,
			baseLayerPath,
		}

		layerFSs := make([]fs.FS, len(layerPaths))
		for i, layerPath := range layerPaths {
			if ok, err := isDir(layerPath); err != nil {
				return errors.Wrapf(err, "failed to check if layer path is a directory: %s", layerPath)
			} else if !ok {
				return errors.Wrapf(err, "layer is not a directory: %s", layerPath)
			}

			layerFSs[i] = os.DirFS(layerPath)
		}

		fileMappings, fileCollisions, pathTypeCollisions, err := lib.MergeDirectoryLayers(layerFSs, ".")
		if err != nil {
			return errors.Wrap(err, "failed to merge layer directories")
		}

		if len(fileCollisions) > 0 || len(pathTypeCollisions) > 0 {
			if len(fileCollisions) > 0 {
				fmt.Println("The following path(s) have colliding files:")
				for _, collision := range fileCollisions {
					fmt.Printf("- %s\n", collision.Path)
					for _, layerIdx := range collision.CollidingLayerIndexes {
						fmt.Printf("\t+ layer:%s\n", layerPaths[layerIdx])
					}
				}
			}

			if len(pathTypeCollisions) > 0 {
				fmt.Println("On the following path(s) both files and directories exist with the same name:")
				for _, collision := range pathTypeCollisions {
					fmt.Printf("- %s\n", collision.Path)
					for _, layerIdx := range collision.DirectoryLayerIndexes {
						fmt.Printf("\t[DIR ] layer:%s\n", filepath.Join(layerPaths[layerIdx], collision.Path))
					}
					for _, layerIdx := range collision.FileLayerIndexes {
						fmt.Printf("\t[FILE] layer:%s\n", filepath.Join(layerPaths[layerIdx], collision.Path))
					}
				}
			}

			return errors.New("unable to merge layers")
		}

		fmt.Printf("Combining %d files. The following files were renamed:\n", len(fileMappings))
		for i, layerPath := range layerPaths {
			fmt.Printf("From %s\n", layerPath)
			renamed := 0
			for _, fileMapping := range fileMappings {
				if fileMapping.LayerIdx == i && fileMapping.SourcePath != fileMapping.TargetPath { // efficient enough for low number of layers
					fmt.Printf("\t%s -> %s\n", fileMapping.SourcePath, fileMapping.TargetPath)
					renamed++
				}
			}
			if renamed == 0 {
				fmt.Println("\tNo files were renamed")
			}
		}
		fmt.Println()

		if dryRun {
			fmt.Println("Dry run: no files were copied")
		} else {
			if err := executeFileMappings(outputPath, layerFSs, fileMappings); err != nil {
				return errors.Wrap(err, "failed to execute merge")
			}

			fmt.Printf("Created %d files in %s\n", len(fileMappings), fullOutputPath)
		}
		return nil
	},
}

func isDir(path string) (bool, error) {
	pathFile, err := os.Open(path)
	if err != nil {
		return false, errors.Wrap(err, "failed to open path")
	}

	pathInfo, err := pathFile.Stat()
	if err != nil {
		return false, errors.Wrapf(err, "failed to get path info")
	}

	return pathInfo.IsDir(), nil
}

func executeFileMappings(outputPath string, layers []fs.FS, fileMappings []lib.FileMapping) error {
	if err := lib.EnsureEmptyDirectory(outputPath); err != nil {
		return errors.Wrap(err, "failed to create output path")
	}

	createdDirs := map[string]struct{}{}
	for _, mapping := range fileMappings {
		targetPath := filepath.Join(outputPath, mapping.TargetPath)
		dirPath := filepath.Dir(targetPath)
		if _, ok := createdDirs[dirPath]; !ok {
			if err := os.MkdirAll(dirPath, os.ModePerm); err != nil {
				return errors.Wrapf(err, "failed to create directory %s", targetPath)
			}
			createdDirs[dirPath] = struct{}{}
		}

		if err := lib.CopyFile(layers[mapping.LayerIdx], mapping.SourcePath, targetPath); err != nil {
			return errors.Wrapf(err, "failed to copy file from %s (layer=%d) to %s", mapping.SourcePath, mapping.LayerIdx, targetPath)
		}
	}

	return nil
}
