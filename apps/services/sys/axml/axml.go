package axml

import (
	"regexp"
	"strings"
)

func newSys(options Options) (sys ISys, err error) {
	sys = &AXml{}
	return
}

// XMLItem 表示一个通用的 XML 数据项
type XMLItem struct {
	TagName    string            // 标签名
	Attributes map[string]string // 属性键值对
	Content    string            // 标签内容
}
type AXml struct {
	source string
	buffer string
	items  []*XMLItem
}

func (this *AXml) Add(data string) (err error) {
	this.source += data
	this.buffer += data
	this.processData()
	return
}

func (this *AXml) Get(name string) (items []*XMLItem) {
	items = make([]*XMLItem, 0)
	for _, v := range this.items {
		if v.TagName == name {
			items = append(items, v)
		}
	}
	return
}

// 解析数据
func (this *AXml) processData() {
	// 匹配完整的 <tag attr="value">content</tag> 模式
	// 捕获标签名、属性和内容
	re := regexp.MustCompile(`<([a-zA-Z][^>]*)>((?:[^<]|<[^/])*?)</([a-zA-Z][^>]*)>`)
	matches := re.FindAllStringSubmatch(this.buffer, -1)

	// var items []XMLItem
	for _, match := range matches {
		if len(match) != 4 {
			continue
		}
		// match[0] 是完整匹配，match[1] 是标签和属性部分，match[2] 是内容
		tagAndAttrs := match[1]
		content := match[2]

		// 解析标签名和属性
		attrRe := regexp.MustCompile(`([a-zA-Z]+)(?: *= *"([^"]*)")?`)
		attrMatches := attrRe.FindAllStringSubmatch(tagAndAttrs, -1)

		item := &XMLItem{
			Attributes: make(map[string]string),
		}
		for _, attrMatch := range attrMatches {
			if len(attrMatch) >= 2 {
				if item.TagName == "" {
					item.TagName = attrMatch[1] // 第一个捕获组是标签名
				}
				if len(attrMatch) == 3 && attrMatch[2] != "" {
					item.Attributes[attrMatch[1]] = attrMatch[2] // 属性名和值
				}
			}
		}
		item.Content = strings.TrimSpace(content)

		if item.TagName != "" {
			this.items = append(this.items, item)
			// 从缓冲区移除已解析的部分
			this.buffer = this.buffer[strings.Index(this.buffer, match[0])+len(match[0]):]
		}
	}

}
