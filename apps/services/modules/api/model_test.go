package api_test

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
	"yunyan/comm"
	"yunyan/lego/sys/mysql"
	"yunyan/modules/api"
	"yunyan/pb"
)

// 生成自定义 MAC 地址（64 位 / 8 字节）
func generateCustomMAC(devicetype byte, factoryid byte, batchid uint32, serial uint32) (string, error) {
	if serial > 0xFFFFFF {
		return "", fmt.Errorf("serial number exceeds 3-byte limit (max 16777215)")
	}

	mac := make([]byte, 8)

	// Byte 0: 设备类型
	mac[0] = devicetype

	// Byte 1: 厂商 ID
	mac[1] = factoryid

	// Byte 2~4: 批次 ID（日期压缩或编号）
	mac[2] = byte((batchid >> 16) & 0xFF)
	mac[3] = byte((batchid >> 8) & 0xFF)
	mac[4] = byte(batchid & 0xFF)

	// Byte 5~7: 序号（3字节）
	mac[5] = byte((serial >> 16) & 0xFF)
	mac[6] = byte((serial >> 8) & 0xFF)
	mac[7] = byte(serial & 0xFF)

	// 格式化成 MAC 字符串：每个字节2位，共 8 段
	return fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
		mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], mac[6], mac[7]), nil
}

// 解析自定义 MAC 地址字符串为结构体数据
func parseCustomMAC(macStr string) (devicetype, factoryid byte, batchid, serial uint32, err error) {
	// 去掉冒号并转换为字节
	macStr = strings.ReplaceAll(macStr, ":", "")
	data, err := hex.DecodeString(macStr)
	if err != nil {
		return
	}
	if len(data) != 8 {
		err = fmt.Errorf("invalid MAC length: expected 8 bytes, got %d", len(data))
		return
	}

	// Byte 0: 设备类型
	devicetype = data[0]

	// Byte 1: 厂商 ID
	factoryid = data[1]

	// Byte 2~4: 批次 ID
	batchid = uint32(data[2])<<16 | uint32(data[3])<<8 | uint32(data[4])

	// Byte 5~7: 序号
	serial = uint32(data[5])<<16 | uint32(data[6])<<8 | uint32(data[7])

	return
}
func Test_Sys_Chat(t *testing.T) {
	// str, _ := GetQWeather("上海")
	// fmt.Println(str)
	mac, err := generateCustomMAC(0x01, 0x02, 250624, 123456)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Println("MAC Address:", mac)
	devtype, factory, batchid, serial, err := parseCustomMAC(mac)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("设备类型: 0x%02X\n厂商 ID: 0x%02X\n批次 ID: %d\n序列号: %d\n",
		devtype, factory, batchid, serial)
}
func GetQWeather(city string) (value string, err error) {
	var (
		georesp *http.Response
		resp    *http.Response
		// body    []byte
	)

	apiKey := os.Getenv("QWEATHER_API_KEY")
	if apiKey == "" {
		return "", fmt.Errorf("QWEATHER_API_KEY env not set")
	}
	// 1. 获取城市ID
	geoUrl := fmt.Sprintf("https://geoapi.qweather.com/v2/city/lookup?location=%s&key=%s", city, apiKey)
	georesp, err = http.Get(geoUrl)
	if err != nil {
		return "", err
	}
	defer georesp.Body.Close()

	var geoData map[string]interface{}
	json.NewDecoder(georesp.Body).Decode(&geoData)
	cityID := geoData["location"].([]interface{})[0].(map[string]interface{})["id"].(string)
	fmt.Printf("获取城市id:%s\n", cityID)
	// 2. 获取天气数据
	// https://api.qweather.com/v7/weather/now?location=101010100&key=<QWEATHER_API_KEY>
	weatherUrl := fmt.Sprintf("https://api.qweather.com/v7/weather/now?location=%s&key=%s", cityID, apiKey)
	if resp, err = http.Get(weatherUrl); err != nil {
		return
	}
	defer resp.Body.Close()
	// body, err = io.ReadAll(resp.Body)
	var weatherData map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&weatherData)

	temp := weatherData["now"].(map[string]interface{})["temp"].(string) // 温度
	text := weatherData["now"].(map[string]interface{})["text"].(string) // 天气状况
	// return string(body), nil
	value = fmt.Sprintf("%s: %s℃, %s", city, temp, text)
	return
}

