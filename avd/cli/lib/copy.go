package lib

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"io"
	"io/fs"
	"os"
)

func EnsureEmptyDirectory(path string) error {
	fileInfo, err := os.Stat(path)
	if err != nil {
		if !os.IsNotExist(err) {
			return errors.Wrapf(err, "failed to check path for existing folder/file: %s", path)
		}
	} else {
		if fileInfo.IsDir() {
			return fmt.Errorf("directory already exists: %s", path)
		} else {
			return fmt.Errorf("directory is already a file: %s", path)
		}
	}

	return os.MkdirAll(path, os.ModePerm)
}

func CopyFile(sourceFs fs.FS, sourcePath, targetPath string) error {
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

	return nil
}
