package google_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/google"
)

func Test_Sys(t *testing.T) {
	jsonPath := os.Getenv("GOOGLE_SA_JSON_PATH")
	if jsonPath == "" {
		t.Skip("GOOGLE_SA_JSON_PATH env not set")
	}
	if sys, err := google.NewSys(
		google.SetJsonPath(jsonPath),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		token, err := sys.SpeechToken()
		fmt.Printf(" token:%v err:%v", token, err)
	}
}
