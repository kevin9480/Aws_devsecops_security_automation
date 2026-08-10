/**
 * S3 이미지 URL → Pre-signed URL 변환 미들웨어
 * - S3 모드에서 응답의 이미지 URL을 Pre-signed URL로 변환
 * - 로컬 모드에서는 패스스루
 */

const { getPresignedGetUrl } = require('../services/storage');

/**
 * 응답 바디를 재귀적으로 순회하며 S3 URL을 Pre-signed URL로 변환
 */
async function transformUrls(obj) {
  if (typeof obj === 'string') {
    return getPresignedGetUrl(obj);
  }
  if (Array.isArray(obj)) {
    return Promise.all(obj.map(transformUrls));
  }
  if (obj !== null && typeof obj === 'object') {
    const result = {};
    for (const [key, value] of Object.entries(obj)) {
      result[key] = await transformUrls(value);
    }
    return result;
  }
  return obj;
}

const presignUrlsMiddleware = (req, res, next) => {
  // 로컬 모드에서는 변환 없이 패스
  if (process.env.STORAGE_TYPE !== 's3') {
    return next();
  }

  // S3 모드: 응답 JSON의 S3 URL을 Pre-signed URL로 변환
  const originalJson = res.json.bind(res);
  res.json = async (body) => {
    try {
      body = await transformUrls(body);
    } catch (err) {
      console.error('[presignUrls] URL 변환 오류:', err.message);
    }
    originalJson(body);
  };

  next();
};

module.exports = presignUrlsMiddleware;
