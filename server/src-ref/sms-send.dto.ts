import { IsIn, IsPhoneNumber, IsOptional, IsString } from 'class-validator';

export class SendSmsCodeDto {
  @IsPhoneNumber('CN')
  phone: string;

  @IsIn(['register', 'login', 'bind'])
  scene: 'register' | 'login' | 'bind';

  /**
   * 找回（scene=login）场景可选传入：用于发送前校验手机号与
   * 本机账户（以该设备为主设备的账户）的对应关系，见
   * UserLoginService.checkPhoneForDeviceAccount
   */
  @IsOptional()
  @IsString()
  fingerprint_hash?: string;
}
