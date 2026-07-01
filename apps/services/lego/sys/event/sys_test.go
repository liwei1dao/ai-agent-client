package event_test

import (
	"fmt"
	"testing"

	"yunyan/lego/core"
	"yunyan/lego/sys/event"
)

func Test_sys(t *testing.T) {
	if err := event.OnInit(nil); err == nil {
		event.Register(core.Event_Key("TestEvent"), func() {
			fmt.Printf("TestEvent TriggerEvent")
		})
		event.TriggerEvent(core.Event_Key("TestEvent"))
	}
}
