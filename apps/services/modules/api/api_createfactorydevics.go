package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"math"
	"strings"
	"time"
)

// / 创建工厂设备
func (this *apiComp) CreateFactoryDevics(session comm.IUserSession, req *pb.ApiCreateFactoryDevicsReq) (resp *pb.ApiCreateFactoryDevicsResp, errdata *pb.ErrorData) {
	var (
		startmac, endmac, code string
		err                    error
		modelFactory           *pb.DBFactory
		product                *pb.DBProduct
		models                 []*pb.DBFactoryDevics = make([]*pb.DBFactoryDevics, 0, req.Number)
	)

	if modelFactory, err = this.module.model.factory(uint32(req.Factoryid)); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}
	if product, err = this.module.model.product(uint32(req.Productid)); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}

	modelFactory.Probatch++
	// 每副产品需要生产的设备码份数（0或1视为单份）
	codeCount := product.Devicecodecount
	if codeCount == 0 {
		codeCount = 1
	}
	if req.Createtype == 1 { //生产模式
		total := req.Number * codeCount
		if startmac, err = GenerateCustomMAC(uint16(req.Productid), byte(modelFactory.Probatch), uint32(1)); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_SystemError,
				Message: err.Error(),
			}
			return
		}
		if endmac, err = GenerateCustomMAC(uint16(req.Productid), byte(modelFactory.Probatch), uint32(total*2+uint32(math.Ceil(float64(total)/float64(200))))); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_SystemError,
				Message: err.Error(),
			}
			return
		}
		for i := 1; i <= int(total); i++ {
			if code, err = comm.GenerateLicense(uint16(req.Productid), byte(modelFactory.Probatch), uint32(i)); err != nil {
				errdata = &pb.ErrorData{
					Code:    pb.ErrorCode_SystemError,
					Message: err.Error(),
				}
				return
			}
			device := &pb.DBFactoryDevics{
				Code:       code,
				Codetype:   pb.Codetype_AUTHCODE,
				Productid:  req.Productid,
				Factoryid:  req.Factoryid,
				Probatch:   modelFactory.Probatch,
				Number:     uint32(i),
				Createtime: time.Now().Unix(),
			}
			if product.Devicetype == pb.DeviceType_Classic_bluetooth_Headset { //经典蓝牙
				if endmac, err = GenerateCustomMAC(uint16(req.Productid), byte(modelFactory.Probatch), uint32(i)); err != nil {
					errdata = &pb.ErrorData{
						Code:    pb.ErrorCode_SystemError,
						Message: err.Error(),
					}
					return
				}
				device.Codetype = pb.Codetype_DEVICECODE
				device.Devicemac = endmac
			}
			models = append(models, device)
		}
	} else if req.Createtype == 2 { //导入模式
		macaddresses := strings.Split(req.Macaddresses, ",")
		for i, v := range macaddresses {
			if code, err = comm.GenerateLicense(uint16(req.Productid), byte(modelFactory.Probatch), uint32(i+1)); err != nil {
				errdata = &pb.ErrorData{
					Code:    pb.ErrorCode_SystemError,
					Message: err.Error(),
				}
				return
			}
			device := &pb.DBFactoryDevics{
				Code:       code,
				Codetype:   pb.Codetype_DEVICECODE,
				Productid:  req.Productid,
				Factoryid:  req.Factoryid,
				Probatch:   modelFactory.Probatch,
				Number:     uint32(i + 1),
				Createtime: time.Now().Unix(),
				Devicemac:  v,
			}
			models = append(models, device)
		}
	}

	if err = this.module.model.addfactoryDevics(product.Id, models); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("addauthcodes Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.module.model.savefactory(modelFactory); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("savefactory Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.module.model.addfactorydeliverynotes(&pb.DBFactoryDeliveryNote{
		Ts:         time.Now().Unix(),
		Factoryid:  req.Factoryid,
		Productid:  req.Productid,
		Probatch:   modelFactory.Probatch,
		Startmac:   startmac,
		Endmac:     endmac,
		Devicetnum: uint32(len(models)),
	}); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("savefactory Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiCreateFactoryDevicsResp{
		Factoryid: req.Factoryid,
		Productid: req.Productid,
		Startmac:  startmac,
		Endmac:    endmac,
		Probatch:  modelFactory.Probatch,
		Number:    uint32(len(models)),
		Devices:   models,
	}
	return
}
