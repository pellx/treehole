import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { CheckLoginDto } from './dto/check.dto';
import { RegisterDto } from './dto/register.dto';
import { RegisterV2Dto } from './dto/register-v2.dto';
import { CaptchaVerifyDto } from './dto/captcha-verify.dto';
import { RenameDto } from './dto/rename.dto';
import { BindingRenameDto } from './dto/binding-rename.dto';
import { BindingDeleteDto } from './dto/binding-delete.dto';
import { PrimaryTransferDto } from './dto/primary-transfer.dto';
import { LoginDto } from './dto/login.dto';
import { BindingCreateDto } from './dto/binding-create.dto';
import { OccupiedCheckDto } from './dto/occupied-check.dto';
import { SessionCreateDto } from './dto/session-create.dto';
import { SessionOnlyDto } from './dto/session-only.dto';
import { SendSmsCodeDto } from './dto/sms-send.dto';
import { SmsRegisterDto } from './dto/sms-register.dto';
import { SmsLoginDto } from './dto/sms-login.dto';
import { SmsBindDto } from './dto/sms-bind.dto';
import { SessionGuard } from '../common/guards/session.guard';
import { UserLoginService } from './user.service.login';
import { UserProfileService } from './user.service.profile';
import { UserBindingService } from './user.service.binding';
import { UserService } from './user.service';

@Controller('user')
export class UserController {
  constructor(
    private readonly userService: UserService,
    private readonly userLoginService: UserLoginService,
    private readonly userProfileService: UserProfileService,
    private readonly userBindingService: UserBindingService,
  ) { }

  // ── 注册 / 登录 ──

  @Get('pow-challenge')
  async getPoWChallenge() {
    return this.userService.getPoWChallenge();
  }

