import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class CaptchaVerifyDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(4096)
  captcha_verify_param: string;
}
