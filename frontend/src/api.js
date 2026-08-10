import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '',
});

// Request interceptor: attach Authorization header
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor: handle 401
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('token');
    }
    return Promise.reject(error);
  }
);

// Auth API
export const authAPI = {
  signup: (data) => api.post('/api/auth/signup', data),
  login: (data) => api.post('/api/auth/login', data),
  getMe: () => api.get('/api/auth/me'),
};

// Products API
export const productsAPI = {
  getAll: (params) => api.get('/api/products', { params }),
  getById: (id) => api.get(`/api/products/${id}`),
};

// Reviews API
export const reviewsAPI = {
  getByProduct: (productId) => api.get(`/api/products/${productId}/reviews`),
  create: (productId, data) => api.post(`/api/products/${productId}/reviews`, data),
};

// Cart API
export const cartAPI = {
  getAll: () => api.get('/api/cart'),
  addItem: (data) => api.post('/api/cart', data),
  updateItem: (itemId, data) => api.put(`/api/cart/${itemId}`, data),
  removeItem: (itemId) => api.delete(`/api/cart/${itemId}`),
  clear: () => api.delete('/api/cart'),
};

// Orders API
export const ordersAPI = {
  create: () => api.post('/api/orders'),
  getAll: () => api.get('/api/orders'),
};

// Upload API — Pre-signed PUT URL 방식 (브라우저에서 S3로 직접 업로드)
// ALB/WAF를 거치지 않으므로 WAF 바디 크기 제한 문제 없음
export const uploadAPI = {
  uploadFile: async (file) => {
    // 1. 백엔드에서 pre-signed PUT URL 발급
    const { data: { uploadUrl, fileUrl } } = await api.post('/api/upload/presigned', {
      fileName: file.name,
      fileType: file.type,
    });

    // 2. S3에 직접 PUT (api 인스턴스 사용 금지 — Authorization 헤더가 서명을 깨뜨림)
    await axios.put(uploadUrl, file, {
      headers: { 'Content-Type': file.type },
    });

    // 3. ReviewForm이 기대하는 형식으로 반환
    return { data: { fileUrl } };
  },
};

export default api;
