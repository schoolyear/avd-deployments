package lib

import (
	"fmt"
	"github.com/friendsofgo/errors"
	"io"
	"io/fs"
	"os"
)

func EnsureEmptyDirectory(path string, overwriteOnCollision bool) error {
	if overwriteOnCollision {
		if err := os.RemoveAll(path); err != nil {
			return errors.Wrapf(err, "failed to delete path: %s", path)
		}
	} else {
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

func CalcDirSizeRecursively(fsys fs.FS) (int64, error) {
	var size int64
	err := fs.WalkDir(fsys, ".", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() {
			info, err := fs.Stat(fsys, path)
			if err != nil {
				return errors.Wrapf(err, "failed to get file info on %s", path)
			}
			size += info.Size()
		}
		return nil
	})
	return size, err
}

type EmptyFs struct{}

func (e EmptyFs) ReadDir(_ string) ([]fs.DirEntry, error) {
	return []fs.DirEntry{}, nil
}

func (e EmptyFs) Open(_ string) (fs.File, error) {
	return nil, os.ErrNotExist
}
