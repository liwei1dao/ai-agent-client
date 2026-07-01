package utils

import (
	"hash/fnv"
	"strconv"
)

func Atoi(b []byte) (int, error) {
	return strconv.Atoi(BytesToString(b))
}
func StringToInt64(b string) int64 {
	if i, err := strconv.ParseInt(b, 10, 64); err != nil {
		return 0
	} else {
		return i
	}
}

func StringToUInt64(b string) uint64 {
	if i, err := strconv.ParseUint(b, 10, 64); err != nil {
		return 0
	} else {
		return i
	}
}

func StringToFloat64(b string) float64 {
	if i, err := strconv.ParseFloat(b, 64); err != nil {
		return 0
	} else {
		return i
	}
}
func ParseInt(b []byte, base int, bitSize int) (int64, error) {
	return strconv.ParseInt(BytesToString(b), base, bitSize)
}

func ParseUint(b []byte, base int, bitSize int) (uint64, error) {
	return strconv.ParseUint(BytesToString(b), base, bitSize)
}

func ParseFloat(b []byte, bitSize int) (float64, error) {
	return strconv.ParseFloat(BytesToString(b), bitSize)
}

func ParseBool(b []byte) (bool, error) {
	return strconv.ParseBool(BytesToString(b))
}

func UintToString(n uint64) string {
	return BytesToString(strconv.AppendUint([]byte{}, n, 10))
}

func IntToString(n int64) string {
	return BytesToString(strconv.AppendInt([]byte{}, n, 10))
}

func FloatToString(f float64) string {
	return BytesToString(strconv.AppendFloat([]byte{}, f, 'f', -1, 64))
}

// 字符串Hash到int
func StringHashToInt(s string) uint64 {
	// 创建一个新的 FNV-1a 哈希
	h := fnv.New64a()
	// 写入字符串
	h.Write([]byte(s))
	// 返回哈希值
	return h.Sum64()
}
