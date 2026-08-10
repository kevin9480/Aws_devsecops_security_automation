# ShopEasy API Server (Node.js Express)

## 설치 및 실행

```bash
# 의존성 설치
npm install

# 환경변수 파일 생성
cp .env.example .env

# 시드 데이터 삽입
npm run seed

# 서버 실행 (http://localhost:5000)
npm start

# 개발 모드 실행 (코드 변경시 자동 재시작)
npm run dev
```

## 테스트 계정

| 항목 | 값 |
|------|-----|
| 이메일 | test@test.com |
| 비밀번호 | password123 |

## 환경변수 설명

`.env.example`을 복사하여 `.env` 파일을 생성합니다.

### 서버

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | `5000` | 서버 포트 번호 |

### 데이터베이스

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `DB_TYPE` | `sqlite` | `sqlite` 또는 `mysql` |
| `DB_HOST` | (빈 값) | MySQL 호스트 |
| `DB_PORT` | `3306` | MySQL 포트 |
| `DB_USER` | (빈 값) | MySQL 사용자 |
| `DB_PASSWORD` | (빈 값) | MySQL 비밀번호 |
| `DB_NAME` | `ecommerce` | 데이터베이스 이름 |

### 스토리지

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `STORAGE_TYPE` | `local` | `local` 또는 `s3` |
| `S3_BUCKET` | (빈 값) | S3 버킷 이름 |
| `S3_REGION` | `ap-northeast-2` | S3 리전 |

### 리뷰 저장소

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `REVIEW_STORE` | `local` | `local` 또는 `dynamodb` |
| `DYNAMODB_TABLE` | `Reviews` | DynamoDB 테이블 이름 |
| `DYNAMODB_REGION` | `ap-northeast-2` | DynamoDB 리전 |

### 캐시

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CACHE_TYPE` | `memory` | `memory` 또는 `redis` |
| `REDIS_HOST` | (빈 값) | Redis 호스트 |
| `REDIS_PORT` | `6379` | Redis 포트 |

### 메시지 큐

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `QUEUE_TYPE` | `sync` | `sync` 또는 `sqs` |
| `SQS_QUEUE_URL` | (빈 값) | SQS 큐 URL |
| `SNS_TOPIC_ARN` | (빈 값) | SNS 토픽 ARN |

### 인증

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `JWT_SECRET` | `ecommerce-jwt-secret-key-2024` | JWT 서명 비밀키 |

## API 엔드포인트

인증이 필요한 API는 `Authorization: Bearer <JWT토큰>` 헤더를 포함해야 합니다.

### 인증 (Auth)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| POST | `/api/auth/signup` | - | 회원가입 |
| POST | `/api/auth/login` | - | 로그인 |
| GET | `/api/auth/me` | O | 현재 사용자 정보 조회 |

### 상품 (Products)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| GET | `/api/products` | - | 상품 목록 조회 |
| GET | `/api/products/:id` | - | 상품 상세 조회 |

### 리뷰 (Reviews)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| GET | `/api/products/:id/reviews` | - | 상품 리뷰 목록 조회 |
| POST | `/api/products/:id/reviews` | O | 리뷰 작성 |

### 장바구니 (Cart)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| GET | `/api/cart` | O | 장바구니 조회 |
| POST | `/api/cart` | O | 장바구니에 상품 추가 |
| PUT | `/api/cart/:itemId` | O | 장바구니 수량 변경 |
| DELETE | `/api/cart/:itemId` | O | 장바구니 항목 삭제 |
| DELETE | `/api/cart` | O | 장바구니 전체 삭제 |

### 주문 (Orders)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| POST | `/api/orders` | O | 주문 생성 |
| GET | `/api/orders` | O | 주문 내역 조회 |

### 파일 업로드 (Upload)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| POST | `/api/upload` | O | 이미지 파일 업로드 (최대 5MB) |
| POST | `/api/upload/presigned` | O | S3 Pre-signed URL 생성 |

### 시스템 (Health)

| Method | Path | Auth | 설명 |
|--------|------|:----:|------|
| GET | `/api/health` | - | 서버 상태 확인 |
| GET | `/api/config` | - | 현재 서비스 설정 조회 |
