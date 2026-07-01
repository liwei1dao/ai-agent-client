package api

import (
	"yunyan/comm"
	"yunyan/pb"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// 运行日志根目录（相对于 home 服务的工作目录 bin/）
const runtimeLogDir = "./log"

// 服务名白名单校验：仅允许字母数字与下划线
var runtimeLogServiceRe = regexp.MustCompile(`^[A-Za-z0-9_]+$`)

// 列出可查询的运行日志服务
func (this *apiComp) ListRuntimeLogs(session comm.IUserSession, req *pb.ApiListRuntimeLogsReq) (resp *pb.ApiListRuntimeLogsResp, errdata *pb.ErrorData) {
	if session.GetMateToString("identity") != "1" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_InsufficientPermissions, Message: "仅超管可访问"}
		return
	}

	resp = &pb.ApiListRuntimeLogsResp{Services: []string{}}
	entries, err := os.ReadDir(runtimeLogDir)
	if err != nil {
		if os.IsNotExist(err) {
			return
		}
		errdata = &pb.ErrorData{Code: pb.ErrorCode_SystemError, Message: err.Error()}
		return
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".log") {
			continue
		}
		base := strings.TrimSuffix(name, ".log")
		if !runtimeLogServiceRe.MatchString(base) {
			continue
		}
		resp.Services = append(resp.Services, base)
	}
	sort.Strings(resp.Services)
	return
}

// 查询某服务运行日志（从尾部倒序读取，支持 load more）
func (this *apiComp) GetRuntimeLog(session comm.IUserSession, req *pb.ApiGetRuntimeLogReq) (resp *pb.ApiGetRuntimeLogResp, errdata *pb.ErrorData) {
	if session.GetMateToString("identity") != "1" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_InsufficientPermissions, Message: "仅超管可访问"}
		return
	}
	if !runtimeLogServiceRe.MatchString(req.Service) {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "非法服务名"}
		return
	}
	limit := int(req.Limit)
	if limit <= 0 {
		limit = 500
	}
	if limit > 2000 {
		limit = 2000
	}

	// 路径穿越防护
	path := filepath.Join(runtimeLogDir, req.Service+".log")
	absLog, _ := filepath.Abs(runtimeLogDir)
	absFile, _ := filepath.Abs(path)
	if !strings.HasPrefix(absFile, absLog) {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "非法路径"}
		return
	}

	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			resp = &pb.ApiGetRuntimeLogResp{Lines: []string{}}
			return
		}
		errdata = &pb.ErrorData{Code: pb.ErrorCode_SystemError, Message: err.Error()}
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_SystemError, Message: err.Error()}
		return
	}
	fileSize := info.Size()

	end := req.Before
	if end <= 0 || end > fileSize {
		end = fileSize
	}

	lines, earliest, err := readTailLines(f, end, limit, req.Keyword)
	if err != nil && err != io.EOF {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_SystemError, Message: err.Error()}
		return
	}

	resp = &pb.ApiGetRuntimeLogResp{
		Lines:    lines,
		Earliest: earliest,
		FileSize: fileSize,
		HasMore:  earliest > 0,
	}
	return
}

// readTailLines 从 end 位置向前读取最多 limit 行（命中 keyword 过滤），返回旧→新顺序
// earliest = 所返回内容在文件中的起始字节位置
func readTailLines(f *os.File, end int64, limit int, keyword string) (lines []string, earliest int64, err error) {
	const chunkSize = 64 * 1024
	if end <= 0 {
		return []string{}, 0, nil
	}

	var tail []byte // 未处理的尾部缓冲
	pos := end
	collected := make([]string, 0, limit)
	reachedStart := false

	for len(collected) < limit {
		if pos <= 0 {
			reachedStart = true
			break
		}
		readSize := int64(chunkSize)
		if pos < readSize {
			readSize = pos
		}
		offset := pos - readSize
		buf := make([]byte, readSize)
		if _, rerr := f.ReadAt(buf, offset); rerr != nil && rerr != io.EOF {
			return nil, 0, rerr
		}
		// 把本次 chunk 拼到尾部缓冲前面
		combined := append(buf, tail...)
		pos = offset

		// 从后往前按 \n 切。最前面一段可能是跨界的半行，留下来
		idx := len(combined)
		for i := len(combined) - 1; i >= 0; i-- {
			if combined[i] == '\n' {
				line := string(combined[i+1 : idx])
				idx = i
				if line == "" {
					continue
				}
				if keyword != "" && !strings.Contains(line, keyword) {
					continue
				}
				collected = append(collected, line)
				if len(collected) >= limit {
					break
				}
			}
		}
		// idx 之前是半行（还未遇到 \n），保留到下一轮
		tail = combined[:idx]

		if pos == 0 {
			// 已读到文件头，tail 就是最开始那一行
			if len(collected) < limit && len(tail) > 0 {
				line := string(tail)
				if keyword == "" || strings.Contains(line, keyword) {
					collected = append(collected, line)
				}
				tail = nil
			}
			reachedStart = true
			break
		}
	}

	// collected 是从新到旧累积的，反转成 旧→新
	lines = make([]string, 0, len(collected))
	for i := len(collected) - 1; i >= 0; i-- {
		lines = append(lines, collected[i])
	}

	if reachedStart {
		earliest = 0
	} else {
		// 下一次 before 应该指向 "本批最早一行的起始字节"。
		// pos 指向下一个未读 chunk 的起点；tail 是跨界半行，最早行就在 pos + 0 处之后。
		// 简化：直接取 pos（指向未处理 chunk 的起点），因为 tail 是半行属于上一 chunk，
		// 而最早返回的整行恰好是上一个 \n 之后。为了下次能完整读到该行，返回 pos 即可。
		earliest = pos + int64(len(tail))
		if earliest < 0 {
			earliest = 0
		}
	}
	return
}
