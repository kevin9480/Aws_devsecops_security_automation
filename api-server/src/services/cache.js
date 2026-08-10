/**
 * 캐시 서비스 추상화
 * - memory 모드: 인메모리 Map 사용 (로컬 개발용)
 * - redis 모드: AWS ElastiCache (Redis) 사용
 */

const CACHE_TYPE = process.env.CACHE_TYPE || 'memory';

// ========================================
// 인메모리 캐시 구현
// ========================================

// 메모리 캐시 저장소: { key: { value, expireAt } }
const memoryCache = new Map();

/**
 * 만료된 항목 자동 정리 (1분마다)
 */
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of memoryCache) {
    if (entry.expireAt && entry.expireAt < now) {
      memoryCache.delete(key);
    }
  }
}, 60 * 1000);

// ========================================
// Redis 클라이언트 (lazy initialization)
// ========================================

let redisClient = null;

function getRedisClient() {
  if (!redisClient) {
    const Redis = require('ioredis');
    redisClient = new Redis({
      host: process.env.REDIS_HOST || 'localhost',
      port: parseInt(process.env.REDIS_PORT) || 6379,
      retryStrategy(times) {
        // 최대 3번 재시도, 간격 2초
        if (times > 3) return null;
        return 2000;
      },
    });

    redisClient.on('connect', () => {
      console.log('[Cache] Redis 연결 성공');
    });

    redisClient.on('error', (err) => {
      console.error('[Cache] Redis 연결 오류:', err.message);
    });
  }
  return redisClient;
}

// ========================================
// 통합 인터페이스
// ========================================

/**
 * 캐시에서 값 조회
 * @param {string} key - 캐시 키
 * @returns {Promise<any|null>} 캐시된 값 또는 null
 */
async function get(key) {
  if (CACHE_TYPE === 'redis') {
    const client = getRedisClient();
    const value = await client.get(key);
    return value ? JSON.parse(value) : null;
  } else {
    // 메모리 캐시
    const entry = memoryCache.get(key);
    if (!entry) return null;

    // 만료 확인
    if (entry.expireAt && entry.expireAt < Date.now()) {
      memoryCache.delete(key);
      return null;
    }

    return entry.value;
  }
}

/**
 * 캐시에 값 저장
 * @param {string} key - 캐시 키
 * @param {any} value - 저장할 값
 * @param {number} ttl - TTL (초), 기본 300초 (5분)
 */
async function set(key, value, ttl = 300) {
  if (CACHE_TYPE === 'redis') {
    const client = getRedisClient();
    await client.set(key, JSON.stringify(value), 'EX', ttl);
  } else {
    // 메모리 캐시
    memoryCache.set(key, {
      value,
      expireAt: Date.now() + ttl * 1000,
    });
  }
}

/**
 * 캐시에서 값 삭제
 * @param {string} key - 캐시 키
 */
async function del(key) {
  if (CACHE_TYPE === 'redis') {
    const client = getRedisClient();
    await client.del(key);
  } else {
    memoryCache.delete(key);
  }
}

module.exports = { get, set, del };
