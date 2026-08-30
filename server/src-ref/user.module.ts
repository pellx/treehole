import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserEntity } from './entities/user.entity';
import { DeviceEntity } from './entities/device.entity';
import { UserDeviceBindingEntity } from './entities/user-device-binding.entity';
import { FingerprintEntity } from './entities/fingerprint.entity';
import { UserIdentifierHistoryEntity } from './entities/user-identifier-history.entity';
import { UserTokenHistoryEntity } from './entities/user-token-history.entity';
import { UserService } from './user.service';
import { UserBindingService } from './user.service.binding';
import { UserLoginService } from './user.service.login';
import { UserProfileService } from './user.service.profile';
import { UserController } from './user.controller';
import { FingerprintService } from './fingerprint/fingerprint.service';
import { SessionGuard } from '../common/guards/session.guard';
import { SmsService } from './sms/sms.service';
import { AliyunSmsAuthSender } from './sms/aliyun-sms.sender';
import { SMS_SENDER } from './sms/sms-sender.interface';
import { VerificationService } from './verification/verification.service';
import { TurnstileStrategy } from './verification/turnstile.strategy';
import { CaptchaStrategy } from './verification/captcha.strategy';
import { PoWStrategy } from './verification/pow.strategy';
import { RedisModule } from '../redis/redis.module';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      UserEntity,
      DeviceEntity,
      UserDeviceBindingEntity,
      FingerprintEntity,
      UserIdentifierHistoryEntity,
      UserTokenHistoryEntity,
    ]),
    RedisModule,
    forwardRef(() => RealtimeModule),
  ],
  controllers: [UserController],
  providers: [
    UserService,
    UserBindingService,
    UserLoginService,
    UserProfileService,
    SessionGuard,
    FingerprintService,
    SmsService,
    {
      provide: SMS_SENDER,
      useClass: AliyunSmsAuthSender,
    },
    TurnstileStrategy,
    CaptchaStrategy,
    PoWStrategy,
    VerificationService,
    {
      provide: 'VERIFICATION_STRATEGIES',
      useFactory: (
        turnstile: TurnstileStrategy,
        pow: PoWStrategy,
        captcha: CaptchaStrategy,
      ) => [turnstile, pow, captcha],
      inject: [TurnstileStrategy, PoWStrategy, CaptchaStrategy],
    },
  ],
  exports: [UserService, UserLoginService, UserBindingService, UserProfileService, SessionGuard, FingerprintService, TypeOrmModule],
})
export class UserModule {}
