import { Type } from 'class-transformer';
import {
  IsNotEmpty,
  IsPhoneNumber,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { DeviceFingerprintDto } from './fingerprint.dto';

/**
 * 手机号验证码注册：防刷依赖短信送达本身（60s 冷却/每日上限/IP 限流），
 * 不再要求阿里云 CAPTCHA 与 PoW。
 */
export class SmsRegisterDto {
  @IsPhoneNumber('CN')
  phone: string;

  @IsString()
  @IsNotEmpty()
  code: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  user_display_id: string;

  @ValidateNested()
  @Type(() => DeviceFingerprintDto)
  device_finger_print: DeviceFingerprintDto;
}
