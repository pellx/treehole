import {
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { DeviceFingerprintDto } from './fingerprint.dto';
import { PoWVerificationDto } from './register.dto';

export class RegisterV2Dto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  user_display_id: string;

  @ValidateNested()
  @Type(() => DeviceFingerprintDto)
  device_finger_print: DeviceFingerprintDto;

  @IsOptional()
  @IsString()
  verification_captcha?: string;

  /** 通过测试页即时校验通过后由服务端签发的 Redis 凭证（与
   *  verification_captcha 二选一，凭证在注册成功后销毁） */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  verification_captcha_ticket?: string;

  @ValidateNested()
  @Type(() => PoWVerificationDto)
  verification_pow: PoWVerificationDto;
}
