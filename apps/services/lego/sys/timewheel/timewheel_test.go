package timewheel_test

import (
	"fmt"
	"testing"
	"time"

	"yunyan/lego/sys/timewheel"
)

func checkTimeCost(t *testing.T, start, end time.Time, before int, after int) bool {
	due := end.Sub(start)
	if due > time.Duration(after)*time.Millisecond {
		t.Error("delay run")
		return false
	}

	if due < time.Duration(before)*time.Millisecond {
		t.Error("run ahead")
		return false
	}

	return true
}

func TestAddFunc(t *testing.T) {
	tw, _ := timewheel.NewSys(timewheel.SetTick(100), timewheel.SetBucketsNum(10))
	tw.Start()
	defer tw.Stop()

	for index := 1; index < 6; index++ {
		queue := make(chan bool, 0)
		start := time.Now()
		tw.Add(time.Duration(index)*time.Second, func(*timewheel.Task, ...interface{}) {
			queue <- true
		})

		<-queue

		before := index*1000 - 200
		after := index*1000 + 200
		checkTimeCost(t, start, time.Now(), before, after)
		fmt.Println("time since: ", time.Since(start).String())
	}
}

func Test_AddFunc(t *testing.T) {
	tw, _ := timewheel.NewSys(timewheel.SetTick(100*time.Millisecond), timewheel.SetBucketsNum(10))
	tw.Start()
	defer tw.Stop()
	start := time.Now()
	tw.AddCron(time.Second, func(*timewheel.Task, ...interface{}) {
		fmt.Println("time since: ", time.Since(start).String())
	})

	time.Sleep(10 * time.Second)
}
