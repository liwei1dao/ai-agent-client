package utils

import (
	"yunyan/lego/utils"
	"encoding/json"
	"strconv"
)

func ToString(v interface{}) string {
	var (
		err      error
		jsonData []byte
	)
	if v == nil {
		return ""
	}

	if jsonData, err = json.Marshal(v); err != nil {
		return ""
	}
	return utils.BytesToString(jsonData)
}

func ToInt64(s string) int64 {
	if bint, err := strconv.ParseInt(s, 10, 64); err == nil {
		return bint
	}
	return 0
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
