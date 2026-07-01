package id

import (
	"crypto/sha256"
	"encoding/hex"

	"github.com/bwmarrin/snowflake"
	uuid "github.com/google/uuid"
	"github.com/rs/xid"
)

// xid
func NewXId() string {
	id := xid.New()
	return id.String()
}

// uuid
func NewUUId() string {
	u1 := uuid.New()
	return u1.String()
}

// 带分组Id
func NewSnowflakeId(group int64) string {
	node, _ := snowflake.NewNode(group) //groupID 映射为 node
	id := node.Generate().String()
	return id
}

// 解析 Snowflake ID 获取 NodeID（即你设置的 groupID）
func GetNodeIDFromSnowflakeID(id snowflake.ID) int64 {
	return int64((id >> 12) & 0x3FF) // 取出第 12-21 位（共 10 位）的 NodeID
}

// 获取id 的分组
func GetSnowflakeId(str string) (group int64, err error) {
	var (
		id snowflake.ID
	)
	if id, err = snowflake.ParseString(str); err != nil {
		return
	}
	group = int64((id >> 12) & 0x3FF)
	return
}

// 根据字符串生成唯一id
func GenerateSHA256ID(input string) string {
	hash := sha256.New()
	hash.Write([]byte(input))
	return hex.EncodeToString(hash.Sum(nil))
}