func Test_TavilyApi(t *testing.T) {
	// API配置
	apiURL := "https://api.tavily.com/search"
	apiKey := os.Getenv("TAVILY_API_KEY") // 替换为你的实际API密钥
	if apiKey == "" {
		t.Skip("TAVILY_API_KEY env not set")
	}

	// 创建请求体
	requestBody := struct {
		Query string `json:"query"`
	}{
		Query: "今天武汉的天气", // 你可以修改查询内容
	}

	// 序列化请求体
	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		fmt.Printf("Error marshaling JSON: %v\n", err)
		return
	}

	// 创建HTTP请求
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Printf("Error creating request: %v\n", err)
		return
	}

	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Error making request: %v\n", err)
		return
	}
	defer resp.Body.Close()

	// 读取响应体
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("Error reading response body: %v\n", err)
		return
	}

	// 处理响应
	fmt.Printf("Status Code: %d\n", resp.StatusCode)
	fmt.Printf("Response Body:\n%s\n", body)
}

//  测试api返回效率
func Test_API_AI(t *testing.T) {
	// 测试参数
	apiURL := "http://ideapsound.com/ai/funcchat" // 替换为你的实际地址
	testMessage := &AIChatReq{
		Msg: "今天的天气如何",
		Contexts: []string{
			"我在武汉",
		},
	}

	// 运行测试
	if err := testFuncChat(apiURL, testMessage); err != nil {
		fmt.Printf("测试失败: %v\n", err)
	}
}

type AIChatReq struct {
	Msg      string   `json:"msg"`
	Contexts []string `json:"contexts"`
}

type SSEEvent struct {
	Event string
	Data  string
}

func testFuncChat(url string, req *AIChatReq) error {
	// 准备请求体
	reqBody, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("编码请求体失败: %w", err)
	}

	// 创建HTTP请求
	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(reqBody))
	if err != nil {
		return fmt.Errorf("创建请求失败: %w", err)
	}
	httpReq.Header.Set("Accept", "text/event-stream")
	httpReq.Header.Set("Content-Type", "application/json")

	// 记录开始时间
	startTime := time.Now()
	var firstResponseTime time.Duration

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(httpReq)
	if err != nil {
		return fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("非200状态码: %d", resp.StatusCode)
	}

	// 读取SSE流
	buf := make([]byte, 4096)
	gotFirstResponse := false
	totalBytes := 0
	eventCount := 0

	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			totalBytes += n
			if !gotFirstResponse {
				firstResponseTime = time.Since(startTime)
				gotFirstResponse = true
				fmt.Printf("收到第一个响应时间: %v\n", firstResponseTime)
			}

			// 简单解析SSE事件
			events := parseSSE(buf[:n])
			eventCount += len(events)
			for _, event := range events {
				fmt.Printf("事件[%s]: %s\n", event.Event, event.Data)
			}
		}

		if err != nil {
			if err == io.EOF {
				break
			}
			return fmt.Errorf("读取响应失败: %w", err)
		}
	}

	// 输出统计信息
	totalTime := time.Since(startTime)
	fmt.Println("\n测试结果:")
	fmt.Printf("第一个响应时间: %v\n", firstResponseTime)
	fmt.Printf("总传输时间: %v\n", totalTime)
	fmt.Printf("接收事件数量: %d\n", eventCount)
	fmt.Printf("总数据量: %d bytes\n", totalBytes)
	fmt.Printf("平均传输速率: %.2f bytes/ms\n", float64(totalBytes)/totalTime.Seconds()/1000)

	return nil
}

// 简单SSE解析器
func parseSSE(data []byte) []SSEEvent {
	var events []SSEEvent
	var currentEvent SSEEvent

	lines := bytes.Split(data, []byte("\n"))
	for _, line := range lines {
		if len(line) == 0 {
			continue
		}

		parts := bytes.SplitN(line, []byte(":"), 2)
		if len(parts) < 2 {
			continue
		}

		field := string(parts[0])
		value := string(parts[1])
		if len(value) > 0 && value[0] == ' ' {
			value = value[1:]
		}

		switch field {
		case "event":
			currentEvent.Event = value
		case "data":
			currentEvent.Data = value
			events = append(events, currentEvent)
			currentEvent = SSEEvent{}
		}
	}

	return events
}

