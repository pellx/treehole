import {
  BadRequestException,
  Inject,
  Injectable,
  UnauthorizedException,
  forwardRef,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { QueryFailedError, Repository, In } from 'typeorm';
import { createHash, randomBytes, randomUUID } from 'crypto';
import * as bcrypt from 'bcrypt';
import { CheckLoginDto } from './dto/check.dto';
import { RegisterDto } from './dto/register.dto';
import { RegisterV2Dto } from './dto/register-v2.dto';
import { DeviceFingerprintDto } from './dto/fingerprint.dto';
import { LoginDto } from './dto/login.dto';
import { BindingCreateDto } from './dto/binding-create.dto';
import { OccupiedCheckDto } from './dto/occupied-check.dto';
import { SessionCreateDto } from './dto/session-create.dto';
import { SessionOnlyDto } from './dto/session-only.dto';
import { SendSmsCodeDto } from './dto/sms-send.dto';
import { SmsRegisterDto } from './dto/sms-register.dto';
import { SmsLoginDto } from './dto/sms-login.dto';
import { SmsBindDto } from './dto/sms-bind.dto';
import { SmsService } from './sms/sms.service';
import { DeviceEntity } from './entities/device.entity';
import { FingerprintEntity } from './entities/fingerprint.entity';
import { UserDeviceBindingEntity } from './entities/user-device-binding.entity';
import { UserEntity } from './entities/user.entity';
import { UserIdentifierHistoryEntity } from './entities/user-identifier-history.entity';
import { UserTokenHistoryEntity } from './entities/user-token-history.entity';
import { FingerprintService } from './fingerprint/fingerprint.service';
import { PoWStrategy } from './verification/pow.strategy';
import { VerificationService } from './verification/verification.service';
import { TurnstileStrategy } from './verification/turnstile.strategy';
import { UserBindingService } from './user.service.binding';
import { UserService } from './user.service';
import { RedisService } from '../redis/redis.service';
import { RealtimeService } from '../realtime/realtime.service';

const SESSION_TTL_S = 3 * 24 * 60 * 60;
const DEVICE_OWNER_TTL_S = 2 * 24 * 60 * 60;
const RATE_LIMIT_COUNT = 8;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class UserLoginService {
  constructor(
    @InjectRepository(FingerprintEntity)
    private readonly fingerprintRepo: Repository<FingerprintEntity>,
    @InjectRepository(DeviceEntity)
    private readonly deviceRepo: Repository<DeviceEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepo: Repository<UserEntity>,
    @InjectRepository(UserDeviceBindingEntity)
    private readonly bindingRepo: Repository<UserDeviceBindingEntity>,
    private readonly fingerprintService: FingerprintService,
    private readonly userBindingService: UserBindingService,
    private readonly userService: UserService,
    private readonly configService: ConfigService,
    private readonly verificationService: VerificationService,
    private readonly turnstileStrategy: TurnstileStrategy,
    private readonly powStrategy: PoWStrategy,
    private readonly redisService: RedisService,
    private readonly smsService: SmsService,
    @Inject(forwardRef(() => RealtimeService))
    private readonly realtimeService: RealtimeService,
  ) { }

  // ── PoW ──

  /** 获取一次性 PoW 挑战 */
  async getPoWChallenge(difficulty?: number) {
    return this.powStrategy.createChallenge(difficulty);
  }

  // ── 指纹查询 ──

  /** 检查设备指纹是否已注册 */
  async checkLogin(dto: CheckLoginDto): Promise<{ registered: boolean }> {
    const fingerprint = this.userService.toFingerprintEntity(dto.device_finger_print);
    const fingerprintHash = this.fingerprintService.computeHardwareHash(fingerprint);
    const registered = await this.fingerprintRepo.exists({
      where: { fingerprint_hash: fingerprintHash },
    });
    return { registered };
  }

  // ── 注册 ──

  /** 创建用户与设备（需 PoW + Turnstile）；不建绑，须再 login / binding/create */
  async register(dto: RegisterDto, remoteIp?: string): Promise<{
    user_token: string;
    device_secret: string;
  }> {
    const turnstileResult = await this.verificationService.verify(
      'turnstile', dto.verification_turnstile, remoteIp,
    );
    if (!turnstileResult.success) {
      throw new BadRequestException(turnstileResult.message ?? 'Turnstile 验证失败');
    }

    const powValid = await this.powStrategy.verify(
      dto.verification_pow.challenge_id, dto.verification_pow.nonce,
    );
    if (!powValid) throw new BadRequestException('PoW 验证失败');

    const result = await this.createUserAndDevice(dto);

    // 仅注册成功后使 Turnstile / PoW 失效；失败时均可在 TTL 内重试
    await this.turnstileStrategy.consume(dto.verification_turnstile);
    await this.powStrategy.consume(dto.verification_pow.challenge_id);

    return result;
  }

  /**
   * 注册 v2：阿里云验证码（无痕验证）。
   * captchaVerifyParam 一次性（复用/过期返回 F008），无需 consume；
   * 与 v1 共用建号逻辑，v1 的 Turnstile 流程不受影响。
   */
  async registerV2(dto: RegisterV2Dto): Promise<{
    user_token: string;
    device_secret: string;
  }> {
    // 凭证模式：通过测试页即时校验后签发的 Redis ticket（注册失败可复用，
    // 仅注册成功后销毁）；否则回退为直接校验 captchaVerifyParam（旧客户端）
    let captchaTicket: string | null = null;
    if (dto.verification_captcha_ticket) {
      const exists = await this.redisService.client.exists(
        `captcha:ticket:${dto.verification_captcha_ticket}`,
      );
      if (exists !== 1) {
        throw new BadRequestException('验证码已使用或过期，请重新验证');
      }
      captchaTicket = dto.verification_captcha_ticket;
    } else {
      const captchaResult = await this.verificationService.verify(
        'captcha',
        dto.verification_captcha ?? '',
      );
      if (!captchaResult.success) {
        throw new BadRequestException(captchaResult.message ?? '验证码验证失败');
      }
    }

    const powValid = await this.powStrategy.verify(
      dto.verification_pow.challenge_id,
      dto.verification_pow.nonce,
    );
    if (!powValid) throw new BadRequestException('PoW 验证失败');

    const result = await this.createUserAndDevice(dto);

    // 仅使 PoW 失效（captcha token 一次性，无需缓存/consume）
    await this.powStrategy.consume(dto.verification_pow.challenge_id);
    // 注册成功才销毁验证凭证
    if (captchaTicket) {
      await this.redisService.client.del(`captcha:ticket:${captchaTicket}`);
    }

    return result;
  }

  /**
   * 通过测试页即时校验阿里云验证码，通过后签发 Redis 凭证
   * （captcha:ticket:<uuid>，10 分钟有效）。注册时以
   * verification_captcha_ticket 提交，避免注册时刻重复调阿里云，
   * 且 F001 等风控结论当场可见。
   */
  async verifyCaptchaTicket(captchaVerifyParam: string) {
    const result = await this.verificationService.verify(
      'captcha',
      captchaVerifyParam,
    );
    if (!result.success) {
      throw new BadRequestException(result.message ?? '验证码验证失败');
    }
    const ticket = randomUUID();
    await this.redisService.client.set(
      `captcha:ticket:${ticket}`,
      '1',
      'EX',
      600,
    );
    return { captcha_ticket: ticket };
  }

  /**
   * 指纹冲突检查 + 事务插入建号，注册 v1/v2/sms 共用。
   * - Android：fingerprint_hash 全局唯一；sms 注册（create_binding）命中时
   *   复用既有设备建新号（轮换 secret），其余场景拒绝
   * - iOS：允许同一 fingerprint_hash 在不同用户下重复
   * 可选同时建绑（手机号注册一步完成）。
   */
  private async createUserAndDevice(dto: {
    user_display_id: string;
    device_finger_print: DeviceFingerprintDto;
    phone?: string;
    create_binding?: boolean;
  }): Promise<{ user_token: string; device_secret: string }> {
    const fingerprint = this.userService.toFingerprintEntity(
      dto.device_finger_print,
    );
    const fingerprintHash =
      this.fingerprintService.computeHardwareHash(fingerprint);

    // Android 保持全局唯一；iOS 放宽，按 (user_id, fingerprint_hash) 区分。
    // 手机号注册（create_binding）命中已有指纹时不拒绝：引导页「注册新账号」
    // 只会出现在设备已注册的状态下，改为复用既有设备建新号并轮换 secret。
    let reuseDeviceId: number | null = null;
    if (fingerprint.platform !== 'ios') {
      const exists = await this.fingerprintRepo.findOne({
        where: { fingerprint_hash: fingerprintHash },
      });
      if (exists) {
        if (!dto.create_binding) throw new BadRequestException('该设备环境已注册');
        const device = await this.deviceRepo.findOne({
          where: { device_id: exists.device_id },
        });
        if (!device) throw new BadRequestException('该设备环境已注册');
        reuseDeviceId = device.device_id;
      }
    }

    // 昵称不得与其他用户当前名或历史名冲突
    await this.userService.assertDisplayIdAvailable(dto.user_display_id);
    await this.userService.assertDisplayIdModerated(dto.user_display_id);

    // 手机号注册时校验手机号可用
    if (dto.phone) {
      await this.userService.assertPhoneAvailable(dto.phone);
    }

    const deviceSecret = this.generateDeviceSecret();
    const pepper = this.configService.get<string>('DEVICE_SECRET_HASH_KEY', '');
    const deviceSecretHash = await bcrypt.hash(deviceSecret + pepper, 10);
    const userToken = await this.userService.generateUniqueUserToken();

    try {
      await this.deviceRepo.manager.transaction(async (manager) => {
        let deviceId: number;
        if (reuseDeviceId != null) {
          // 复用既有设备：不新增 device/fingerprint 行，轮换 device_secret
          //（本机新账户接管；secret 属设备维度，不影响其他设备上的账户）
          await manager.update(
            DeviceEntity,
            { device_id: reuseDeviceId },
            { device_secret_hash: deviceSecretHash },
          );
          deviceId = reuseDeviceId;
        } else {
          const deviceResult = await manager.insert(DeviceEntity, {
            device_secret_hash: deviceSecretHash,
            fingerprint_hash: fingerprintHash,
          });
          deviceId = deviceResult.identifiers[0].device_id as number;

          fingerprint.device_id = deviceId;
          fingerprint.fingerprint_hash = fingerprintHash;
          await manager.save(FingerprintEntity, fingerprint);
        }

        const userResult = await manager.insert(UserEntity, {
          user_token: userToken,
          user_display_id: dto.user_display_id.trim(),
          phone: dto.phone ? this.userService.normalizePhone(dto.phone) : null,
          primary_device_id: deviceId,
          // 不写 changed_at（库默认 null）：注册后首次改名不受两周冷却
        });
        const userId = userResult.identifiers[0].user_id as number;

        await manager.insert(UserIdentifierHistoryEntity, {
          user_id: userId,
          type: 'display_id',
          value: dto.user_display_id.trim(),
        });

        // 每次签发的 token 都写入 history（含注册时的首个 token）
        await manager.insert(UserTokenHistoryEntity, {
          user_id: userId,
          user_token: userToken,
        });

        // 手机号注册：一步完成建绑
        if (dto.create_binding) {
          await this.userBindingService.bindUserToDevice(manager, userId, deviceId);
        }
      });
    } catch (error) {
      if (this.isFingerprintConflict(error)) {
        throw new BadRequestException('该设备环境已注册');
      }
      throw error;
    }

    return { user_token: userToken, device_secret: deviceSecret };
  }

  // ── 手机号验证码 ──

  /** 发送短信验证码 */
  async sendSmsCode(
    dto: SendSmsCodeDto,
    remoteIp?: string,
  ): Promise<{ sent: boolean; cooldown_seconds: number }> {
    return this.smsService.sendCode(dto, remoteIp);
  }

  /** 手机号验证码注册：一步完成建号 + 建绑 */
  async smsRegister(
    dto: SmsRegisterDto,
    remoteIp?: string,
  ): Promise<{ user_token: string; device_secret: string }> {
    // 与 registerV2 一致走阿里云验证码（captcha token 一次性，无需 consume）
    const captchaResult = await this.verificationService.verify(
      'captcha', dto.verification_captcha, remoteIp,
    );
    if (!captchaResult.success) {
      throw new BadRequestException(captchaResult.message ?? '验证码验证失败');
    }

    const powValid = await this.powStrategy.verify(
      dto.verification_pow.challenge_id, dto.verification_pow.nonce,
    );
    if (!powValid) throw new BadRequestException('PoW 验证失败');

    await this.smsService.verifyCode(dto.phone, 'register', dto.code);

    const result = await this.createUserAndDevice({
      user_display_id: dto.user_display_id,
      device_finger_print: dto.device_finger_print,
      phone: dto.phone,
      create_binding: true,
    });

    await this.powStrategy.consume(dto.verification_pow.challenge_id);

    return result;
  }

  /**
   * 手机号验证码登录：直接签发 session。
   * 未注册手机号存在找回路径：见 recoverUserByFingerprint。
   * 响应携带 user_token，客户端据此登记本机账户令牌（切号/failover 依赖）。
   */
  async smsLogin(dto: SmsLoginDto): Promise<{
    session_id: number;
    session_secret: string;
    user_token: string;
  }> {
    await this.smsService.verifyCode(dto.phone, 'login', dto.code);

    let user = await this.userService.findUserByPhone(dto.phone);
    if (!user) {
      user = await this.recoverUserByFingerprint(dto.phone, dto.fingerprint_hash);
    }
    if (!user) throw new UnauthorizedException('USER_NOT_FOUND');

    const device = await this.resolveDeviceForUser(user.user_id, dto.fingerprint_hash);

    await this.assertDeviceOwnerAllowed(user.user_id, device.device_id);

    // 自动建绑（新设备或解绑后重新登录）
    await this.userBindingService.ensureLiveBinding(user.user_id, device.device_id);

    // 轮换 device_secret
    const deviceSecret = this.generateDeviceSecret();
    const pepper = this.configService.get<string>('DEVICE_SECRET_HASH_KEY', '');
    const deviceSecretHash = await bcrypt.hash(deviceSecret + pepper, 10);
    await this.deviceRepo.update(
      { device_id: device.device_id },
      { device_secret_hash: deviceSecretHash },
    );

    const { session } = await this.issueSession(user.user_id, device.device_id);

    return { ...session, user_token: user.user_token };
  }

  /**
   * 未注册手机号的账户找回：
   * 本机指纹对应的活绑定账户中，若恰好只有一个从未绑定过手机号的账户，
   * 则视为找回该账户，并把该手机号绑定为账户手机号（到此处短信验证码已通过，
   * 且全库无任何用户占用该手机号）。候选为 0 个或多个时保持 USER_NOT_FOUND，
   * 前者是无匹配设备，后者是无法消歧——已绑手机的账户仍须用绑定手机号找回。
   */
  private async recoverUserByFingerprint(
    phone: string,
    fingerprintHash: string,
  ): Promise<UserEntity | null> {
    const fps = await this.fingerprintRepo.find({
      where: { fingerprint_hash: fingerprintHash },
    });
    if (fps.length === 0) return null;

    const bindings = await this.bindingRepo.find({
      where: {
        device_id: In(fps.map((fp) => fp.device_id)),
        status: In(['active', 'unbind_pending']),
      },
    });
    const userIds = [...new Set(bindings.map((b) => b.user_id))];
    if (userIds.length === 0) return null;

    const users = await this.userRepo.find({ where: { user_id: In(userIds) } });
    const candidates = users.filter((u) => !u.phone);
    if (candidates.length !== 1) return null;

    const user = candidates[0];
    const normalized = this.userService.normalizePhone(phone);
    await this.userRepo.update(
      { user_id: user.user_id },
      { phone: normalized },
    );
    user.phone = normalized;
    return user;
  }

  /** 当前 session 用户绑定/换绑手机号 */
  async smsBind(userId: number, dto: SmsBindDto): Promise<{ phone: string }> {
    await this.smsService.verifyCode(dto.phone, 'bind', dto.code);
    await this.userService.assertPhoneAvailable(dto.phone, userId);

    const normalized = this.userService.normalizePhone(dto.phone);
    await this.userRepo.update({ user_id: userId }, { phone: normalized });

    return { phone: normalized };
  }

  // ── 会话 ──

  /** 验证 session 是否有效，返回 user_id + device_id */
  async validateSession(
    sessionId: number,
    sessionSecret: string,
  ): Promise<{ user_id: number; device_id: number }> {
    const raw = await this.redisService.client.get(`session:${sessionId}`);
    if (!raw) throw new UnauthorizedException('SESSION_INVALID');

    const data = JSON.parse(raw);
    const hash = createHash('sha256').update(sessionSecret).digest('hex');
    if (hash !== data.session_secret_hash) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    if (data.user_id == null || data.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return { user_id: data.user_id, device_id: data.device_id };
  }

  /**
   * 用 user_token + device_secret + fingerprint_hash 申请 session。
   * 按指纹定位本机，校验该 user+device 活绑定；切号成功时写 2 天 device_owner。
   */
  async createSession(dto: SessionCreateDto): Promise<{ session_id: number; session_secret: string }> {
    const { user, device } = await this.resolveUserAndDevice(
      dto.user_token,
      dto.fingerprint_hash,
    );

    await this.assertDeviceSecret(device, dto.device_secret);

    const binding = await this.bindingRepo.findOne({
      where: {
        user_id: user.user_id,
        device_id: device.device_id,
        status: In(['active', 'unbind_pending']),
      },
    });
    if (!binding) throw new UnauthorizedException('DEVICE_NOT_BOUND');

    await this.assertDeviceOwnerAllowed(user.user_id, device.device_id);

    const { session, switched, previous_session_id, previous_user_id } =
      await this.issueSession(user.user_id, device.device_id);

    if (switched) {
      // 切号：本机旧账户 session 已在 issueSession 中删除；写 2 天锁并清理遗留 by_user 索引
      await this.redisService.client.set(
        this.deviceOwnerKey(device.device_id),
        JSON.stringify({
          user_id: user.user_id,
          switched_at: new Date().toISOString(),
        }),
        'EX',
        DEVICE_OWNER_TTL_S,
      );
      if (previous_user_id != null && previous_session_id != null) {
        await this.clearLegacyByUserIndex(previous_user_id, previous_session_id);
      }
    }
    return session;
  }

  /**
   * 建绑并轮换 device_secret；不签发 session。
   * 本机尚无 secret / 丢失 / 主动轮换时使用。
   */
  async login(dto: LoginDto): Promise<{
    device_secret: string;
    binding_id: number;
    device_id: number;
  }> {
    const { user, device } = await this.resolveUserAndDevice(
      dto.user_token,
      dto.fingerprint_hash,
    );

    await this.assertDeviceOwnerAllowed(user.user_id, device.device_id);

    const binding = await this.userBindingService.ensureLiveBinding(
      user.user_id,
      device.device_id,
    );

    const deviceSecret = this.generateDeviceSecret();
    const pepper = this.configService.get<string>('DEVICE_SECRET_HASH_KEY', '');
    const deviceSecretHash = await bcrypt.hash(deviceSecret + pepper, 10);
    await this.deviceRepo.update(
      { device_id: device.device_id },
      { device_secret_hash: deviceSecretHash },
    );

    return {
      device_secret: deviceSecret,
      binding_id: binding.id,
      device_id: device.device_id,
    };
  }

  /**
   * 建绑并校验现有 device_secret；不轮换、不签发 session。
   * 本机已有有效 secret、再绑另一账户时使用。
   */
  async bindingCreate(dto: BindingCreateDto): Promise<{
    binding_id: number;
    device_id: number;
  }> {
    const { user, device } = await this.resolveUserAndDevice(
      dto.user_token,
      dto.fingerprint_hash,
    );

    await this.assertDeviceSecret(device, dto.device_secret);
    await this.assertDeviceOwnerAllowed(user.user_id, device.device_id);

    const binding = await this.userBindingService.ensureLiveBinding(
      user.user_id,
      device.device_id,
    );

    return {
      binding_id: binding.id,
      device_id: device.device_id,
    };
  }

  /** 按 user_token（含历史）返回该用户活绑定设备数 */
  async checkOccupied(dto: OccupiedCheckDto): Promise<{ device_count: number }> {
    const user = await this.userService.findUserByTokenIncludingHistory(dto.user_token);
    if (!user) throw new UnauthorizedException('USER_NOT_FOUND');

    const device_count = await this.bindingRepo.count({
      where: {
        user_id: user.user_id,
        status: In(['active', 'unbind_pending']),
      },
    });
    return { device_count };
  }

  /** 本机上次切号时间（来自 device_owner；无锁则 null） */
  async getLastSwitch(deviceId: number): Promise<{
    switched_at: string | null;
    owner_user_id: number | null;
    expires_at: string | null;
  }> {
    const key = this.deviceOwnerKey(deviceId);
    const raw = await this.redisService.client.get(key);
    if (!raw) {
      return { switched_at: null, owner_user_id: null, expires_at: null };
    }

    const parsed = this.parseDeviceOwner(raw);
    if (!parsed) {
      return { switched_at: null, owner_user_id: null, expires_at: null };
    }

    const ttl = await this.redisService.client.ttl(key);
    let expires_at: string | null = null;
    if (ttl > 0) {
      expires_at = new Date(Date.now() + ttl * 1000).toISOString();
    }

    return {
      switched_at: parsed.switched_at,
      owner_user_id: parsed.user_id,
      expires_at,
    };
  }

  /** 用 user_token + fingerprint_hash 解析用户与本机设备 */
  private async resolveUserAndDevice(
    userToken: string,
    fingerprintHash: string,
  ): Promise<{ user: UserEntity; device: DeviceEntity }> {
    const user = await this.userRepo.findOne({
      where: { user_token: userToken },
    });
    if (!user) throw new UnauthorizedException('USER_NOT_FOUND');

    const device = await this.resolveDeviceForUser(user.user_id, fingerprintHash);
    return { user, device };
  }

  /**
   * 在指定用户的绑定范围内定位设备；兼容 iOS fingerprint_hash 重复场景。
   * 优先找与该用户有活绑定的设备；若全局仅有一台该指纹设备，也允许使用（兼容 Android）。
   */
  private async resolveDeviceForUser(
    userId: number,
    fingerprintHash: string,
  ): Promise<DeviceEntity> {
    const fps = await this.fingerprintRepo.find({
      where: { fingerprint_hash: fingerprintHash },
    });
    if (fps.length === 0) throw new UnauthorizedException('FINGERPRINT_MISMATCH');

    const deviceIds = fps.map((fp) => fp.device_id);
    const devices = await this.deviceRepo.find({
      where: { device_id: In(deviceIds) },
    });

    // 优先：该用户已绑定的设备（iOS 多用户同指纹时必不可少）
    const bindings = await this.bindingRepo.find({
      where: {
        user_id: userId,
        device_id: In(deviceIds),
        status: In(['active', 'unbind_pending']),
      },
    });
    const boundDeviceIds = new Set(bindings.map((b) => b.device_id));
    const boundDevice = devices.find((d) => boundDeviceIds.has(d.device_id));
    if (boundDevice) return boundDevice;

    // 兼容：全局只有一台该指纹设备（传统 Android 唯一场景）
    if (devices.length === 1) {
      return devices[0];
    }

    throw new UnauthorizedException('FINGERPRINT_MISMATCH');
  }

  /** 校验 session_id + session_secret，返回 user_id */
  async validateSessionEndpoint(dto: SessionOnlyDto): Promise<{ valid: boolean; user_id: number }> {
    const session = await this.validateSession(dto.session_id, dto.session_secret);
    return { valid: true, user_id: session.user_id };
  }

  // ── 内部工具 ──

  private sessionByDeviceKey(deviceId: number): string {
    return `session:by_device:${deviceId}`;
  }

  private deviceOwnerKey(deviceId: number): string {
    return `session:device_owner:${deviceId}`;
  }

  /** 切号锁：存在且非本人则拒绝 */
  private async assertDeviceOwnerAllowed(userId: number, deviceId: number): Promise<void> {
    const raw = await this.redisService.client.get(this.deviceOwnerKey(deviceId));
    if (!raw) return;
    const parsed = this.parseDeviceOwner(raw);
    if (parsed && parsed.user_id !== userId) {
      throw new BadRequestException('DEVICE_SESSION_LOCKED');
    }
  }

  /** 解析 device_owner：新格式 JSON，或旧格式纯 user_id 字符串 */
  private parseDeviceOwner(raw: string): { user_id: number; switched_at: string | null } | null {
    try {
      const data = JSON.parse(raw) as { user_id?: unknown; switched_at?: unknown };
      if (data != null && typeof data === 'object' && data.user_id != null) {
        return {
          user_id: Number(data.user_id),
          switched_at: typeof data.switched_at === 'string' ? data.switched_at : null,
        };
      }
    } catch {
      // legacy: plain user id
    }
    const userId = Number(raw);
    if (!Number.isFinite(userId)) return null;
    return { user_id: userId, switched_at: null };
  }

  private async assertDeviceSecret(device: DeviceEntity, deviceSecret: string): Promise<void> {
    const pepper = this.configService.get<string>('DEVICE_SECRET_HASH_KEY', '');
    const secretMatch = await bcrypt.compare(deviceSecret + pepper, device.device_secret_hash);
    if (!secretMatch) throw new UnauthorizedException('DEVICE_SECRET_INVALID');
  }

  /**
   * 签发 session（含限流）。
   * 写入 session:{id}，维护 session:by_device；
   * 若本机已有旧 session 则删除（同用户续签与切号均踢掉本机旧凭证）。
   * switched=true 表示踢掉的是另一用户的 session（切号）。
   */
  private async issueSession(
    userId: number,
    deviceId: number,
  ): Promise<{
    session: { session_id: number; session_secret: string };
    switched: boolean;
    previous_session_id: string | null;
    previous_user_id: number | null;
  }> {
    await this.checkRateLimit('user', String(userId));
    await this.checkRateLimit('device', String(deviceId));

    const sessionSecret = this.generateSessionSecret();
    const sessionSecretHash = createHash('sha256').update(sessionSecret).digest('hex');
    const sessionId = await this.redisService.client.incr('session:counter');
    const byDeviceKey = this.sessionByDeviceKey(deviceId);

    let switched = false;
    let previousSessionId: string | null = null;
    let previousUserId: number | null = null;

    const existingSessionId = await this.redisService.client.get(byDeviceKey);
    if (existingSessionId) {
      previousSessionId = existingSessionId;
      const prevRaw = await this.redisService.client.get(`session:${existingSessionId}`);
      if (prevRaw) {
        try {
          const prev = JSON.parse(prevRaw);
          if (prev.user_id != null) {
            previousUserId = Number(prev.user_id);
            if (previousUserId !== userId) {
              switched = true;
            }
          }
        } catch {
          // 脏数据：仍删除旧 session
        }
      }
      // 本机原 session 一律作废（切号/续签均删掉旧凭证）
      await this.redisService.client.del(`session:${existingSessionId}`);
      if (previousUserId != null) {
        this.realtimeService.notifySessionInvalidated({
          user_id: previousUserId,
          device_id: deviceId,
          reason: 'replaced',
          at: new Date().toISOString(),
        });
      }
    }

    await this.redisService.client.set(
      `session:${sessionId}`,
      JSON.stringify({
        session_secret_hash: sessionSecretHash,
        user_id: userId,
        device_id: deviceId,
      }),
      'EX',
      SESSION_TTL_S,
    );
    await this.redisService.client.set(byDeviceKey, String(sessionId), 'EX', SESSION_TTL_S);

    await this.recordRateLimit('user', String(userId));
    await this.recordRateLimit('device', String(deviceId));

    return {
      session: { session_id: Number(sessionId), session_secret: sessionSecret },
      switched,
      previous_session_id: previousSessionId,
      previous_user_id: previousUserId,
    };
  }

  /** 若遗留 session:by_user 仍指向已删的本机会话，则清掉 */
  private async clearLegacyByUserIndex(userId: number, sessionId: string): Promise<void> {
    const key = `session:by_user:${userId}`;
    const indexed = await this.redisService.client.get(key);
    if (indexed === sessionId) {
      await this.redisService.client.del(key);
    }
  }

  /** 检测 MySQL 指纹哈希唯一索引冲突 */
  private isFingerprintConflict(error: unknown): boolean {
    if (!(error instanceof QueryFailedError)) return false;
    const d = error.driverError as { code?: string; message?: string };
    return d.code === 'ER_DUP_ENTRY' && d.message?.includes('uk_fingerprints_hash') === true;
  }

  /** 滑动窗口 session 申请限流检查 */
  private async checkRateLimit(subjectType: string, subjectId: string): Promise<void> {
    const key = `ratelimit:${subjectType}:${subjectId}:session_application`;
    await this.redisService.client.zremrangebyscore(key, 0, Date.now() - RATE_LIMIT_WINDOW_MS);
    if (await this.redisService.client.zcard(key) >= RATE_LIMIT_COUNT) {
      throw new BadRequestException('RATE_LIMITED');
    }
  }

  /** 记录一次 session 申请（滑动窗口） */
  private async recordRateLimit(subjectType: string, subjectId: string): Promise<void> {
    const key = `ratelimit:${subjectType}:${subjectId}:session_application`;
    const now = Date.now();
    await this.redisService.client.zadd(key, now, `${now}:${randomBytes(4).toString('hex')}`);
    await this.redisService.client.expire(key, Math.ceil(RATE_LIMIT_WINDOW_MS / 1000));
  }

  private generateDeviceSecret(): string { return randomBytes(32).toString('hex'); }
  private generateSessionSecret(): string { return randomBytes(32).toString('hex'); }
}
