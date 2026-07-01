package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 批量重置License状态
func (this *apiComp) BatchResetLicenseStatus(session comm.IUserSession, req *pb.ApiBatchResetLicenseStatusReq) (resp *pb.ApiBatchResetLicenseStatusResp, errdata *pb.ErrorData) {
	resp = &pb.ApiBatchResetLicenseStatusResp{}
	for _, license := range req.Licenses {
		if err := this.resetOneLicense(license); err != nil {
			resp.FailCount++
		} else {
			resp.SuccessCount++
		}
	}
	return
}

// resetOneLicense 重置单条 License 到初始状态（复用逻辑，供单条和批量共享）
func (this *apiComp) resetOneLicense(license string) error {
	pid, _, _, err := comm.ValidateLicense(license)
	if err != nil {
		err = nil
		pid = uint16(45058)
	}
	model, err := this.module.model.factoryDevic(uint32(pid), license)
	if err != nil {
		return err
	}
	wasActivated := model.Uid != ""
	if wasActivated {
		if err = this.module.model.deluserdevice(model.Uid); err != nil {
			return err
		}
	}
	model.Status = 0
	model.Uid = ""
	model.Devicemac = ""
	model.Usedtime = 0
	if err = this.module.model.updatefactoryDevic(uint32(pid), model); err != nil {
		return err
	}
	if wasActivated && model.Productid > 0 {
		_ = this.module.model.decrProductStatActivated(model.Productid)
	}
	return nil
}
