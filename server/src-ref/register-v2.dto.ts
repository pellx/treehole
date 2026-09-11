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

  /** 客户端生成的注册请求幂等 ID（uuid）。同一注册尝试的重试复用同一 ID：
   * 服务端凭此保证只创建一个用户；响应丢失时可凭 ID 查询原注册结果
   * （GET /user/registerV2/result）。 */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  registration_request_id?: string;

  @ValidateNested()
  @Type(() => PoWVerificationDto)
  verification_pow: PoWVerificationDto;
}
