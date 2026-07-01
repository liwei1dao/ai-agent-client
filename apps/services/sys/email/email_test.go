package email_test

import (
	"crypto/tls"
	"yunyan/sys/email"
	"fmt"
	"net/smtp"
	"testing"

	eml "github.com/jordan-wright/email"
	"gopkg.in/gomail.v2"
)

// 发送邮件
func Test_Sys(t *testing.T) {
	if sys, err := email.NewSys(
		email.Set_EmailType(email.TencentEmail),
		email.Set_FromEmail("liwei@yunqiinnovation.com"),
		email.Set_Password("eNdXWrjSQbdYtwbt")); err != nil {
		fmt.Println(err)
		return
	} else {
		err = sys.SendMail("测试邮件主题", "<h1>邮件正文</h1><p>这是一封通过Golang发送的测试邮件。</p>", "2211068034@qq.com")
		fmt.Println(err)
	}
}

// 发送邮件
func Test_SendMail_Gamil(t *testing.T) {
	e := eml.NewEmail()
	e.From = "liwei1dao@gmail.com"
	e.To = []string{"2211068034@qq.com"}
	// e.Bcc = []string{"test_bcc@example.com"}
	// e.Cc = []string{"test_cc@example.com"}
	e.Subject = "Awesome Subject"
	e.Text = []byte("Text Body is, of course, supported!")
	e.HTML = []byte("")
	err := e.Send("smtp.gmail.com:587", smtp.PlainAuth("", "liwei1dao@gmail.com", "afsqdeweopnpakuw", "smtp.gmail.com"))
	fmt.Printf("Test_SendMail:%v", err)
}

// 发送邮件
func Test_SendMail_QQ(t *testing.T) {
	e := eml.NewEmail()
	e.From = "2211068034@qq.com"
	e.To = []string{"2211068034@qq.com"}
	// e.Bcc = []string{"test_bcc@example.com"}
	// e.Cc = []string{"test_cc@example.com"}
	e.Subject = "Awesome Subject"
	e.Text = []byte("Text Body is, of course, supported!")
	e.HTML = []byte("")
	err := e.Send("smtp.qq.com:25", smtp.PlainAuth("", "2211068034@qq.com", "ffngwepbmewcdifc", "smtp.qq.com"))
	fmt.Printf("Test_SendMail:%v", err)
}

// 发送邮件
func Test_SendMail_TencentEmail(t *testing.T) {
	// e := eml.NewEmail()
	// e.From = "liwei@yunqiinnovation.com"
	// e.To = []string{"2211068034@qq.com"}
	// // e.Bcc = []string{"test_bcc@example.com"}
	// // e.Cc = []string{"test_cc@example.com"}
	// e.Subject = "Awesome Subject"
	// e.Text = []byte("Text Body is, of course, supported!")
	// e.HTML = []byte("")
	// err := e.Send("smtp.exmail.qq.com:465", smtp.PlainAuth("", "liwei@yunqiinnovation.com", "eNdXWrjSQbdYtwbt", "smtp.exmail.qq.com"))
	// fmt.Printf("Test_SendMail:%v", err)

	//配置参数
	smtpHost := "smtp.exmail.qq.com"
	smtpPort := 465
	fromEmail := "liwei@yunqiinnovation.com"        // 发件人邮箱
	authCode := "eNdXWrjSQbdYtwbt"                  // 授权码
	toEmails := []string{"lizayop92887@icloud.com"} // 收件人列表

	// 创建邮件消息
	m := gomail.NewMessage()
	m.SetHeader("From", m.FormatAddress("liwei@yunqiinnovation.com", "云翔创新科技"))
	m.SetHeader("To", toEmails...)
	m.SetHeader("Subject", "测试邮件主题")
	m.SetBody("text/html", "<h1>邮件正文</h1><p>这是一封通过Golang发送的测试邮件。</p>")

	// 配置SMTP连接
	d := gomail.NewDialer(smtpHost, smtpPort, fromEmail, authCode)
	d.TLSConfig = &tls.Config{InsecureSkipVerify: true} // 可选：跳过证书验证（测试环境使用）

	// 发送邮件
	if err := d.DialAndSend(m); err != nil {
		fmt.Println("邮件发送失败:", err)
		return
	}
	fmt.Println("邮件发送成功！")
}

func TestSendMail(t *testing.T) {
	if sys, err := email.NewSys(
		email.Set_EmailType(email.TencentEmail),
		email.Set_FromEmail("liwei@yunqiinnovation.com"),
		email.Set_Password("eNdXWrjSQbdYtwbt")); err != nil {
		fmt.Println(err)
		return
	} else {
		err = sys.SendMail("Sign-in Verification Code", fmt.Sprintf("<html><body><p>Your verification code is: <strong>%d</strong></p><p>For your account security, please do not share this code with anyone.</p></body></html>", 2467), "2211068034@qq.com")
		fmt.Println(err)
	}
}