// 混淆函数（修复移位错误）
func obfuscate(numStr string, seed int) string {
	// 限制 seed 范围为 1 到 31
	seed = seed % 31
	if seed == 0 {
		seed = 1 // 避免移位 0 位
	}

	// 将字符串转为数字
	num, _ := strconv.Atoi(numStr)

	// 使用 uint32 确保无符号移位
	num32 := uint32(num)
	obfNum := int((num32<<seed | num32>>(32-seed)) ^ uint32(seed))

	// 转为字符串并确保长度一致
	result := fmt.Sprintf("%0*d", len(numStr), obfNum%int(pow10(len(numStr))))
	return result
}

// 计算10的n次方
func pow10(n int) int {
	result := 1
	for i := 0; i < n; i++ {
		result *= 10
	}
	return result
}

func Test_JIAMI(t *testing.T) {
	// code, err := comm.GenerateLicense(0x0302, 1, 1000000)
	// fmt.Println(code, err)
	pid, days, num, err := comm.ValidateLicense("0D82F1CCD83D72B78FA9")
	fmt.Printf("pid:%X, days:%d, num:%d, err:%v\n", pid, days, num, err)
}

func Test_GenerateMac(t *testing.T) {
	// 测试生成MAC地址
	productid := uint16(0x0302)
	batchNumber := byte(1)
	serial := uint32(1000000)

	code, err := api.GenerateCustomMAC(productid, batchNumber, serial)
	if err != nil {
		t.Errorf("生成MAC地址失败: %v", err)
	}
	fmt.Println("生成的MAC地址:", code)

	// 测试解析MAC地址
	parsedProductid, parsedBatchNumber, parsedSerial, err := api.ParseCustomMAC(code)
	if err != nil {
		t.Errorf("解析MAC地址失败: %v", err)
	}

	// 验证解析结果是否与原始输入一致
	if parsedProductid != productid {
		t.Errorf("解析的productid不匹配: 期望 0x%04X, 实际 0x%04X", productid, parsedProductid)
	}

	if parsedBatchNumber != batchNumber {
		t.Errorf("解析的batchNumber不匹配: 期望 %d, 实际 %d", batchNumber, parsedBatchNumber)
	}

	if parsedSerial != serial {
		t.Errorf("解析的serial不匹配: 期望 %d, 实际 %d", serial, parsedSerial)
	}

	fmt.Printf("解析结果: productid=0x%04X, batchNumber=%d, serial=%d\n",
		parsedProductid, parsedBatchNumber, parsedSerial)
}
func Test_DB(t *testing.T) {
	dsn := os.Getenv("MYSQL_DSN")
	if dsn == "" {
		t.Skip("MYSQL_DSN not set, skip")
	}
	if sys, err := mysql.NewSys(
		mysql.SetMySQLDsn(dsn),
	); err != nil {
		fmt.Printf("err:%v", err)
		return
	} else {
		// if err = sys.CreateTable(comm.TableLicense, &pb.DBFactoryDevics{}); err != nil {
		// 	fmt.Printf("创建表失败: %v", err)
		// 	return
		// }
		if err = sys.CreateTable(comm.TableFactory, &pb.DBFactory{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		} else {
			//设置product表的主键从1000开始
			sys.Exec(fmt.Sprintf("ALTER TABLE %s AUTO_INCREMENT = %d", comm.TableFactory, 0xA001))
		}
		if err = sys.CreateTable(comm.TableFactoryDeliveryNote, &pb.DBFactoryDeliveryNote{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		}
		if err = sys.CreateTable(comm.TableProduct, &pb.DBProduct{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		} else {
			//设置product表的主键从1000开始
			sys.Exec(fmt.Sprintf("ALTER TABLE %s AUTO_INCREMENT = %d", comm.TableProduct, 0xB001))
		}
		if err = sys.CreateTable(comm.TableProductVersion, &pb.DBProductVersion{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		}

		// if err = sys.CreateTable(comm.TableLicense, &pb.DBFactoryDevics{}); err != nil {
		// 	fmt.Printf("创建表失败: %v", err)
		// }
		if err = sys.CreateTable(comm.TableGoods, &pb.DBGoods{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		}
		if err = sys.CreateTable(comm.TableWakeupVoice, &pb.DBWakeupVoice{}); err != nil {
			fmt.Printf("创建表失败: %v", err)
		} else {
			//设置product表的主键从1000开始
			sys.Exec(fmt.Sprintf("ALTER TABLE %s AUTO_INCREMENT = %d", comm.TableWakeupVoice, 0xD001))
		}
		return
	}
}

// Test_DeleteTodayProducedDevics 回滚某次生产动作（按时间起点 + 产品 ID 过滤）
//   - 锁定区间: [startTs, 现在) 本地时区，与服务端 time.Now().Unix() 一致
//     startTs=0 时退化为"今日 00:00"
//   - productId=0 表示不限产品；非 0 时只回滚该产品的出货单/设备
//   - 删除范围:
//     1. license_<productid_hex> 表里 factoryid + probatch + createtime>=startTs 命中的设备
//     2. factory_deliverynote 表里 ts>=startTs (+ productid 可选) 的出货单
//     3. factory.probatch 回滚到该厂家剩余出货单（排除本次区间）的 MAX(probatch)，无则置 0
//   - dryRun=true 时只查询打印数量、不写入；确认无误后改成 false 再跑。
//     注意区分国内/国外两套库 (deploy-region-split)，DSN 切换后分别执行。
func Test_DeleteTodayProducedDevics(t *testing.T) {
	dsn := os.Getenv("MYSQL_DSN")
	if dsn == "" {
		t.Skip("MYSQL_DSN not set, skip")
	}
	const (
		dryRun = false
		// 回滚起始时间，本地时区，格式 "2006-01-02 15:04:05"。空串 = 今日 00:00
		startTime = ""
		// 回滚的产品 ID。0 = 不限制产品（区间内所有产品都回滚）
		productId uint32 = 0xB00F
	)

	sys, err := mysql.NewSys(mysql.SetMySQLDsn(dsn))
	if err != nil {
		t.Fatalf("连接 DB 失败: %v", err)
	}

	now := time.Now()
	var tsStart int64
	if startTime == "" {
		tsStart = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).Unix()
	} else {
		ts, err := time.ParseInLocation("2006-01-02 15:04:05", startTime, time.Local)
		if err != nil {
			t.Fatalf("解析 startTime %q 失败: %v", startTime, err)
		}
		tsStart = ts.Unix()
	}
	fmt.Printf("=== 回滚生产动作 ===\n")
	fmt.Printf("dryRun=%v  productId=%d  start_ts=%d (%s)  now=%s\n\n",
		dryRun, productId, tsStart,
		time.Unix(tsStart, 0).Format("2006-01-02 15:04:05"),
		now.Format("2006-01-02 15:04:05"))

	// 1) 拉区间内出货单
	var notes []*pb.DBFactoryDeliveryNote
	noteSQL := fmt.Sprintf("SELECT * FROM %s WHERE ts >= ?", comm.TableFactoryDeliveryNote)
	args := []interface{}{tsStart}
	if productId != 0 {
		noteSQL += " AND productid = ?"
		args = append(args, productId)
	}
	noteSQL += " ORDER BY ts ASC"
	if err := sys.Raw(noteSQL, args...).Scan(&notes).Error; err != nil {
		t.Fatalf("查询 delivery note 失败: %v", err)
	}
	fmt.Printf("[1] 命中出货单 %d 条:\n", len(notes))
	for _, n := range notes {
		fmt.Printf("    id=%d ts=%s factoryid=%d productid=%d probatch=%d num=%d mac:%s ~ %s\n",
			n.Id, time.Unix(n.Ts, 0).Format("15:04:05"),
			n.Factoryid, n.Productid, n.Probatch, n.Devicetnum, n.Startmac, n.Endmac)
	}
	if len(notes) == 0 {
		fmt.Println("\n无今日生产记录，结束")
		return
	}

	factoryIDs := map[uint32]struct{}{}
	for _, n := range notes {
		factoryIDs[n.Factoryid] = struct{}{}
	}

	// 2) 逐条出货单 → license_<productid_hex> 删设备
	fmt.Printf("\n[2] 删除设备表 license_<productid_hex>:\n")
	for _, n := range notes {
		tname := fmt.Sprintf("%s_%x", comm.TableLicense, n.Productid)
		var (
			cnt, bound int64
		)
		if err := sys.Raw(fmt.Sprintf("SELECT COUNT(*) FROM %s WHERE factoryid=? AND probatch=? AND createtime>=?", tname),
			n.Factoryid, n.Probatch, tsStart).Scan(&cnt).Error; err != nil {
			fmt.Printf("    [WARN] 表 %s 查询失败 (可能不存在): %v\n", tname, err)
			continue
		}
		_ = sys.Raw(fmt.Sprintf("SELECT COUNT(*) FROM %s WHERE factoryid=? AND probatch=? AND createtime>=? AND (status<>0 OR uid<>'')", tname),
			n.Factoryid, n.Probatch, tsStart).Scan(&bound).Error
		fmt.Printf("    %s factoryid=%d probatch=%d → 命中 %d 行 (其中已绑定/已使用 %d 行)\n",
			tname, n.Factoryid, n.Probatch, cnt, bound)
		if bound > 0 {
			fmt.Printf("    [WARN] 该批次已有绑定/使用记录，删除会丢失用户绑定数据，请人工确认\n")
		}
		if !dryRun {
			tx := sys.Exec(fmt.Sprintf("DELETE FROM %s WHERE factoryid=? AND probatch=? AND createtime>=?", tname),
				n.Factoryid, n.Probatch, tsStart)
			if tx.Error != nil {
				t.Errorf("删除 %s 失败: %v", tname, tx.Error)
				continue
			}
			fmt.Printf("    -> 已删除 %d 行\n", tx.RowsAffected)
		}
	}

	// 3) 删除区间内出货单
	delSQL := fmt.Sprintf("DELETE FROM %s WHERE ts>=?", comm.TableFactoryDeliveryNote)
	delArgs := []interface{}{tsStart}
	if productId != 0 {
		delSQL += " AND productid = ?"
		delArgs = append(delArgs, productId)
	}
	fmt.Printf("\n[3] 删除出货单 %s (ts>=%d productId=%d):\n", comm.TableFactoryDeliveryNote, tsStart, productId)
	if dryRun {
		fmt.Printf("    将删除 %d 条\n", len(notes))
	} else {
		tx := sys.Exec(delSQL, delArgs...)
		if tx.Error != nil {
			t.Errorf("删除 delivery note 失败: %v", tx.Error)
		} else {
			fmt.Printf("    -> 已删除 %d 条\n", tx.RowsAffected)
		}
	}

	// 4) 回滚 factory.probatch = MAX(剩余出货单的 probatch)
	// 注意 probatch 是 factory 维度计数器，跨产品共享，所以要取该厂家所有剩余出货单的 MAX
	fmt.Printf("\n[4] 回滚 factory.probatch (该厂家剩余出货单的 MAX(probatch)):\n")
	for fid := range factoryIDs {
		var newVal uint32
		maxSQL := fmt.Sprintf("SELECT COALESCE(MAX(probatch), 0) FROM %s WHERE factoryid=? AND NOT (ts>=?", comm.TableFactoryDeliveryNote)
		maxArgs := []interface{}{fid, tsStart}
		if productId != 0 {
			maxSQL += " AND productid=?"
			maxArgs = append(maxArgs, productId)
		}
		maxSQL += ")"
		if err := sys.Raw(maxSQL, maxArgs...).Scan(&newVal).Error; err != nil {
			t.Errorf("查询厂家 %d MAX(probatch) 失败: %v", fid, err)
			continue
		}
		var current uint32
		_ = sys.Raw(fmt.Sprintf("SELECT probatch FROM %s WHERE id=?", comm.TableFactory), fid).Scan(&current).Error
		fmt.Printf("    factoryid=%d  probatch: %d -> %d\n", fid, current, newVal)
		if !dryRun {
			tx := sys.Exec(fmt.Sprintf("UPDATE %s SET probatch=? WHERE id=?", comm.TableFactory), newVal, fid)
			if tx.Error != nil {
				t.Errorf("回滚厂家 %d probatch 失败: %v", fid, tx.Error)
			}
		}
	}

	fmt.Printf("\n=== 完成 (dryRun=%v) ===\n", dryRun)
}

// Test_RebuildFactoryProbatch 修复厂家 probatch 被重置的历史脏数据
// 用 factory_deliverynote 作权威源（每次生产都会落一条不可变记录），
// 把 factory.probatch 推回到该厂家历史 MAX(probatch)。**只增不减**，
// 防止当前值意外已比历史最大值更高（比如刚有人正在生产）。
//
// 适用场景: api_updatefactory 旧版本曾把前端传过来的 probatch=0 整字段
// Save 覆盖到 DB，导致下次生产又从 1 开始。该函数把所有厂家的 probatch
// 一次性修正回历史最大值。
//
// dryRun=true 时只查询打印，确认无误后改成 false 真正执行。
// 注意区分国内/外两套库 (deploy-region-split)，DSN 切换后分别执行。
func Test_RebuildFactoryProbatch(t *testing.T) {
	dsn := os.Getenv("MYSQL_DSN")
	if dsn == "" {
		t.Skip("MYSQL_DSN not set, skip")
	}
	const (
		dryRun = false
	)

	sys, err := mysql.NewSys(mysql.SetMySQLDsn(dsn))
	if err != nil {
		t.Fatalf("连接 DB 失败: %v", err)
	}

	fmt.Printf("=== 重建厂家 probatch ===\ndryRun=%v\n\n", dryRun)

	// 1) 拉所有厂家当前 probatch
	type factoryRow struct {
		Id       uint32
		Factory  string
		Probatch uint32
	}
	var factories []factoryRow
	if err := sys.Raw(fmt.Sprintf("SELECT id, factory, probatch FROM %s", comm.TableFactory)).Scan(&factories).Error; err != nil {
		t.Fatalf("查询厂家失败: %v", err)
	}
	if len(factories) == 0 {
		fmt.Println("无厂家记录")
		return
	}

	// 2) 拉每个厂家的历史 MAX(probatch)
	type maxRow struct {
		Factoryid uint32
		MaxPro    uint32
	}
	var maxes []maxRow
	if err := sys.Raw(fmt.Sprintf(
		"SELECT factoryid, MAX(probatch) AS max_pro FROM %s GROUP BY factoryid",
		comm.TableFactoryDeliveryNote)).Scan(&maxes).Error; err != nil {
		t.Fatalf("查询历史 MAX(probatch) 失败: %v", err)
	}
	maxMap := make(map[uint32]uint32, len(maxes))
	for _, m := range maxes {
		maxMap[m.Factoryid] = m.MaxPro
	}

	// 3) 对比 & 修复
	var (
		needFix      []factoryRow
		needFixNewMx []uint32
		untouched    int
		noHistory    int
	)
	for _, f := range factories {
		histMax, ok := maxMap[f.Id]
		if !ok {
			// 该厂家在 deliverynote 没记录，不动
			noHistory++
			continue
		}
		if f.Probatch >= histMax {
			untouched++
			continue
		}
		needFix = append(needFix, f)
		needFixNewMx = append(needFixNewMx, histMax)
	}

	fmt.Printf("[扫描结果]\n")
	fmt.Printf("  厂家总数:               %d\n", len(factories))
	fmt.Printf("  无生产历史(不动):       %d\n", noHistory)
	fmt.Printf("  probatch 已是最大(不动):%d\n", untouched)
	fmt.Printf("  需修复:                 %d\n\n", len(needFix))

	if len(needFix) == 0 {
		fmt.Println("无需修复，结束")
		return
	}

	fmt.Printf("[需修复明细]\n")
	for i, f := range needFix {
		fmt.Printf("  factoryid=%d (%s)  probatch: %d -> %d\n",
			f.Id, f.Factory, f.Probatch, needFixNewMx[i])
	}

	if dryRun {
		fmt.Printf("\n[dryRun=true 不写入] 设为 false 重新跑可真正修复\n")
		return
	}

	// 4) 真正写入：用 UPDATE ... WHERE probatch < ? 双重保护，
	//    防止从扫描到写入之间已被其他生产推上去过。
	fmt.Printf("\n[开始写入]\n")
	var fixed, skipped int
	for i, f := range needFix {
		tx := sys.Exec(
			fmt.Sprintf("UPDATE %s SET probatch=? WHERE id=? AND probatch<?", comm.TableFactory),
			needFixNewMx[i], f.Id, needFixNewMx[i])
		if tx.Error != nil {
			t.Errorf("更新 factoryid=%d 失败: %v", f.Id, tx.Error)
			continue
		}
		if tx.RowsAffected == 0 {
			fmt.Printf("  factoryid=%d 期间已被其他写入推到 >= %d，跳过\n", f.Id, needFixNewMx[i])
			skipped++
			continue
		}
		fmt.Printf("  factoryid=%d 修复完成: probatch -> %d\n", f.Id, needFixNewMx[i])
		fixed++
	}
	fmt.Printf("\n=== 完成 fixed=%d skipped=%d (dryRun=%v) ===\n", fixed, skipped, dryRun)
}
