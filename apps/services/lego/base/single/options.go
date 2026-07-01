package single

import (
	"fmt"
	"os"
	"regexp"

	"yunyan/lego/core"
	"yunyan/lego/utils/container/id"

	"gopkg.in/yaml.v2"
)

// 匹配 ${VAR} 与 ${VAR:-default} 两种占位符（与 rpcx base 一致）
var envVarRe = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}`)

// expandEnv 展开配置内容里的环境变量占位符，便于多服务共用同一份环境文件（docker compose env_file）：
//   - ${VAR}            取环境变量 VAR，未设置时替换为空串
//   - ${VAR:-default}   取环境变量 VAR，未设置或为空时使用 default
func expandEnv(content string) string {
	return envVarRe.ReplaceAllStringFunc(content, func(m string) string {
		sub := envVarRe.FindStringSubmatch(m)
		name, def := sub[1], sub[2]
		if v, ok := os.LookupEnv(name); ok && v != "" {
			return v
		}
		return def
	})
}

type Option func(*Options)

// Options 单例服务配置（不依赖 etcd / RPCX 集群）
type Options struct {
	ConfPath string              //配置文件路径
	Version  string              //服务版本
	Setting  core.ServiceSttings //服务配置表
}

func SetConfPath(v string) Option {
	return func(o *Options) {
		o.ConfPath = v
	}
}

func SetVersion(v string) Option {
	return func(o *Options) {
		o.Version = v
	}
}

func newOptions(option ...Option) *Options {
	options := &Options{
		ConfPath: "conf/single.yaml",
	}
	for _, o := range option {
		o(options)
	}
	yamlFile, err := os.ReadFile(options.ConfPath)
	if err != nil {
		panic(fmt.Sprintf("读取服务配置【%s】文件失败err:%v:", options.ConfPath, err))
	}
	// 先做环境变量替换，再解析。这样公共配置（如 DSN、Redis 地址）只需在环境文件改一处。
	if err = yaml.Unmarshal([]byte(expandEnv(string(yamlFile))), &options.Setting); err != nil {
		panic(fmt.Sprintf("读取服务配置【%s】文件失败err:%v:", options.ConfPath, err))
	}
	// 单例服务只要求 Type，不依赖集群标签 / etcd 注册
	if len(options.Setting.Type) == 0 {
		panic(fmt.Sprintf("[%s] 配置缺少必要配置 type: %+v", options.ConfPath, options))
	}
	if len(options.Setting.Id) == 0 {
		options.Setting.Id = fmt.Sprintf("%s-%s", options.Setting.Type, id.NewXId())
	}
	return options
}
