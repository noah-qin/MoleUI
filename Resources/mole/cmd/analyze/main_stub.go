//go:build !darwin

package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "analyze is only supported on macOS")
	os.Exit(1)
}
