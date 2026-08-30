import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Client, {
  VerifyIntelligentCaptchaRequest,
} from '@alicloud/captcha20230305';
import { $OpenApiUtil } from '@alicloud/openapi-core';
import { VerificationStrategy, VerificationResult } from './turnstile.strategy';

const DEFAULT_ENDPOINT = 'captcha.cn-shanghai.aliyuncs.com';

/**
 * 阿里云验证码 2.0（无痕验证）服务端校验。
 * captchaVerifyParam 由客户端回调原样透传，服务端不做任何改动。
 * token 一次性（复用/过期返回 F008），故不做 Redis 缓存复用。
 */
@Injectable()
export class CaptchaStrategy implements VerificationStrategy {
  readonly method = 'captcha';
  private readonly logger = new Logger(CaptchaStrategy.name);
  private client: Client | null = null;
  private sceneId: string;
  private endpoint: string;

  constructor(private readonly configService: ConfigService) {
    const accessKeyId = this.configService.get<string>(
      'ALIBABA_CLOUD_ACCESS_KEY_ID',
    );
    const accessKeySecret = this.configService.get<string>(
      'ALIBABA_CLOUD_ACCESS_KEY_SECRET',
    );
    this.sceneId = this.configService.get<string>('CAPTCHA_SCENE_ID', '');
    this.endpoint = this.configService.get<string>(
      'CAPTCHA_ENDPOINT',
      DEFAULT_ENDPOINT,
    );

    if (accessKeyId && accessKeySecret) {
      const config = new $OpenApiUtil.Config({
        accessKeyId,
        accessKeySecret,
        endpoint: this.endpoint,
        connectTimeout: 5000,
        readTimeout: 10000,
      });
      this.client = new Client(config);
      this.logger.log(
        `阿里云验证码已初始化 (VerifyIntelligentCaptcha, endpoint=${this.endpoint})`,
      );
    } else {
      this.logger.error(
        '缺少 ALIBABA_CLOUD_ACCESS_KEY_ID/SECRET，阿里云验证码不可用',
      );
    }
    if (!this.sceneId) {
      this.logger.error('缺少 CAPTCHA_SCENE_ID，阿里云验证码不可用');
    }
  }

  async verify(token: string): Promise<VerificationResult> {
    if (!token) {
      return { success: false, message: '缺少验证令牌' };
    }
    if (!this.client || !this.sceneId) {
      return { success: false, message: '验证码服务未配置' };
    }

    const startedAt = Date.now();
    try {
      const request = new VerifyIntelligentCaptchaRequest({
        captchaVerifyParam: token, // 原样透传，禁止改动
        sceneId: this.sceneId,
      });

      // 必须设超时：阿里云 SDK 默认可能无限等待，导致 registerV2 请求
      // 挂起直到客户端超时（服务端却无任何日志）
      const response = await this.client.verifyIntelligentCaptcha(request);
      const elapsedMs = Date.now() - startedAt;
      const result = response.body?.result;

      this.logger.log(
        `VerifyIntelligentCaptcha 耗时=${elapsedMs}ms verifyResult=${result?.verifyResult} verifyCode=${result?.verifyCode}`,
      );

      // 以 VerifyResult 为准；VerifyCode 仅用于诊断/提示
      if (result?.verifyResult === true) {
        return { success: true };
      }

      this.logger.warn(
        `阿里云验证码校验失败: verifyCode=${result?.verifyCode}, code=${response.body?.code}, msg=${response.body?.message}`,
      );
      return {
        success: false,
        message: this.translateVerifyCode(result?.verifyCode),
      };
    } catch (err) {
      this.logger.error(
        `阿里云验证码调用异常 (耗时=${Date.now() - startedAt}ms): ${err}`,
      );
      return { success: false, message: '验证码服务异常，请重试' };
    }
  }

  private translateVerifyCode(code?: string): string {
    // 官方 VerifyCode 对照表（帮助中心《服务端接入》），
    // 文案附带原始码便于客户端/用户直接定位问题
    const map: Record<string, string> = {
      F001: '风险校验未通过，请稍后再试(F001)',
      F002: '验证码参数为空，请重新验证(F002)',
      F003: '验证码参数不合法，请重新验证(F003)',
      F004: '验证码测试模式拦截，请检查控制台场景配置(F004)',
      F005: '验证码场景 ID 不合法，请检查接入配置(F005)',
      F006: '验证码场景 ID 不合法，请检查控制台场景配置(F006)',
      F008: '验证码已使用或过期，请重新验证(F008)',
      F009: '设备环境校验未通过，请更换设备或环境后重试(F009)',
      F010: '访问过于频繁，请稍后重试(F010)',
      F011: '操作过于频繁，请稍后重试(F011)',
      F012: '场景配置错误，请检查前后端场景 ID 是否一致(F012)',
      F013: '验证码参数缺失，请重新验证(F013)',
      F014: '验证码会话已失效，请重新验证(F014)',
      F015: '验证交互未通过，请重试(F015)',
      F016: '验证码 URL 校验未通过，请检查控制台 URL 白名单(F016)',
      F017: '风险校验未通过，请稍后再试(F017)',
      F023: '验证码初始化失败，请重试(F023)',
      F024: '检测到模拟操作，请重试(F024)',
      F025: '风险校验未通过，请稍后再试(F025)',
    };
    return map[code ?? ''] ?? `验证码校验失败(${code ?? '未知'})，请重试`;
  }
}
