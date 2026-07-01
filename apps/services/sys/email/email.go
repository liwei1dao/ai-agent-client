package email

import (
	"crypto/tls"

	"gopkg.in/gomail.v2"
)

func newSys(options Options) (sys ISys, err error) {
	var (
		smtpHost string
		smtpPort int
	)
	switch options.EmailType {
	case GmailEmail:
		smtpHost = "smtp.gmail.com"
		smtpPort = 587
		break
	case QQEmail:
		smtpHost = "smtp.qq.com"
		smtpPort = 25
		break
	case TencentEmail:
		smtpHost = "smtp.exmail.qq.com"
		smtpPort = 465
		break
	}
	sys = &Email{
		From:   options.FromEmail,
		Name:   options.FromName,
		Dialer: gomail.NewDialer(smtpHost, smtpPort, options.FromEmail, options.Password),
	}
	return
}

type Email struct {
	From   string
	Name   string
	Dialer *gomail.Dialer
}

// 发送邮件
func (this *Email) SendMail(title string, content string, to ...string) (err error) {
	// 创建邮件消息
	m := gomail.NewMessage()
	m.SetHeader("From", m.FormatAddress(this.From, this.Name))
	m.SetHeader("To", to...)
	m.SetHeader("Subject", title)
	m.SetBody("text/html", content)

	// 配置SMTP连接
	this.Dialer.TLSConfig = &tls.Config{InsecureSkipVerify: true} // 可选：跳过证书验证（测试环境使用）
	// 发送邮件
	if err = this.Dialer.DialAndSend(m); err != nil {
		return
	}
	return
}

// 发送邮件
func (this *Email) SendMailForFile(title string, content string, filepath string, filename string, to ...string) (err error) {
	// 创建邮件消息
	m := gomail.NewMessage()
	m.SetHeader("From", m.FormatAddress(this.From, this.Name))
	m.SetHeader("To", to...)

	m.SetHeader("Subject", title)
	m.SetBody("text/html", content)

	// 添加附件（支持多个）
	m.Attach(filepath, gomail.Rename(filename))
	// 配置SMTP连接
	this.Dialer.TLSConfig = &tls.Config{InsecureSkipVerify: true} // 可选：跳过证书验证（测试环境使用）
	// 发送邮件
	if err = this.Dialer.DialAndSend(m); err != nil {
		return
	}
	return
}
