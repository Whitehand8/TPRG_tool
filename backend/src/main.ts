import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import {
  initializeTransactionalContext,
  StorageDriver,
} from 'typeorm-transactional';
import { addTransactionalDataSource } from 'typeorm-transactional';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { DataSource } from 'typeorm';

async function bootstrap() {
  initializeTransactionalContext({ storageDriver: StorageDriver.AUTO });
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const dataSource = app.get(DataSource);
  addTransactionalDataSource(dataSource);

  try {
    await dataSource.runMigrations({ transaction: 'all' });
  } catch (err) {
    if (
      err.message.includes('migration_history') &&
      err.message.includes('already exists')
    ) {
      // 조용히 무시
    } else {
      console.warn('Migration failed:', err.message);
    }
  }

  const port = configService.get<number>('HTTP_SERVER_PORT', 4000);
  // CORS: 개발 편의상 광범위 허용 (배포 시 특정 도메인으로 좁히세요)
  const extraOrigin = configService.get<string>('FRONTEND_ORIGIN');
  app.enableCors({
    origin: (origin, cb) => {
      // 허용 오리진 화이트리스트
      const whitelist = new Set([
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        // Flutter web dev server (동적 포트): 필요시 아래 두 줄 주석 해제 후 사용
        // 'http://localhost:52759',
        // 'http://192.168.0.10:52759',
      ]);
      if (extraOrigin) whitelist.add(extraOrigin);
      // 개발 편의를 위해 Origin이 없으면(서버-서버, curl) 허용
      if (!origin || whitelist.has(origin)) return cb(null, true);
      // 개발 단계에서는 임시로 모두 허용하려면 다음 라인 사용
      // return cb(null, true);
      cb(new Error(`CORS blocked for origin: ${origin}`));
    },
    methods: ['GET', 'HEAD', 'PUT', 'PATCH', 'POST', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    exposedHeaders: ['Set-Cookie'],
  });
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );

  const config = new DocumentBuilder()
    .setTitle('Echo-Tube-API')
    .setDescription('The echotube API description')
    .setVersion('1.0')
    .addTag('echo-tube')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api-docs', app, document);

  await app.listen(port, '0.0.0.0');
}
bootstrap();