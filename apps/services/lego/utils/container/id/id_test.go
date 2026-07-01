package id_test

import (
	"fmt"
	"testing"

	"yunyan/lego/utils/container/id"

	"github.com/bwmarrin/snowflake"
)

func Test_IdXId(t *testing.T) {
	id := id.NewXId()
	fmt.Println(id)
}

func Test_IdUUId(t *testing.T) {
	id := id.NewUUId()
	fmt.Println(id)
}

// 解析 Snowflake ID 获取 NodeID（即你设置的 groupID）
func GetNodeIDFromSnowflakeID(id snowflake.ID) int64 {
	return int64((id >> 12) & 0x3FF) // 取出第 12-21 位（共 10 位）的 NodeID
}

func Test_Ssnowflake(t *testing.T) {
	node, _ := snowflake.NewNode(2) // groupID 映射为 node
	id := node.Generate().String()
	fmt.Println(id)
	id2, _ := snowflake.ParseString(id)
	nodeID := GetNodeIDFromSnowflakeID(id2)
	fmt.Println("解析出的 groupID:", nodeID)
}
