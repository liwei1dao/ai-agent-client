package tos

import (
	"context"
	"io"

	"github.com/volcengine/ve-tos-golang-sdk/v2/tos"
)

type (
	ISys interface {
		Get(ctx context.Context, name string, listener tos.DataTransferListener) (resp *tos.GetObjectV2Output, err error)
		Put(ctx context.Context, name string, r io.Reader) (err error)
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func Get(ctx context.Context, name string, listener tos.DataTransferListener) (resp *tos.GetObjectV2Output, err error) {
	return defsys.Get(ctx, name, listener)
}
func Put(ctx context.Context, name string, r io.Reader) (err error) {
	return defsys.Put(ctx, name, r)
}