  @Post('check')
  @HttpCode(HttpStatus.OK)
  async check(@Body() dto: CheckLoginDto) {
    return this.userLoginService.checkLogin(dto);
  }

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDto, @Req() req: Request) {
    return this.userLoginService.register(dto, req.ip);
  }

  /** 注册 v2（阿里云验证码）；v1（Turnstile）保持不变 */
  @Post('captcha/verify')
  @HttpCode(HttpStatus.OK)
  async verifyCaptcha(@Body() dto: CaptchaVerifyDto) {
    return this.userLoginService.verifyCaptchaTicket(dto.captcha_verify_param);
  }

  @Post('registerV2')
  @HttpCode(HttpStatus.CREATED)
  async registerV2(@Body() dto: RegisterV2Dto) {
    return this.userLoginService.registerV2(dto);
  }

  // ── 手机号验证码 ──

  /** 发送短信验证码 */
  @Post('sms/send')
  @HttpCode(HttpStatus.OK)
  async sendSmsCode(@Body() dto: SendSmsCodeDto, @Req() req: Request) {
    return this.userLoginService.sendSmsCode(dto, req.ip);
  }

  /** 手机号验证码注册（新账号）：一步建号 + 建绑 */
  @Post('sms/register')
  @HttpCode(HttpStatus.CREATED)
  async smsRegister(@Body() dto: SmsRegisterDto, @Req() req: Request) {
    return this.userLoginService.smsRegister(dto, req.ip);
  }

  /** 手机号验证码登录（已存在账号）：直接签发 session */
  @Post('sms/login')
  @HttpCode(HttpStatus.OK)
  async smsLogin(@Body() dto: SmsLoginDto) {
    return this.userLoginService.smsLogin(dto);
  }

  /** 当前 session 用户绑定/换绑手机号 */
  @Post('sms/bind')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async smsBind(
    @Body() dto: SmsBindDto,
    @Req() req: Request & { user_id: number },
  ) {
    return this.userLoginService.smsBind(req.user_id, dto);
  }

  /** 建绑并轮换 device_secret（不签发 session） */
  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return this.userLoginService.login(dto);
  }

  // ── session/* ──

  /** 唯一签发 session 入口；切号成功时写 2 天 device_owner 锁 */
  @Post('session/create')
  @HttpCode(HttpStatus.CREATED)
  async createSession(@Body() dto: SessionCreateDto) {
    return this.userLoginService.createSession(dto);
  }

  @Post('session/validate')
  @HttpCode(HttpStatus.OK)
  async validateSessionEndpoint(@Body() dto: SessionOnlyDto) {
    return this.userLoginService.validateSessionEndpoint(dto);
  }

  // ── 账户资料 ──

  @Post('profile')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async getProfile(@Body() _dto: SessionOnlyDto, @Req() req: Request & { user_id: number }) {
    return this.userProfileService.getProfile(req.user_id);
  }

  @Post('rename')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async rename(@Body() dto: RenameDto, @Req() req: Request & { user_id: number }) {
    return this.userProfileService.rename(req.user_id, dto.new_name);
  }

  @Post('token/reset')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async resetToken(@Body() _dto: SessionOnlyDto, @Req() req: Request & { user_id: number }) {
    return this.userProfileService.resetToken(req.user_id);
  }

  // ── 列表查询 ──

  /** 当前账户绑定的所有设备 */
  @Post('devices2user')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async devices2user(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { user_id: number },
  ) {
    return this.userBindingService.listDevicesForUser(req.user_id);
  }

  /** 当前设备绑定的所有账户 */
  @Post('user2device')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async user2device(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userBindingService.listUsersForDevice(req.device_id);
  }

  // ── binding/* ──

  /** 建绑并校验现有 device_secret（不轮换、不签发 session） */
  @Post('binding/create')
  @HttpCode(HttpStatus.OK)
  async bindingCreate(@Body() dto: BindingCreateDto) {
    return this.userLoginService.bindingCreate(dto);
  }

  /** 按 user_token（含历史）返回活绑定设备数 */
  @Post('binding/occupied')
  @HttpCode(HttpStatus.OK)
  async bindingOccupied(@Body() dto: OccupiedCheckDto) {
    return this.userLoginService.checkOccupied(dto);
  }

  /** 本机上次切号时间（session 定位设备；无切号锁则 switched_at 为 null） */
  @Post('binding/last-switch')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingLastSwitch(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userLoginService.getLastSwitch(req.device_id);
  }

  /** 同 binding/last-switch（客户端约定路径） */
  @Post('session/last-switch')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async sessionLastSwitch(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userLoginService.getLastSwitch(req.device_id);
  }

  /**
   * 在已绑定本机上发起跨设备绑定转移申请（15 分钟有效）。
   * 新设备须在有效期内调用 /user/login 或 /user/binding/create 完成绑定。
   */
  @Post('binding/transfer-request')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingTransferRequest(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { user_id: number; device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userBindingService.createTransferRequest(req.user_id, req.device_id);
  }

  /** 修改绑定设备显示名 */
  @Post('binding/rename')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingRename(
    @Body() dto: BindingRenameDto,
    @Req() req: Request & { user_id: number },
  ) {
    return this.userBindingService.renameDevice(req.user_id, dto.id, dto.new_name);
  }

  /** 删除设备绑定（主设备禁止；本机 2 小时等待；其他非主设备立刻解绑） */
  @Post('binding/delete')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingDelete(
    @Body() dto: BindingDeleteDto,
    @Req() req: Request & { user_id: number; device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userBindingService.deleteBinding(
      req.user_id,
      dto.id,
      req.device_id,
      req.ip,
    );
  }

  /** 取消解绑申请 */
  @Post('binding/delete-cancel')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingDeleteCancel(
    @Body() dto: BindingDeleteDto,
    @Req() req: Request & { user_id: number },
  ) {
    return this.userBindingService.cancelDeleteBinding(req.user_id, dto.id);
  }

  /**
   * 申请迁移主设备到目标绑定设备（2 天后生效；已有主设备时须在主设备上发起）。
   * body.id = 目标 user_device_binding.id
   */
  @Post('binding/primary-transfer')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingPrimaryTransfer(
    @Body() dto: PrimaryTransferDto,
    @Req() req: Request & { user_id: number; device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userBindingService.requestPrimaryTransfer(
      req.user_id,
      dto.id,
      req.device_id,
    );
  }

  /** 取消未生效的主设备迁移（须在主设备 session 上，若已有主设备） */
  @Post('binding/primary-transfer-cancel')
  @HttpCode(HttpStatus.OK)
  @UseGuards(SessionGuard)
  async bindingPrimaryTransferCancel(
    @Body() _dto: SessionOnlyDto,
    @Req() req: Request & { user_id: number; device_id: number },
  ) {
    if (req.device_id == null) {
      throw new UnauthorizedException('SESSION_INVALID');
    }
    return this.userBindingService.cancelPrimaryTransfer(req.user_id, req.device_id);
  }
}
